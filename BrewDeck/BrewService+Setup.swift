//
//  BrewService+Setup.swift
//  BrewDeck
//
//  Created by Viktor Sokolov on 24/12/2025.
//

import Foundation

extension BrewService {
  func setupAskPass() {
    let script = """
      #!/bin/bash
      osascript \\
      -e 'display dialog "BrewDeck needs administrator privileges to complete this action. \\
      Please enter your password:" default answer "" with title "Privileged Action" \\
      with hidden answer' \\
      -e 'text returned of result'
      """

    do {
      try script.write(toFile: askPassPath, atomically: true, encoding: .utf8)
      let attributes = [FileAttributeKey.posixPermissions: 0o755]
      try FileManager.default.setAttributes(attributes, ofItemAtPath: askPassPath)
    } catch {
      print("❌ Failed to setup askpass: \(error)")
    }
  }

  func setupProcess(_ process: Process, arguments: [String], outputPipe: Pipe, errorPipe: Pipe) {
    process.executableURL = URL(fileURLWithPath: self.brewPath)
    process.arguments = arguments
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    var env = ProcessInfo.processInfo.environment
    env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
    env["HOMEBREW_NO_ANALYTICS"] = "1"
    env["HOMEBREW_COLOR"] = "0"
    env["SUDO_ASKPASS"] = self.askPassPath
    env["DISPLAY"] = ":0"
    process.environment = env
  }

  func setupReadabilityHandlers(
    _ outputPipe: Pipe,
    _ errorPipe: Pipe,
    _ outputData: NSMutableData,
    _ errorData: NSMutableData
  ) {
    outputPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if !data.isEmpty { outputData.append(data) }
    }

    errorPipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if !data.isEmpty { errorData.append(data) }
    }
  }

  func setupTimeout(
    for process: Process,
    timeoutSeconds: Double,
    continuation: CheckedContinuation<String, Error>
  ) {
    DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds) {
      if process.isRunning {
        process.terminate()
        continuation.resume(throwing: BrewError.timeout)
      }
    }
  }

  func setupDataAndHandlers(
    for process: Process,
    outputPipe: Pipe,
    errorPipe: Pipe,
    continuation: CheckedContinuation<String, Error>
  ) {
    let outputData = NSMutableData()
    let errorData = NSMutableData()

    setupReadabilityHandlers(outputPipe, errorPipe, outputData, errorData)
    setupTerminationHandler(
      for: process, outputData: outputData, errorData: errorData, continuation: continuation)
  }

  func finishProcess(
    process: Process,
    continuation: CheckedContinuation<String, Error>,
    error: Error? = nil,
    result: String? = nil
  ) {
    // Stop readability handlers
    (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
    (process.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil

    if let error = error {
      continuation.resume(throwing: error)
    } else if let result = result {
      continuation.resume(returning: result)
    }
  }

  func handleProcessTermination(
    process: Process,
    outputData: NSMutableData,
    errorData: NSMutableData,
    continuation: CheckedContinuation<String, Error>
  ) {
    if process.terminationStatus != 0 {
      let errorMessage =
        String(data: errorData as Data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      self.finishProcess(
        process: process,
        continuation: continuation,
        error: BrewError.commandFailed(
          errorMessage.isEmpty ? "Exit code \(process.terminationStatus)" : errorMessage
        )
      )
    } else {
      if let output = String(data: outputData as Data, encoding: .utf8) {
        self.finishProcess(process: process, continuation: continuation, result: output)
      } else {
        self.finishProcess(
          process: process, continuation: continuation, error: BrewError.parsingError)
      }
    }
  }

  func setupTerminationHandler(
    for process: Process,
    outputData: NSMutableData,
    errorData: NSMutableData,
    continuation: CheckedContinuation<String, Error>
  ) {
    var isFinished = false
    let lock = NSLock()

    process.terminationHandler = { [weak self] process in
      guard let self = self else { return }
      lock.lock()
      defer { lock.unlock() }
      guard !isFinished else { return }
      isFinished = true

      self.handleProcessTermination(
        process: process,
        outputData: outputData,
        errorData: errorData,
        continuation: continuation
      )
    }
  }

  func executeProcess(
    arguments: [String],
    timeoutSeconds: Double,
    continuation: CheckedContinuation<String, Error>
  ) {
    let process = Process()
    let pipe = Pipe()
    let errorPipe = Pipe()

    setupProcess(process, arguments: arguments, outputPipe: pipe, errorPipe: errorPipe)

    setupDataAndHandlers(
      for: process,
      outputPipe: pipe,
      errorPipe: errorPipe,
      continuation: continuation
    )

    setupTimeout(for: process, timeoutSeconds: timeoutSeconds, continuation: continuation)

    do {
      print("🛠 BrewDeck: Executing \(arguments.joined(separator: " "))")
      try process.run()
    } catch {
      if (error as NSError).code == 1 || (error as NSError).code == 5 {
        continuation.resume(throwing: BrewError.permissionDenied)
      } else {
        continuation.resume(
          throwing: BrewError.commandFailed("Launch failed: \(error.localizedDescription)"))
      }
    }
  }
}
