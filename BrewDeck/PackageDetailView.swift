import SwiftUI

struct PackageDetailView: View {
  let package: Package?
  @ObservedObject var viewModel: BrewViewModel

  var currentPackage: Package? {
    guard let package = package else { return nil }
    // Try to find a matching package by name or ID
    return viewModel.installedPackages.first(where: {
      $0.name == package.name || $0.name.lowercased() == package.name.lowercased()
        || ($0.name.components(separatedBy: "/").last
          == package.name.components(separatedBy: "/").last)
    }) ?? package
  }

  var body: some View {
    if let package = currentPackage {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          header(package)

          if let versionInfo = viewModel.outdatedPackages.first(where: { $0.name == package.name })
          {
            updateCard(package, versionInfo)
          }

          actions(package)

          details(package)

          if viewModel.showLogs {
            operationLog
          }

          Spacer()
        }
        .padding(32)
      }
    } else {
      VStack {
        Image(systemName: "shippingbox")
          .font(.system(size: 64))
          .foregroundStyle(.secondary.opacity(0.3))
        Text("Select a package to see details")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func header(_ package: Package) -> some View {
    HStack(alignment: .top, spacing: 20) {
      PackageIcon(type: package.type)
        .frame(width: 80, height: 80)

      VStack(alignment: .leading, spacing: 4) {
        Text(package.name)
          .font(.system(size: 32, weight: .bold))

        Text(package.description ?? "No description available")
          .font(.title3)
          .foregroundStyle(.secondary)

        HStack {
          CapsuleText(
            text: package.type.rawValue.capitalized,
            color: package.type == .formula ? .purple : .blue
          )
          if let fullName = package.fullName {
            Text(fullName)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          if let size = package.formattedSize {
            Text("•")
              .foregroundStyle(.secondary)
            Text(size)
              .font(.caption)
              .foregroundStyle(.blue)
              .bold()
          }
        }
        .padding(.top, 4)
      }

      Spacer()
    }
    .padding(24)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    )
  }

  private func updateCard(_ package: Package, _ info: OutdatedPackageInfo) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Image(systemName: "info.circle.fill")
          .foregroundStyle(.blue)
        Text("Update Available")
          .font(.headline)
      }

      Text(
        "Version \(info.latestVersion) is available. You are currently on \(info.installedVersion)."
      )
      .font(.subheadline)

      Button {
        Task { await viewModel.upgrade(package: package.name) }
      } label: {
        Text("Upgrade to v\(info.latestVersion)")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .disabled(viewModel.isRunningOperation)
    }
    .padding()
    .background(Color.blue.opacity(0.1))
    .cornerRadius(12)
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
    )
  }

  private func actions(_ package: Package) -> some View {
    HStack(spacing: 16) {
      if !package.isInstalled {
        Button {
          Task { await viewModel.install(package: package.name) }
        } label: {
          Label("Install", systemImage: "plus")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      } else {
        Button {
          if let url = package.homepage, let nsURL = URL(string: url) {
            NSWorkspace.shared.open(nsURL)
          }
        } label: {
          Label("Homepage", systemImage: "safari")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)

        Button(role: .destructive) {
          Task { await viewModel.uninstall(package: package) }
        } label: {
          Label("Uninstall", systemImage: "trash")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
      }
    }
  }

  private func details(_ package: Package) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("DETAILS")
        .font(.caption)
        .bold()
        .foregroundStyle(.secondary)

      Divider()

      if let size = package.formattedSize {
        DetailRow(label: "Size on Disk", value: size)
      } else if package.isInstalled {
        // If it's installed but size is 0 or nil, it might still be calculating
        DetailRow(label: "Size on Disk", value: "Calculating...")
          .foregroundStyle(.secondary)
      }

      DetailRow(label: "Installed", value: package.installedVersion ?? "Not installed")
      DetailRow(label: "Latest", value: package.latestVersion)

      if let deps = package.dependencies, !deps.isEmpty {
        DetailRow(label: "Dependencies", value: deps.joined(separator: ", "))
      }

      if let homepage = package.homepage {
        DetailRow(label: "Homepage", value: homepage)
      }
    }
  }

  private var operationLog: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("LOGS")
          .font(.caption)
          .bold()
          .foregroundStyle(.secondary)
        Spacer()

        if viewModel.isRunningOperation {
          ProgressView()
            .scaleEffect(0.5)
        } else {
          HStack(spacing: 12) {
            Button {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(viewModel.operationOutput, forType: .string)
            } label: {
              Image(systemName: "doc.on.doc")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy Logs")

            Button {
              viewModel.showLogs = false
              viewModel.operationOutput = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
          }
        }
      }

      ScrollView {
        Text(viewModel.operationOutput)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(8)
          .background(Color.black.opacity(0.1))
          .cornerRadius(8)
      }
      .frame(height: 150)
    }
    .padding(.top)
  }
}

struct DetailRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack {
      Text(label)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .multilineTextAlignment(.trailing)
    }
    .font(.subheadline)
  }
}

struct CapsuleText: View {
  let text: String
  let color: Color

  var body: some View {
    Text(text)
      .font(.system(size: 10, weight: .bold))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(color.opacity(0.2))
      .foregroundStyle(color)
      .cornerRadius(4)
  }
}
