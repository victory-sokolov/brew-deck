//
//  BrewService+Setup.swift
//  BrewDeck
//
//  Created by Viktor Sokolov on 24/12/2025.
//

import Foundation

extension BrewService {
    // Thread-safe wrapper for data collection in concurrent contexts
    nonisolated class DataWrapper: @unchecked Sendable {
        private let data: NSMutableData
        private let lock = NSLock()

        init() {
            // swiftlint:disable:next avoid_nsmutabledata
            self.data = NSMutableData()
        }

        nonisolated func append(_ newData: Data) {
            self.lock.lock()
            self.data.append(newData)
            self.lock.unlock()
        }

        nonisolated func getData() -> Data {
            self.lock.lock()
            defer { lock.unlock() }
            return self.data as Data
        }
    }

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
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        var env = ProcessInfo.processInfo.environment
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ANALYTICS"] = "1"
        env["HOMEBREW_COLOR"] = "0"
        env["SUDO_ASKPASS"] = askPassPath
        env["DISPLAY"] = ":0"
        process.environment = env
    }

    func setupReadabilityHandlers(
        _ outputPipe: Pipe,
        _ errorPipe: Pipe,
        _ outputWrapper: DataWrapper,
        _ errorWrapper: DataWrapper)
    {
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { outputWrapper.append(data) }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { errorWrapper.append(data) }
        }
    }

    func setupTimeout(
        for process: Process,
        timeoutSeconds: Double,
        continuation: CheckedContinuation<String, Error>)
    {
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
        continuation: CheckedContinuation<String, Error>)
    {
        let outputWrapper = DataWrapper()
        let errorWrapper = DataWrapper()

        self.setupReadabilityHandlers(outputPipe, errorPipe, outputWrapper, errorWrapper)
        self.setupTerminationHandler(
            for: process, outputWrapper: outputWrapper, errorWrapper: errorWrapper, continuation: continuation)
    }

    nonisolated func finishProcess(
        process: Process,
        continuation: CheckedContinuation<String, Error>,
        error: Error? = nil,
        result: String? = nil)
    {
        // Stop readability handlers
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (process.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil

        if let error {
            continuation.resume(throwing: error)
        } else if let result {
            continuation.resume(returning: result)
        }
    }

    nonisolated func handleProcessTermination(
        process: Process,
        outputWrapper: DataWrapper,
        errorWrapper: DataWrapper,
        continuation: CheckedContinuation<String, Error>)
    {
        if process.terminationStatus != 0 {
            let errorMessage =
                String(data: errorWrapper.getData(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.finishProcess(
                process: process,
                continuation: continuation,
                error: BrewError.commandFailed(
                    errorMessage.isEmpty ? "Exit code \(process.terminationStatus)" : errorMessage))
        } else {
            if let output = String(data: outputWrapper.getData(), encoding: .utf8) {
                self.finishProcess(process: process, continuation: continuation, result: output)
            } else {
                self.finishProcess(
                    process: process, continuation: continuation, error: BrewError.parsingError)
            }
        }
    }

    func setupTerminationHandler(
        for process: Process,
        outputWrapper: DataWrapper,
        errorWrapper: DataWrapper,
        continuation: CheckedContinuation<String, Error>)
    {
        // Thread-safe wrapper for the isFinished flag
        final class FinishedFlag: @unchecked Sendable {
            private let lock = NSLock()
            private nonisolated(unsafe) var value = false

            nonisolated func checkAndSet() -> Bool {
                self.lock.lock()
                defer { lock.unlock() }
                if self.value {
                    return true // Already finished
                }
                self.value = true
                return false // Not finished yet, now set to true
            }
        }

        let finishedFlag = FinishedFlag()

        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            guard !finishedFlag.checkAndSet() else { return }

            self.handleProcessTermination(
                process: process,
                outputWrapper: outputWrapper,
                errorWrapper: errorWrapper,
                continuation: continuation)
        }
    }

    func executeProcess(
        arguments: [String],
        timeoutSeconds: Double,
        continuation: CheckedContinuation<String, Error>)
    {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        self.setupProcess(process, arguments: arguments, outputPipe: pipe, errorPipe: errorPipe)

        self.setupDataAndHandlers(
            for: process,
            outputPipe: pipe,
            errorPipe: errorPipe,
            continuation: continuation)

        self.setupTimeout(for: process, timeoutSeconds: timeoutSeconds, continuation: continuation)

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
