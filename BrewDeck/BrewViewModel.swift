import Combine
import Foundation

@MainActor
class BrewViewModel: ObservableObject {
    @Published var installedPackages: [Package] = [] {
        didSet { saveCache() }
    }

    @Published var outdatedPackages: [OutdatedPackageInfo] = []
    @Published var searchResults: [Package] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var operationOutput: String = ""
    @Published var isRunningOperation = false
    @Published var showLogs = false
    @Published var totalDiskUsage: Int64 = 0

    private let service = BrewService.shared
    private var searchTask: Task<Void, Never>?
    private let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "brew_cache.json")

    var formattedTotalSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalDiskUsage)
    }

    init() {
        print("📱 BrewViewModel Initialized. Service Version: \(BrewService.version)")
        loadCache()
        Task {
            await refresh()
        }
    }

    private func saveCache() {
        try? JSONEncoder().encode(installedPackages).write(to: cacheURL)
    }

    private func loadCache() {
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode([Package].self, from: data)
        {
            installedPackages = cached
            totalDiskUsage = cached.compactMap(\.sizeOnDisk).reduce(0, +)
        }
    }

    func refresh() async {
        isLoading = true
        error = nil

        do {
            let installed = try await service.fetchInstalledPackages()

            // Fetch outdated in parallel
            async let outdated = service.fetchOutdatedPackages()
            let fetchedOutdated = await (try? outdated) ?? []

            await MainActor.run {
                self.installedPackages = installed
                self.outdatedPackages = fetchedOutdated
                self.totalDiskUsage = installed.compactMap(\.sizeOnDisk).reduce(0, +)
                self.isLoading = false
            }
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    func search(query: String) async {
        if query.count < 2 {
            searchResults = []
            return
        }

        isLoading = true
        do {
            let results = try await service.searchPackages(query: query)
            searchResults = results
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    func install(package: String) async {
        isRunningOperation = true
        showLogs = true
        operationOutput = "Starting installation of \(package)...\n"

        for await output in service.performAction(arguments: ["install", "--", package]) {
            operationOutput += output
        }

        isRunningOperation = false
        await refresh()
    }

    func uninstall(package: Package) async {
        isRunningOperation = true
        showLogs = true
        operationOutput = "Starting uninstallation of \(package.name)...\n"

        let args: [String] = if package.type == .cask {
            ["uninstall", "--cask", "--zap", "--", package.name]
        } else {
            ["uninstall", "--", package.name]
        }

        for await output in service.performAction(arguments: args) {
            operationOutput += output
        }

        isRunningOperation = false
        await refresh()
    }

    func upgrade(package: String) async {
        isRunningOperation = true
        showLogs = true
        operationOutput = "Starting upgrade of \(package)...\n"

        for await output in service.performAction(arguments: ["upgrade", "--", package]) {
            operationOutput += output
        }

        isRunningOperation = false
        await refresh()
    }

    func upgradeAll() async {
        isRunningOperation = true
        showLogs = true
        operationOutput = "Starting upgrade of all outdated packages...\n"

        for await output in service.performAction(arguments: ["upgrade"]) {
            operationOutput += output
        }

        isRunningOperation = false
        await refresh()
    }
}
