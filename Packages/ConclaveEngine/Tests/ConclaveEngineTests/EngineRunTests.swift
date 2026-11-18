import Foundation
import Testing
@testable import ConclaveEngine

/// A stand-in engine: a shell script that prints what the real one prints, then does what the test asks.
func fakeEngine(_ body: String) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: "conclave-engine-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let script = folder.appending(path: "conclave-backend")
    try "#!/bin/sh\n\(body)\n".write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    return script
}

func tempLog() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "conclave-log-\(UUID().uuidString)/logs/backend.log")
}

@Suite(.serialized) struct EngineRunTests {
    @Test func startsReadsTheAddressAndStops() async throws {
        let exe = try fakeEngine("""
            echo "Conclave GUI: starting"
            echo "MTGDECK_URL=http://127.0.0.1:4711/?token=t0k"
            echo "to stderr" >&2
            exec sleep 30
            """)
        let log = tempLog()
        let (run, address) = try await EngineRun.start(executable: exe, arguments: [], log: log)
        #expect(address.base.absoluteString == "http://127.0.0.1:4711/")
        #expect(address.token == "t0k")
        #expect(run.isRunning)
        run.stop(grace: .milliseconds(200))
        _ = await run.waitForExit()
        #expect(!run.isRunning)
        let text = try String(contentsOf: log, encoding: .utf8)
        #expect(text.contains("MTGDECK_URL="))
        #expect(text.contains("to stderr"))
    }

    @Test func reportsAnEngineThatDiesBeforeItIsReady() async throws {
        let exe = try fakeEngine("echo boom >&2; exit 3")
        await #expect(throws: EngineStartError.exited(3)) {
            _ = try await EngineRun.start(executable: exe, arguments: [], log: tempLog())
        }
    }

    @Test func reportsAMissingProgram() async {
        await #expect(throws: EngineStartError.missing("/nowhere/conclave-backend")) {
            _ = try await EngineRun.start(
                executable: URL(filePath: "/nowhere/conclave-backend"), arguments: [], log: tempLog())
        }
    }

    @Test func givesUpWhenTheEngineStaysSilent() async throws {
        let exe = try fakeEngine("exec sleep 30")
        await #expect(throws: EngineStartError.timedOut) {
            _ = try await EngineRun.start(executable: exe, arguments: [], log: tempLog(), timeout: .milliseconds(300))
        }
    }

    @Test func keepsThePreviousLog() async throws {
        let exe = try fakeEngine("echo MTGDECK_URL=http://127.0.0.1:1/?token=a; exit 0")
        let log = tempLog()
        let previous = log.deletingLastPathComponent().appending(path: "backend.1.log")
        for _ in 0..<2 {
            let (run, _) = try await EngineRun.start(executable: exe, arguments: [], log: log, previousLog: previous)
            _ = await run.waitForExit()
        }
        #expect(FileManager.default.fileExists(atPath: previous.path))
    }
}

/// Collects the states a supervisor reports.
final class States: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [EngineState] = []
    func add(_ state: EngineState) { lock.withLock { seen.append(state) } }
    var all: [EngineState] { lock.withLock { seen } }
}

@Suite(.serialized) struct EngineSupervisorTests {
    let quick = RestartPolicy(delays: [.milliseconds(10), .milliseconds(10)], healthyAfter: .seconds(300))

    @Test func restartsACrashedEngineThenGivesUp() async throws {
        let exe = try fakeEngine("echo MTGDECK_URL=http://127.0.0.1:1/?token=a; exit 1")
        let log = tempLog()
        let states = States()
        let supervisor = EngineSupervisor(
            launcher: { try await EngineRun.start(executable: exe, arguments: [], log: log) },
            policy: quick, logTail: { "last lines" }, onChange: states.add)
        await supervisor.start()
        for _ in 0..<200 where !(states.all.last.map(isFailed) ?? false) { try await Task.sleep(for: .milliseconds(20)) }

        let ready = states.all.filter { if case .ready = $0 { true } else { false } }
        #expect(ready.count == 3)  // the first start and two restarts
        #expect(states.all.contains(.starting(attempt: 2)))
        #expect(states.all.last == .failed(reason: "exit 1", log: "last lines"))
    }

    @Test func stopsTheEngineWhenTheAppQuits() async throws {
        let exe = try fakeEngine("echo MTGDECK_URL=http://127.0.0.1:1/?token=a; exec sleep 30")
        let log = tempLog()
        let states = States()
        let supervisor = EngineSupervisor(
            launcher: { try await EngineRun.start(executable: exe, arguments: [], log: log) },
            policy: quick, onChange: states.add)
        await supervisor.start()
        for _ in 0..<200 where !states.all.contains(where: isReady) { try await Task.sleep(for: .milliseconds(20)) }
        await supervisor.stop()
        #expect(states.all.last == .stopped)
        #expect(states.all.filter(isReady).count == 1)  // no restart after a stop
    }
}

func isReady(_ state: EngineState) -> Bool { if case .ready = state { true } else { false } }
func isFailed(_ state: EngineState) -> Bool { if case .failed = state { true } else { false } }
