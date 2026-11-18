import Foundation

/// What the engine is doing, for the window to show.
public enum EngineState: Sendable, Equatable {
    /// Starting; `attempt` > 0 after a crash.
    case starting(attempt: Int)
    case ready(EngineAddress)
    /// Gave up after the restarts ran out; `log` = the end of its log, `reason` = what went wrong last.
    case failed(reason: String, log: String)
    case stopped
}

/// Keeps the engine running for as long as the app runs: starts it, restarts it with a back-off when it stops on its
/// own (`RestartPolicy`), gives up after the last try and reports every change. The Mac twin of the Windows shell's
/// `backend.rs` `supervise()`.
public actor EngineSupervisor {
    public typealias Launcher = @Sendable () async throws -> (EngineRun, EngineAddress)

    private let launcher: Launcher
    private let logTail: @Sendable () -> String
    private let onChange: @Sendable (EngineState) -> Void
    private var policy: RestartPolicy
    private var run: EngineRun?
    private var loop: Task<Void, Never>?
    private var stopping = false
    public private(set) var state: EngineState = .stopped

    public init(
        launcher: @escaping Launcher, policy: RestartPolicy = .standard,
        logTail: @escaping @Sendable () -> String = { "" },
        onChange: @escaping @Sendable (EngineState) -> Void
    ) {
        self.launcher = launcher
        self.policy = policy
        self.logTail = logTail
        self.onChange = onChange
    }

    /// The engine program in `folders`, started the way the Windows shell starts it.
    public init(
        executable: URL, folders: EngineFolders, policy: RestartPolicy = .standard,
        onChange: @escaping @Sendable (EngineState) -> Void
    ) {
        self.init(
            launcher: {
                try await EngineRun.start(
                    executable: executable, arguments: folders.arguments, log: folders.log,
                    previousLog: folders.previousLog)
            },
            policy: policy, logTail: { EngineSupervisor.tail(of: folders.log) }, onChange: onChange)
    }

    /// Start (or, after `failed`, try again with a fresh budget).
    public func start() {
        guard loop == nil else { return }
        stopping = false
        policy.reset()
        loop = Task { await supervise() }
    }

    /// Stop the engine for good (the app quits).
    public func stop() async {
        stopping = true
        run?.stop()
        loop?.cancel()  // ends a back-off wait at once
        await loop?.value
        loop = nil
        set(.stopped)
    }

    private func supervise() async {
        var lastError = ""
        while !stopping {
            set(.starting(attempt: policy.attempt))
            let began = ContinuousClock.now
            do {
                let (run, address) = try await launcher()
                self.run = run
                if stopping { run.stop() }
                set(.ready(address))
                let code = await run.waitForExit()
                lastError = "exit \(code)"
            } catch {
                lastError = String(describing: error)
            }
            run = nil
            if stopping { break }
            guard let delay = policy.afterExit(ranFor: ContinuousClock.now - began) else {
                set(.failed(reason: lastError, log: logTail()))
                loop = nil
                return
            }
            try? await Task.sleep(for: delay)
        }
    }

    private func set(_ new: EngineState) {
        guard new != state else { return }
        state = new
        onChange(new)
    }

    /// The last lines of a log file, for the "Conclave couldn't start" screen.
    public static func tail(of file: URL, lines: Int = 40) -> String {
        guard let data = try? Data(contentsOf: file) else { return "" }
        let all = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        return all.suffix(lines).joined(separator: "\n")
    }
}
