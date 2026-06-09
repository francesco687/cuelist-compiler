// Tests/KitTests/NudgeAccumulatorTests.swift
import XCTest
@testable import SaettaKit

final class NudgeAccumulatorTests: XCTestCase {

    func test_first_accept_emits_immediately() {
        let acc = NudgeAccumulator(intervalMs: 50)
        XCTAssertEqual(acc.accept(delta: 3, atMs: 0), 3)
        XCTAssertEqual(acc.offset, 3)
    }

    func test_within_window_coalesces_and_returns_nil() {
        let acc = NudgeAccumulator(intervalMs: 50)
        _ = acc.accept(delta: 3, atMs: 0)          // emits 3
        XCTAssertNil(acc.accept(delta: 2, atMs: 10)) // coalesced
        XCTAssertNil(acc.accept(delta: 1, atMs: 20)) // coalesced
        XCTAssertEqual(acc.offset, 6, "offset tracks the true running sum")
    }

    func test_emits_accumulated_after_window_elapses() {
        let acc = NudgeAccumulator(intervalMs: 50)
        _ = acc.accept(delta: 3, atMs: 0)          // emits 3
        XCTAssertNil(acc.accept(delta: 2, atMs: 10))
        XCTAssertEqual(acc.accept(delta: 1, atMs: 60), 3, "pending 2 + new 1 emitted")
        XCTAssertEqual(acc.offset, 6)
    }

    func test_flush_emits_pending() {
        let acc = NudgeAccumulator(intervalMs: 50)
        _ = acc.accept(delta: 3, atMs: 0)
        XCTAssertNil(acc.accept(delta: 4, atMs: 10))
        XCTAssertEqual(acc.flush(atMs: 20), 4)
        XCTAssertNil(acc.flush(atMs: 30), "nothing pending after flush")
        XCTAssertEqual(acc.offset, 7)
    }
}
