import SwiftUI

struct PackageListView: View {
    let mode: NavigationItem
    @ObservedObject var viewModel: BrewViewModel
    @Binding var selectedPackage: Package?

    @State private var searchText = ""
    @State private var filter: PackageType?
    @State private var showOnlyOutdated = false

    var filteredPackages: [Package] {
        let source: [Package] =
            switch self.mode {
            case .search:
                self.viewModel.searchResults
            case .installed:
                self.viewModel.installedPackages
            case .updates:
                self.viewModel.installedPackages.filter { pkg in
                    self.viewModel.outdatedPackages.contains { $0.name == pkg.name }
                }
            case .settings:
                []
            }

        return source.filter { pkg in
            let matchesSearch =
                self.searchText.isEmpty || pkg.name.localizedCaseInsensitiveContains(self.searchText)
                || (pkg.description?.localizedCaseInsensitiveContains(self.searchText) ?? false)
            let matchesFilter = self.filter == nil || pkg.type == self.filter
            let matchesOutdated =
                !self.showOnlyOutdated || self.viewModel.outdatedPackages.contains { $0.name == pkg.name }
            return matchesSearch && matchesFilter && matchesOutdated
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            self.header

            if let error = viewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.white)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        self.viewModel.error = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss error")
                }
                .padding(8)
                .background(Color.red.opacity(0.8))
                .cornerRadius(8)
                .padding([.horizontal, .bottom])
            }

            if self.viewModel.isLoading, self.filteredPackages.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                List(self.filteredPackages, selection: self.$selectedPackage) { package in
                    PackageRow(
                        package: package,
                        isOutdated: self.viewModel.outdatedPackages.contains { $0.name == package.name })
                        .tag(package)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text(self.mode.rawValue)
                        .font(.title)
                        .bold()
                    HStack(spacing: 8) {
                        Text("\(self.filteredPackages.count) items")

                        if self.mode == .installed || self.mode == .updates {
                            Text("•")
                            Text(self.viewModel.formattedTotalSize)
                                .foregroundStyle(.blue)
                                .bold()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if self.mode == .updates || self.mode == .installed {
                    Button {
                        Task { await self.viewModel.upgradeAll() }
                    } label: {
                        Label("Update All", systemImage: "arrow.clockwise.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(self.viewModel.isRunningOperation)
                    .accessibilityHint("Updates all outdated packages to their latest versions")
                }
            }

            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(
                        "Search \(self.mode == .search ? "all" : "installed") packages...",
                        text: self.$searchText)
                        .textFieldStyle(.plain)
                        .onChange(of: self.searchText) { newValue in
                            if self.mode == .search {
                                Task { await self.viewModel.search(query: newValue) }
                            }
                        }

                    if !self.searchText.isEmpty {
                        Button {
                            self.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1))

                Picker("", selection: self.$filter) {
                    Text("All Types").tag(nil as PackageType?)
                    Text("Formulae").tag(PackageType.formula)
                    Text("Casks").tag(PackageType.cask)
                }
                .frame(width: 120)
                .pickerStyle(.menu)
            }

            HStack(spacing: 8) {
                FilterButton(title: "All", isActive: self.filter == nil) { self.filter = nil }
                FilterButton(title: "Formulae", isActive: self.filter == .formula) { self.filter = .formula }
                FilterButton(title: "Casks", isActive: self.filter == .cask) { self.filter = .cask }

                if self.mode == .installed {
                    FilterButton(title: "Outdated", isActive: self.showOnlyOutdated) {
                        self.showOnlyOutdated.toggle()
                    }
                }
            }
        }
        .padding()
    }
}

struct FilterButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Text(self.title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(self.isActive ? Color.blue : Color.secondary.opacity(0.1))
                .foregroundStyle(self.isActive ? .white : .primary)
                .cornerRadius(15)
        }
        .buttonStyle(.plain)
    }
}

struct PackageRow: View {
    let package: Package
    let isOutdated: Bool

    var body: some View {
        HStack(spacing: 16) {
            PackageIcon(type: self.package.type)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(self.package.name)
                        .font(.headline)

                    if self.isOutdated {
                        Text("OUTDATED")
                            .font(.system(size: 8, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                            .foregroundStyle(.orange)
                    }
                }

                Text(self.package.description ?? "No description available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let size = package.formattedSize {
                    Text(size)
                        .font(.caption2)
                        .foregroundStyle(.blue.opacity(0.8))
                }

                if let version = package.installedVersion {
                    Text(version)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Circle()
                    .fill(self.package.isInstalled ? Color.green : Color.secondary.opacity(0.2))
                    .frame(width: 8, height: 8)
                    .shadow(color: self.package.isInstalled ? .green.opacity(0.5) : .clear, radius: 2)
                    .accessibilityLabel(self.package.isInstalled ? "Installed" : "Not installed")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

struct PackageIcon: View {
    let type: PackageType

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: self.type == .formula ? [.purple, .indigo] : [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
                .shadow(
                    color: (self.type == .formula ? Color.purple : Color.blue).opacity(0.3),
                    radius: 4,
                    x: 0,
                    y: 2)

            Image(systemName: self.type == .formula ? "terminal.fill" : "macwindow")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}
