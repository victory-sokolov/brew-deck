import Foundation

enum BrewError: LocalizedError {
  case brewNotFound
  case commandFailed(String)
  case parsingError
  case timeout
  case permissionDenied

  var errorDescription: String? {
    switch self {
    case .brewNotFound: return "Homebrew not found. Please ensure it is installed."
    case .commandFailed(let detail): return detail
    case .parsingError: return "Failed to parse Homebrew output."
    case .timeout: return "The Homebrew command timed out."
    case .permissionDenied:
      return "Permission Denied (OS 0x5). "
        + "Please disable App Sandbox in Xcode and Clean the project (Cmd+Option+Shift+K)."
    }
  }
}

class BrewService {
  static let shared = BrewService()
  static let version = "2.1.0"  // Version marker for debugging

  let brewPath: String
  let askPassPath: String = "/tmp/brewdeck-askpass.sh"

  init() {
    let paths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew", "/usr/bin/brew"]
    brewPath =
      paths.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? "/opt/homebrew/bin/brew"
    setupAskPass()
    print("🚀 BrewService Initialized (v\(BrewService.version)). Brew path: \(brewPath)")
  }

  func run(arguments: [String], timeoutSeconds: Double = 60.0) async throws -> String {
    guard !arguments.isEmpty else { return "" }

    return try await withCheckedThrowingContinuation { continuation in
      self.executeProcess(
        arguments: arguments, timeoutSeconds: timeoutSeconds, continuation: continuation)
    }
  }
}
