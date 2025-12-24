//
//  BrewService+Extensions.swift
//  BrewDeck
//
//  Created by Viktor Sokolov on 24/12/2025.
//

import Foundation

extension BrewService {
    func fetchInstalledPackages() async throws -> [Package] {
        let sizes = await fetchPackageSizes()
        let output = try await run(arguments: ["info", "--json=v2", "--installed"], timeoutSeconds: 60)
        let data = Data(output.utf8)
        let response = try JSONDecoder().decode(BrewInfoResponse.self, from: data)

        let formulae = response.formulae.map { formula -> Package in
            var pkg = Package(from: formula)

            // Only try to fetch size from du if JSON didn't provide it
            if pkg.sizeOnDisk == nil || pkg.sizeOnDisk == 0 {
                let shortName = pkg.name.components(separatedBy: "/").last ?? pkg.name
                let variations = [pkg.name, shortName, pkg.name.lowercased(), shortName.lowercased()]

                for variation in variations {
                    if let fetchedSize = sizes[variation] {
                        pkg.sizeOnDisk = fetchedSize
                        print("📦 Set size for \(pkg.name) from du: \(fetchedSize) bytes")
                        break
                    }
                }

                if pkg.sizeOnDisk == nil {
                    print("⚠️ No size found for formula: \(pkg.name)")
                }
            } else {
                print("✅ Using JSON size for \(pkg.name): \(pkg.sizeOnDisk!) bytes")
            }

            return pkg
        }

        let casks = response.casks.map { cask -> Package in
            var pkg = Package(from: cask)

            // Casks don't have installedSize in JSON, so always try to fetch from du
            let shortName = pkg.name.components(separatedBy: "/").last ?? pkg.name
            let variations = [pkg.name, shortName, pkg.name.lowercased(), shortName.lowercased()]

            for variation in variations {
                if let fetchedSize = sizes[variation] {
                    pkg.sizeOnDisk = fetchedSize
                    print("📦 Set size for cask \(pkg.name) from du: \(fetchedSize) bytes")
                    break
                }
            }

            if pkg.sizeOnDisk == nil {
                print("⚠️ No size found for cask: \(pkg.name)")
            }

            return pkg
        }

        return formulae + casks
    }

    func fetchOutdatedPackages() async throws -> [OutdatedPackageInfo] {
        let output = try await run(arguments: ["outdated", "--json=v2"], timeoutSeconds: 60)
        let response = try JSONDecoder().decode(OutdatedResponse.self, from: Data(output.utf8))
        var outdated: [OutdatedPackageInfo] = []
        outdated += response.formulae.map {
            OutdatedPackageInfo(
                name: $0.name,
                type: .formula,
                installedVersion: $0.installedVersions.first ?? "",
                latestVersion: $0.currentVersion
            )
        }
        outdated += response.casks.map {
            OutdatedPackageInfo(
                name: $0.name,
                type: .cask,
                installedVersion: $0.installedVersions.first ?? "",
                latestVersion: $0.currentVersion
            )
        }
        return outdated
    }

    func searchPackages(query: String) async throws -> [Package] {
        if query.count < 2 { return [] }
        let output = try await run(arguments: ["search", "--", query], timeoutSeconds: 30)
        let names = output.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                !$0.isEmpty && !$0.contains("==>") &&
                !$0.localizedCaseInsensitiveContains("Formulae") &&
                !$0.localizedCaseInsensitiveContains("Casks")
            }

        if names.isEmpty { return [] }
        let limitedNames = Array(names.prefix(15))
        let infoOutput = try await run(arguments: ["info", "--json=v2", "--"] + limitedNames, timeoutSeconds: 30)
        let response = try JSONDecoder().decode(BrewInfoResponse.self, from: Data(infoOutput.utf8))
        return response.formulae.map { Package(from: $0) } + response.casks.map { Package(from: $0) }
    }

    func fetchPackageSizes() async -> [String: Int64] {
        // Get correct paths from brew
        let cellarPath = (try? await run(arguments: ["--cellar"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let caskroomPath = (try? await run(arguments: ["--caskroom"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var pathsToScan: [String] = []
        if !cellarPath.isEmpty, FileManager.default.fileExists(atPath: cellarPath) {
            pathsToScan.append("'\(cellarPath)'/*")
        }
        if !caskroomPath.isEmpty, FileManager.default.fileExists(atPath: caskroomPath) {
            pathsToScan.append("'\(caskroomPath)'/*")
        }

        guard !pathsToScan.isEmpty else {
            print("⚠️ No paths to scan for package sizes")
            return [:]
        }

        // Use du -sk with glob pattern to get sizes of all subdirectories
        // Note: -d 1 doesn't work properly on macOS, so we use /* instead
        let command = "du -sk \(pathsToScan.joined(separator: " ")) 2>/dev/null"
        print("🛠 Executing size command: \(command)")
        let output = (try? await runShell(command: command)) ?? ""
        print("📊 du output length: \(output.count) characters")

        let parsed = BrewService.parseDuOutput(output)
        print("📦 Parsed \(parsed.count) package sizes")

        // Print first few entries for debugging
        if !parsed.isEmpty {
            let sample = parsed.prefix(5)
            print("📋 Sample sizes: \(sample)")
        }

        // Also add a simplified name mapping for all parsed sizes for fuzzy matching
        var normalizedSizes: [String: Int64] = [:]
        for (key, value) in parsed {
            normalizedSizes[key] = value
            normalizedSizes[key.lowercased()] = value
        }
        return normalizedSizes
    }

    static func parseDuOutput(_ output: String) -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            if line.isEmpty { continue }

            // du output is typically "size\tpath"
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)

            if parts.count == 2 {
                let sizeStr = parts[0].trimmingCharacters(in: .whitespaces)
                let path = parts[1]
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if let sizeInKb = Int64(sizeStr) {
                    let name = (path as NSString).lastPathComponent
                    // Ignore the base directories themselves (Cellar/Caskroom) which represent totals
                    if !name.isEmpty && name.lowercased() != "cellar" && name.lowercased() != "caskroom" {
                        sizes[name] = sizeInKb * 1024
                    }
                }
            } else {
                // Fallback for space-separated output or other formats
                let scanner = Scanner(string: line)
                var sizeInKb: Int64 = 0
                if scanner.scanInt64(&sizeInKb) {
                    let remaining = line
                        .dropFirst(scanner.currentIndex.utf16Offset(in: line))
                        .trimmingCharacters(in: .whitespaces)
                    if !remaining.isEmpty {
                        let path = remaining.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        let name = (path as NSString).lastPathComponent
                        if !name.isEmpty, name.lowercased() != "cellar", name.lowercased() != "caskroom" {
                            sizes[name] = sizeInKb * 1024
                        }
                    }
                }
            }
        }
        return sizes
    }

    func performAction(arguments: [String]) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: brewPath)
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe

                var env = ProcessInfo.processInfo.environment
                env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
                env["HOMEBREW_COLOR"] = "0"
                env["SUDO_ASKPASS"] = self.askPassPath
                env["DISPLAY"] = ":0"
                process.environment = env

                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                        continuation.yield(output)
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()
                    pipe.fileHandleForReading.readabilityHandler = nil
                    continuation.finish()
                } catch {
                    continuation.yield("Error: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
        }
    }

    func runShell(command: String, timeoutSeconds _: Double = 30.0) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.standardOutput = pipe
            process.standardError = pipe

            process.terminationHandler = { _ in
                let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
