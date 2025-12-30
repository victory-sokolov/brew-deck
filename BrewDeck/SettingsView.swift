import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: BrewViewModel

    var body: some View {
        Form {
            Section("Brew Settings") {
                Button("Refresh Installed Packages") {
                    Task { await self.viewModel.refresh() }
                }
                .disabled(self.viewModel.isLoading)
                .accessibilityHint("Reloads the list of installed packages and checks for updates")

                if self.viewModel.isLoading {
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
                        .accessibilityHint("Opens the Homebrew website in your default web browser")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
