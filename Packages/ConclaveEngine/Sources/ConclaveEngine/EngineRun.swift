import Foundation

/// Why the engine could not be started.
public enum EngineStartError: Error, Equatable, Sendable {
    /// No engine program at that place (the app was built without `scripts/build_engine.sh`).
    case missing(String)
    /// It stopped before saying where it listens, with this exit code.
    case exited(Int32)
    /// It said nothing within the time limit.
    case timedOut
    /// The system refused to start it (permissions, a damaged file).
    case launch(String)
}

/// One run of the engine program: started, its output going to the log, waiting for its address.
/// The Windows shell does the same in `backend.rs` `run_once()`.
public final class EngineRun: @unchecked Sendable {
    // Process is not Sendable; every access to it goes through `lock`.
    private let lock = NSLock()
    private let process = Process()
    private var exitWaiters: [CheckedContinuation<Int32, Never>] = []
    private var exitCode: Int32?
    public let started = ContinuousClock.now

    /// Start `executable` with `arguments` and wait until it prints its address.
    /// Everything it prints also goes to `log` (the previous run's log moves to `previousLog`).
    public static func start(
        executable: URL, arguments: [String], log: URL, previousLog: URL? = nil,
        environment: [String: String]? = nil, timeout: Duration = .seconds(60)
    ) async throws -> (EngineRun, EngineAddress) {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw EngineStartError.missing(executable.path)
        }
        let run = EngineRun()
        let logHandle = try openLog(log, previous: previousLog)
        let address = try await run.launch(
            executable: executable, arguments: arguments, environment: environment, log: logHandle, timeout: timeout)
        return (run, address)
    }

    private static func openLog(_ log: URL, previous: URL?) throws -> FileHandle {
        let files = FileManager.default
        try files.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let previous, files.fileExists(atPath: log.path) {
            try? files.removeItem(at: previous)
            try? files.moveItem(at: log, to: previous)
        }
        _ = files.createFile(atPath: log.path, contents: nil)
        return try FileHandle(forWritingTo: log)
    }

    private func launch(
        executable: URL, arguments: [String], environment: [String: String]?, log: FileHandle, timeout: Duration
    ) async throws -> EngineAddress {
        let output = Pipe()
        let lines = LineReader()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardOutput = output
        process.standardError = log  // tracebacks land in the log only
        process.standardInput = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { (found: CheckedContinuation<EngineAddress, Error>) in
            let answer = Once(found)
            // An engine that dies early may still have its last lines in the pipe: only when both the output has
            // ended and the process is gone does "it stopped before it was ready" count (`Ending`).
            let ending = Ending { code in answer.resume(throwing: EngineStartError.exited(code)) }
            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {  // end of output
                    handle.readabilityHandler = nil
                    ending.outputEnded()
                    return
                }
                log.write(data)
                for line in lines.feed(data) {
                    if let address = EngineAddress.parse(line: line) { answer.resume(returning: address) }
                }
            }
            process.terminationHandler = { [weak self] process in
                let code = process.terminationStatus
                ending.exited(code)
                self?.finished(code)
            }
            do {
                try lock.withLock { try process.run() }
            } catch {
                answer.resume(throwing: EngineStartError.launch(error.localizedDescription))
                return
            }
            Task {
                try? await Task.sleep(for: timeout)
                if answer.resume(throwing: EngineStartError.timedOut) { self.stop() }
            }
        }
    }

    private func finished(_ code: Int32) {
        let waiters = lock.withLock {
            exitCode = code
            defer { exitWaiters = [] }
            return exitWaiters
        }
        for waiter in waiters { waiter.resume(returning: code) }
    }

    /// Waits until the engine has stopped, and returns its exit code.
    public func waitForExit() async -> Int32 {
        await withCheckedContinuation { waiter in
            let code: Int32? = lock.withLock {
                if exitCode == nil { exitWaiters.append(waiter) }
                return exitCode
            }
            if let code { waiter.resume(returning: code) }
        }
    }

    /// Ask the engine to stop (SIGTERM) and, if it is still there after `grace`, end it (SIGKILL): a hung engine
    /// must not keep the app from quitting. The PyInstaller folder build runs Python in this same process,
    /// so there are no child processes to hunt down like on Windows.
    public func stop(grace: Duration = .seconds(3)) {
        let pid: Int32? = lock.withLock {
            guard process.isRunning else { return nil }
            process.terminate()
            return process.processIdentifier
        }
        guard let pid else { return }
        Task {
            try? await Task.sleep(for: grace)
            if self.isRunning { kill(pid, SIGKILL) }
        }
    }

    public var isRunning: Bool { lock.withLock { process.isRunning } }
}

/// Splits bytes into lines; keeps a half line for the next chunk.
final class LineReader: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()

    func feed(_ data: Data) -> [String] {
        lock.withLock {
            pending.append(data)
            var lines: [String] = []
            while let end = pending.firstIndex(of: UInt8(ascii: "\n")) {
                lines.append(String(decoding: pending[pending.startIndex..<end], as: UTF8.self))
                pending.removeSubrange(pending.startIndex...end)
            }
            return lines
        }
    }
}

/// Calls `done` once both the output has ended and the process has exited.
final class Ending: @unchecked Sendable {
    private let lock = NSLock()
    private var ended = false
    private var code: Int32?
    private let done: @Sendable (Int32) -> Void

    init(_ done: @escaping @Sendable (Int32) -> Void) { self.done = done }

    func outputEnded() { check { ended = true } }
    func exited(_ status: Int32) { check { code = status } }

    private func check(_ change: () -> Void) {
        let finished: Int32? = lock.withLock {
            change()
            return ended ? code : nil
        }
        if let finished { done(finished) }
    }
}

/// A continuation that is resumed at most once, whoever comes first (the address, the exit or the time limit).
final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }

    @discardableResult func resume(returning value: T) -> Bool { take()?.resume(returning: value) != nil }
    @discardableResult func resume(throwing error: Error) -> Bool { take()?.resume(throwing: error) != nil }

    private func take() -> CheckedContinuation<T, Error>? {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }
    }
}
