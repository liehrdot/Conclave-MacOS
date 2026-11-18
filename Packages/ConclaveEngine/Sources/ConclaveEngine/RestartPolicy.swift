/// When to start the engine again after it stopped on its own, like the Windows shell (`backend.rs`
/// `BACKOFF` and `HEALTHY_AFTER`): wait 1, 2, 5, 5, 5 seconds, then give up. A run that lasted
/// `healthyAfter` or longer resets the count, so a crash once a day never uses up the budget.
public struct RestartPolicy: Sendable, Equatable {
    public var delays: [Duration]
    public var healthyAfter: Duration
    /// Restarts used since the last healthy run.
    public private(set) var attempt = 0

    public static let standard = RestartPolicy(
        delays: [.seconds(1), .seconds(2), .seconds(5), .seconds(5), .seconds(5)], healthyAfter: .seconds(300))

    public init(delays: [Duration], healthyAfter: Duration) {
        self.delays = delays
        self.healthyAfter = healthyAfter
    }

    /// The engine stopped after running `ranFor`: how long to wait before the next start, or nil to give up.
    public mutating func afterExit(ranFor: Duration) -> Duration? {
        if ranFor >= healthyAfter { attempt = 0 }
        guard attempt < delays.count else { return nil }
        defer { attempt += 1 }
        return delays[attempt]
    }

    /// Someone pressed "Try Again": a fresh budget.
    public mutating func reset() { attempt = 0 }
}
