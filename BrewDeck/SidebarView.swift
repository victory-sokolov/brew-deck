import SwiftUI

enum NavigationItem: String, Hashable, CaseIterable {
    case search = "Search"
    case installed = "Installed"
    case updates = "Updates"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .search: "magnifyingglass"
        case .installed: "shippingbox"
        case .updates: "arrow.clockwise"
        case .settings: "gearshape"
        }
    }
}

struct SidebarView: View {
    @Binding var selection: NavigationItem?
    @ObservedObject var viewModel: BrewViewModel

    var body: some View {
        List(selection: self.$selection) {
            Section("Main") {
                ForEach([NavigationItem.search, .installed, .updates], id: \.self) { item in
                    NavigationLink(value: item) {
                        Label(item.rawValue, systemImage: item.icon)
                            .badge(self.badgeFor(item))
                    }
                    .accessibilityValue(self.badgeFor(item) > 0 ? "\(self.badgeFor(item)) items" : "")
                }
            }

            Spacer()

            Section("System") {
                NavigationLink(value: NavigationItem.settings) {
                    Label(
                        NavigationItem.settings.rawValue,
                        systemImage: NavigationItem.settings.icon)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                Button {
                    Task { await self.viewModel.refresh() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .symbolEffect(
                                .pulse,
                                options: .repeating,
                                isActive: self.viewModel.isLoading)
                        Text("Sync Brew")
                            .bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .padding(.horizontal)
                .accessibilityHint("Refreshes the list of installed packages and available updates")

                Divider()

                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text("Dev User")
                            .font(.headline)
                        Text("Pro License")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }

    private func badgeFor(_ item: NavigationItem) -> Int {
        switch item {
        case .installed:
            self.viewModel.installedPackages.count
        case .updates:
            self.viewModel.outdatedPackages.count
        default:
            0
        }
    }
}
