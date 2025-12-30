import Observation
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = BrewViewModel()
    @State private var selection: NavigationItem? = .installed
    @State private var selectedPackage: Package?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: self.$selection, viewModel: self.viewModel)
                .navigationSplitViewColumnWidth(min: 200, ideal: 250)
        } content: {
            if let selection {
                if selection == .settings {
                    SettingsView(viewModel: self.viewModel)
                } else {
                    PackageListView(
                        mode: selection,
                        viewModel: self.viewModel,
                        selectedPackage: self.$selectedPackage)
                }
            } else {
                Text("Select a category")
                    .foregroundStyle(.secondary)
            }
        } detail: {
            if self.selection != .settings {
                PackageDetailView(package: self.selectedPackage, viewModel: self.viewModel)
            } else {
                Text("Settings Detail")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            self.selection = .installed
        }
        .onChange(of: self.selectedPackage) { _, _ in
            if !self.viewModel.isRunningOperation {
                self.viewModel.showLogs = false
                self.viewModel.operationOutput = ""
            }
        }
    }
}

#Preview {
    ContentView()
}
