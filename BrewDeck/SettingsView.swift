import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: BrewViewModel

    var body: some View {
        Form {
            Section("Brew Settings") {
                Button("Refresh Installed Packages") {
                    Task { await viewModel.refresh() }
                }
                .disabled(viewModel.isLoading)

                if viewModel.isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("Refreshing...")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("App Name", value: "BrewDeck")
                if let url = URL(string: "https://github.com/homebrew") {
                    Link("Visit Website", destination: url)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
