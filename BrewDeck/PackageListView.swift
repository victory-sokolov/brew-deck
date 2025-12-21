import SwiftUI

struct PackageListView: View {
    let mode: NavigationItem
    @ObservedObject var viewModel: BrewViewModel
    @Binding var selectedPackage: Package?
    
    @State private var searchText = ""
    @State private var filter: PackageType? = nil
    @State private var showOnlyOutdated = false
    
    var filteredPackages: [Package] {
        let source: [Package]
        switch mode {
        case .search:
            source = viewModel.searchResults
        case .installed:
            source = viewModel.installedPackages
        case .updates:
            source = viewModel.installedPackages.filter { pkg in
                viewModel.outdatedPackages.contains { $0.name == pkg.name }
            }
        case .allPackages:
            // This would ideally be a huge list, but for now let's just show everything we know
            source = viewModel.installedPackages // Placeholder
        case .settings:
            source = []
        }
        
        return source.filter { pkg in
            let matchesSearch = searchText.isEmpty || pkg.name.localizedCaseInsensitiveContains(searchText) || (pkg.description?.localizedCaseInsensitiveContains(searchText) ?? false)
            let matchesFilter = filter == nil || pkg.type == filter
            let matchesOutdated = !showOnlyOutdated || viewModel.outdatedPackages.contains { $0.name == pkg.name }
            return matchesSearch && matchesFilter && matchesOutdated
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
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
                        viewModel.error = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.red.opacity(0.8))
                .cornerRadius(8)
                .padding([.horizontal, .bottom])
            }
            
            if viewModel.isLoading && filteredPackages.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                List(filteredPackages, selection: $selectedPackage) { package in
                    PackageRow(package: package, isOutdated: viewModel.outdatedPackages.contains { $0.name == package.name })
                        .tag(package)
                }
            }
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text(mode.rawValue)
                        .font(.title)
                        .bold()
                    HStack(spacing: 8) {
                        Text("\(filteredPackages.count) items")
                        
                        if mode == .installed || mode == .updates {
                            Text("•")
                            Text(viewModel.formattedTotalSize)
                                .foregroundStyle(.blue)
                                .bold()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if mode == .updates || mode == .installed {
                    Button {
                        Task { await viewModel.upgradeAll() }
                    } label: {
                        Label("Update All", systemImage: "arrow.clockwise.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isRunningOperation)
                }
            }
            
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search \(mode == .search ? "all" : "installed") packages...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onChange(of: searchText) { newValue in
                            if mode == .search {
                                Task { await viewModel.search(query: newValue) }
                            }
                        }
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
                
                Picker("", selection: $filter) {
                    Text("All Types").tag(nil as PackageType?)
                    Text("Formulae").tag(PackageType.formula)
                    Text("Casks").tag(PackageType.cask)
                }
                .frame(width: 120)
                .pickerStyle(.menu)
            }
            
            HStack(spacing: 8) {
                FilterButton(title: "All", isActive: filter == nil) { filter = nil }
                FilterButton(title: "Formulae", isActive: filter == .formula) { filter = .formula }
                FilterButton(title: "Casks", isActive: filter == .cask) { filter = .cask }
                
                if mode == .installed {
                    FilterButton(title: "Outdated", isActive: showOnlyOutdated) {
                        showOnlyOutdated.toggle()
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
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? Color.blue : Color.secondary.opacity(0.1))
                .foregroundStyle(isActive ? .white : .primary)
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
            PackageIcon(type: package.type)
                .frame(width: 44, height: 44)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(package.name)
                        .font(.headline)
                    
                    if isOutdated {
                        Text("OUTDATED")
                            .font(.system(size: 8, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                            .foregroundStyle(.orange)
                    }
                }
                
                Text(package.description ?? "No description available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if let version = package.installedVersion {
                    Text(version)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                Circle()
                    .fill(package.isInstalled ? Color.green : Color.secondary.opacity(0.2))
                    .frame(width: 8, height: 8)
                    .shadow(color: package.isInstalled ? .green.opacity(0.5) : .clear, radius: 2)
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
                        colors: type == .formula ? [.purple, .indigo] : [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: (type == .formula ? Color.purple : Color.blue).opacity(0.3), radius: 4, x: 0, y: 2)
            
            Image(systemName: type == .formula ? "terminal.fill" : "macwindow")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}
