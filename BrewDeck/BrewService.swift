import Foundation

enum BrewError: LocalizedError {
    case brewNotFound
    case commandFailed(String)
    case parsingError
    case timeout
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .brewNotFound: return "Homebrew not found. Please ensure it is installed."
        case .commandFailed(let detail): return detail
        case .parsingError: return "Failed to parse Homebrew output."
        case .timeout: return "The Homebrew command timed out."
        case .permissionDenied: return "Permission Denied (OS 0x5). Please disable App Sandbox in Xcode and Clean the project (Cmd+Option+Shift+K)."
        }
    }
}

class BrewService {
    static let shared = BrewService()
    static let version = "2.1.0" // Version marker for debugging
    
    private let brewPath: String
    private let askPassPath: String = "/tmp/brewdeck-askpass.sh"
    
    init() {
        let paths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew", "/usr/bin/brew"]
        self.brewPath = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? "/opt/homebrew/bin/brew"
        setupAskPass()
        print("🚀 BrewService Initialized (v\(BrewService.version)). Brew path: \(brewPath)")
    }
    
    private func setupAskPass() {
        let script = """
        #!/bin/bash
        osascript -e 'display dialog "BrewDeck needs administrator privileges to complete this action. Please enter your password:" default answer "" with title "Privileged Action" with hidden answer' -e 'text returned of result'
        """
        
        do {
            try script.write(toFile: askPassPath, atomically: true, encoding: .utf8)
            let attributes = [FileAttributeKey.posixPermissions: 0o755]
            try FileManager.default.setAttributes(attributes, ofItemAtPath: askPassPath)
        } catch {
            print("❌ Failed to setup askpass: \(error)")
        }
    }
    
    func run(arguments: [String], timeoutSeconds: Double = 30.0) async throws -> String {
        guard !arguments.isEmpty else { return "" }
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let errorPipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: self.brewPath)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = errorPipe
            
            var env = ProcessInfo.processInfo.environment
            env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
            env["HOMEBREW_NO_ANALYTICS"] = "1"
            env["HOMEBREW_COLOR"] = "0"
            env["SUDO_ASKPASS"] = self.askPassPath
            env["DISPLAY"] = ":0"
            process.environment = env
            
            let outputData = NSMutableData()
            let errorData = NSMutableData()
            
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { outputData.append(data) }
            }
            
            errorPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { errorData.append(data) }
            }
            
            var isFinished = false
            let lock = NSLock()
            
            func finish(throwing error: Error? = nil, result: String? = nil) {
                lock.lock()
                defer { lock.unlock() }
                guard !isFinished else { return }
                isFinished = true
                
                // Stop readability handlers
                pipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let result = result {
                    continuation.resume(returning: result)
                }
            }
            
            process.terminationHandler = { process in
                if process.terminationStatus != 0 {
                    let errorMessage = String(data: errorData as Data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    finish(throwing: BrewError.commandFailed(errorMessage.isEmpty ? "Exit code \(process.terminationStatus)" : errorMessage))
                } else {
                    if let output = String(data: outputData as Data, encoding: .utf8) {
                        finish(result: output)
                    } else {
                        finish(throwing: BrewError.parsingError)
                    }
                }
            }
            
            // Timeout handling
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
                if process.isRunning {
                    process.terminate()
                    finish(throwing: BrewError.timeout)
                }
            }
            
            do {
                print("🛠 BrewDeck: Executing \(arguments.joined(separator: " "))")
                try process.run()
            } catch {
                if (error as NSError).code == 1 || (error as NSError).code == 5 {
                    finish(throwing: BrewError.permissionDenied)
                } else {
                    finish(throwing: BrewError.commandFailed("Launch failed: \(error.localizedDescription)"))
                }
            }
        }
    }
    
    func fetchInstalledPackages() async throws -> [Package] {
        let sizes = await fetchPackageSizes()
        let output = try await run(arguments: ["info", "--json=v2", "--installed"], timeoutSeconds: 20)
        let data = Data(output.utf8)
        let response = try JSONDecoder().decode(BrewInfoResponse.self, from: data)
        
        let formulae = response.formulae.map { formula -> Package in
            var pkg = Package(from: formula)
            pkg.sizeOnDisk = sizes[pkg.name]
            return pkg
        }
        
        let casks = response.casks.map { cask -> Package in
            var pkg = Package(from: cask)
            pkg.sizeOnDisk = sizes[pkg.name]
            return pkg
        }
        
        return formulae + casks
    }
    
    func fetchOutdatedPackages() async throws -> [OutdatedPackageInfo] {
        let output = try await run(arguments: ["outdated", "--json=v2"], timeoutSeconds: 20)
        let response = try JSONDecoder().decode(OutdatedResponse.self, from: Data(output.utf8))
        var outdated: [OutdatedPackageInfo] = []
        outdated += response.formulae.map { OutdatedPackageInfo(name: $0.name, type: .formula, installedVersion: $0.installedVersions.first ?? "", latestVersion: $0.currentVersion) }
        outdated += response.casks.map { OutdatedPackageInfo(name: $0.name, type: .cask, installedVersion: $0.installedVersions.first ?? "", latestVersion: $0.currentVersion) }
        return outdated
    }
    
    func searchPackages(query: String) async throws -> [Package] {
        if query.count < 2 { return [] }
        let output = try await run(arguments: ["search", "--", query], timeoutSeconds: 15)
        let names = output.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains("==>") && !$0.localizedCaseInsensitiveContains("Formulae") && !$0.localizedCaseInsensitiveContains("Casks") }
        
        if names.isEmpty { return [] }
        let limitedNames = Array(names.prefix(15))
        let infoOutput = try await run(arguments: ["info", "--json=v2", "--"] + limitedNames, timeoutSeconds: 15)
        let response = try JSONDecoder().decode(BrewInfoResponse.self, from: Data(infoOutput.utf8))
        return response.formulae.map { Package(from: $0) } + response.casks.map { Package(from: $0) }
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
    
    func runShell(command: String, timeoutSeconds: Double = 30.0) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.standardOutput = pipe
            process.standardError = pipe
            
            process.terminationHandler = { process in
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
    
    func fetchPackageSizes() async -> [String: Int64] {
        let cellarPath = brewPath.replacingOccurrences(of: "/bin/brew", with: "/Cellar")
        let caskroomPath = brewPath.replacingOccurrences(of: "/bin/brew", with: "/Caskroom")
        
        // du -sk returns size in KB
        let command = "du -sk '\(cellarPath)'/* '\(caskroomPath)'/* 2>/dev/null"
        let output = (try? await runShell(command: command)) ?? ""
        
        var sizes: [String: Int64] = [:]
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 2, let kb = Int64(parts[0]) {
                let path = parts[1]
                let name = (path as NSString).lastPathComponent
                sizes[name] = kb * 1024 // Convert to bytes
            }
        }
        return sizes
    }
}
