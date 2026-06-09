// Sources/Kit/Fixture/NudgeAccumulator.swift
/// Coalesces a stream of relative nudge deltas (from a finger drag) into
/// throttled emissions so a drag never floods the desk. Leading-edge emit, then
/// sum within `intervalMs`, then emit on the next accept past the window or on
/// `flush` (drag end). `offset` always tracks the true running sum for display.
public final class NudgeAccumulator {
    private let intervalMs: Int
    private var pending = 0
    private var lastEmitMs: Int?            // nil → first accept emits immediately
    public private(set) var offset = 0

    public init(intervalMs: Int = 50) {
        self.intervalMs = intervalMs
    }

    /// Feed a delta sampled at monotonic `now` (ms). Returns the delta to send,
    /// or nil if it was coalesced into the pending window.
    public func accept(delta: Int, atMs now: Int) -> Int? {
        offset += delta
        pending += delta
        if let last = lastEmitMs, now - last < intervalMs {
            return nil
        }
        return emit(now)
    }

    /// Emit any pending delta now (call on drag end). Returns it, or nil.
    /// Resets the throttle clock so the next drag's first accept emits immediately.
    public func flush(atMs now: Int) -> Int? {
        defer { lastEmitMs = nil }
        guard pending != 0 else { return nil }
        let out = pending
        pending = 0
        return out
    }

    private func emit(_ now: Int) -> Int? {
        guard pending != 0 else { return nil }
        let out = pending
        pending = 0
        lastEmitMs = now
        return out
    }
}
