import Combine
import Foundation
import SwiftUI

@MainActor
class BrewViewModel: ObservableObject {
    @Published var installedPackages: [Package] = [] {
        didSet { self.saveCache() }
    }

    @Published var outdatedPackages: [OutdatedPackageInfo] = []
    @Published var searchResults: [Package] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var operationOutput: String = ""
    @Published var isRunningOperation = false
    @Published var showLogs = false
    @Published var totalDiskUsage: Int64 = 0

    @AppStorage("autoUpdateEnabled") private(set) var autoUpdateEnabled = false
    @Published var lastAutoUpdateTime: Date?

    private let service = BrewService.shared
    private var searchTask: Task<Void, Never>?
    private var autoUpdateTask: Task<Void, Never>?
    private let cacheURL = FileManager.default.temporaryDirectory.appending(path: "brew_cache.json")

    var formattedTotalSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: self.totalDiskUsage)
    }

    init() {
        print("📱 BrewViewModel Initialized. Service Version: \(BrewService.version)")
        self.loadCache()
        Task {
            await self.refresh()
        }
    }

    private func saveCache() {
        do {
            try JSONEncoder().encode(self.installedPackages).write(to: self.cacheURL)
        } catch {
            print("Error saving cache: \(error)")
            self.error = "Failed to save cache: \(error.localizedDescription)"
        }
    }

    private func loadCache() {
        do {
            let data = try Data(contentsOf: cacheURL)
            let cached = try JSONDecoder().decode([Package].self, from: data)
            self.installedPackages = cached
            self.totalDiskUsage = cached.compactMap(\.sizeOnDisk).reduce(0, +)
        } catch {
            print("Error loading cache: \(error)")
            // Cache doesn't exist or is corrupted, start fresh
        }
    }

    func refresh() async {
        self.isLoading = true
        self.error = nil

        do {
            let installed = try await service.fetchInstalledPackages()

            // Fetch outdated in parallel
            async let outdated = self.service.fetchOutdatedPackages()
            let fetchedOutdated = try await outdated

            await MainActor.run {
                self.installedPackages = installed
                self.outdatedPackages = fetchedOutdated
                self.totalDiskUsage = installed.compactMap(\.sizeOnDisk).reduce(0, +)
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func search(query: String) async {
        if query.count < 2 {
            self.searchResults = []
            return
        }

        self.isLoading = true
        do {
            let results = try await service.searchPackages(query: query)
            self.searchResults = results
            self.isLoading = false
        } catch {
            self.error = error.localizedDescription
            self.isLoading = false
        }
    }

    func install(package: String) async {
        self.isRunningOperation = true
        self.showLogs = true
        self.operationOutput = "Starting installation of \(package)...\n"

        for await output in self.service.performAction(arguments: ["install", "--", package]) {
            self.operationOutput += output
        }

        self.isRunningOperation = false
        await self.refresh()
    }

    func uninstall(package: Package) async {
        self.isRunningOperation = true
        self.showLogs = true
        self.operationOutput = "Starting uninstallation of \(package.name)...\n"

        let args: [String] =
            if package.type == .cask {
                ["uninstall", "--cask", "--zap", "--", package.name]
            } else {
                ["uninstall", "--", package.name]
            }

        for await output in self.service.performAction(arguments: args) {
            self.operationOutput += output
        }

        self.isRunningOperation = false
        await self.refresh()
    }

    func upgrade(package: String) async {
        self.isRunningOperation = true
        self.showLogs = true
        self.operationOutput = "Starting upgrade of \(package)...\n"

        for await output in self.service.performAction(arguments: ["upgrade", "--", package]) {
            self.operationOutput += output
        }

        self.isRunningOperation = false
        await self.refresh()
    }

    func upgradeAll() async {
        self.isRunningOperation = true
        self.showLogs = true
        self.operationOutput = "Starting upgrade of all outdated packages...\n"

        for await output in self.service.performAction(arguments: ["upgrade"]) {
            self.operationOutput += output
        }

        self.isRunningOperation = false
        await self.refresh()
    }

    func setAutoUpdateEnabled(_ enabled: Bool) {
        self.autoUpdateEnabled = enabled

        if enabled {
            self.startAutoUpdate()
        } else {
            self.stopAutoUpdate()
        }
    }

    private func startAutoUpdate() {
        guard self.autoUpdateEnabled else { return }

        self.autoUpdateTask?.cancel()

        self.autoUpdateTask = Task {
            while self.autoUpdateEnabled, !Task.isCancelled {
                await self.performAutoUpdate()

                let updateInterval: TimeInterval = 24 * 60 * 60
                try? await Task.sleep(for: .seconds(updateInterval))

                if Task.isCancelled { break }
            }
        }
    }

    private func stopAutoUpdate() {
        self.autoUpdateTask?.cancel()
        self.autoUpdateTask = nil
    }

    private func performAutoUpdate() async {
        guard self.autoUpdateEnabled else { return }

        do {
            let outdated = try await self.service.fetchOutdatedPackages()

            guard !outdated.isEmpty else {
                await MainActor.run {
                    self.lastAutoUpdateTime = Date()
                }
                return
            }

            await MainActor.run {
                self.operationOutput = "Auto-updating \(outdated.count) package(s)...\n"
                self.showLogs = true
            }

            for await output in self.service.performAction(arguments: ["upgrade"]) {
                await MainActor.run {
                    self.operationOutput += output
                }
            }

            await MainActor.run {
                self.lastAutoUpdateTime = Date()
            }

            await self.refresh()
        } catch {
            await MainActor.run {
                self.error = "Auto-update failed: \(error.localizedDescription)"
            }
        }
    }

    var autoUpdateStatusMessage: String {
        if !self.autoUpdateEnabled {
            return "Auto-update is disabled"
        }

        guard let lastTime = self.lastAutoUpdateTime else {
            return "Auto-update enabled (waiting for next check)"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let timeString = formatter.localizedString(for: lastTime, relativeTo: Date())

        return "Last auto-update: \(timeString)"
    }
}
