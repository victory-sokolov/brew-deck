import Observation
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = BrewViewModel()
    @State private var selection: NavigationItem? = .installed
    @State private var selectedPackage: Package?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } content: {
            if let selection {
                if selection == .settings {
                    SettingsView(viewModel: viewModel)
                } else {
                    PackageListView(
                        mode: selection, viewModel: viewModel, selectedPackage: $selectedPackage)
                }
            } else {
                Text("Select a category")
                    .foregroundStyle(.secondary)
            }
        } detail: {
            if selection != .settings {
                PackageDetailView(package: selectedPackage, viewModel: viewModel)
            } else {
                Text("Settings Detail")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            selection = .installed
        }
        .onChange(of: selectedPackage) { _, _ in
            if !viewModel.isRunningOperation {
                viewModel.showLogs = false
                viewModel.operationOutput = ""
            }
        }
    }
}

#Preview {
    ContentView()
}
