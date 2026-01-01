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

    // MARK: - Constants

    private static let autoUpdateInterval: TimeInterval = 24 * 60 * 60 // 24 hours

    // MARK: - Formatters

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

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

        // Auto-start auto-update if it was previously enabled
        if self.autoUpdateEnabled {
            self.startAutoUpdate()
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
        // Cancel any existing task first to avoid overlapping tasks
        self.autoUpdateTask?.cancel()

        // Create new task - the caller (setAutoUpdateEnabled) has already verified autoUpdateEnabled is true
        self.autoUpdateTask = Task {
            while !Task.isCancelled {
                // Check if auto-update is still enabled before performing update
                guard self.autoUpdateEnabled else { break }

                await self.performAutoUpdate()

                // Check again after update before sleeping
                guard self.autoUpdateEnabled, !Task.isCancelled else { break }

                try? await Task.sleep(for: .seconds(Self.autoUpdateInterval))
            }
        }
    }

    private func stopAutoUpdate() {
        self.autoUpdateTask?.cancel()
        self.autoUpdateTask = nil
    }

    deinit {
        // Ensure any ongoing auto-update task is cancelled when the view model is deallocated
        self.autoUpdateTask?.cancel()
    }

    private func performAutoUpdate() async {
        guard self.autoUpdateEnabled, !Task.isCancelled else { return }

        // Set operation lock to prevent concurrent operations
        await MainActor.run {
            self.isRunningOperation = true
        }

        // Ensure lock is always cleared when exiting
        defer {
            Task { @MainActor in
                self.isRunningOperation = false
            }
        }

        do {
            let outdated = try await self.service.fetchOutdatedPackages()

            // Check for cancellation after network call
            guard !Task.isCancelled else { return }

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
                // Check for cancellation during streaming output
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.operationOutput += output
                }
            }

            // Final cancellation check before completing
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.lastAutoUpdateTime = Date()
                // Append completion message
                self.operationOutput += "\n✅ Auto-update completed successfully at \(Date().formatted(date: .omitted, time: .standard))"
            }

            await self.refresh()

            // Auto-hide logs after 30 seconds for background auto-updates
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // Note: isRunningOperation is already cleared by defer, so we can't check it here
                // Just hide the logs if task wasn't cancelled
                self.showLogs = false
            }
        } catch {
            // Only show error if not cancelled
            guard !Task.isCancelled else { return }
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

        let timeString = Self.relativeDateFormatter.localizedString(for: lastTime, relativeTo: Date())

        return "Last auto-update: \(timeString)"
    }
}
