// Sources/Kit/Fixture/SelectionEntry.swift
import Foundation

/// Accumulates numeric-keypad taps into a grandMA3 selection command string
/// (e.g. "Fixture 101 Thru 105", "Group 2 + Fixture 7"). Purely a string
/// assembler — the result is sent verbatim over the cmd transport.
public struct SelectionEntry: Equatable {
    public enum Keyword: String {
        case fixture = "Fixture"
        case group = "Group"
        case thru = "Thru"
        case plus = "+"
    }

    /// Each part is either a multi-digit number run or a keyword token.
    private var parts: [String] = []
    /// True when the last part is an open number run that digits should extend.
    private var inNumber: Bool { parts.last.flatMap { Int($0) } != nil }

    public init() {}

    public mutating func tapDigit(_ d: Int) {
        let digit = String(max(0, min(9, d)))
        if inNumber, let last = parts.last {
            parts[parts.count - 1] = last + digit
        } else {
            parts.append(digit)
        }
    }

    public mutating func tapKeyword(_ k: Keyword) {
        parts.append(k.rawValue)
    }

    /// Remove one trailing digit; if the trailing number run empties or the
    /// trailing part is a keyword, drop the whole part.
    public mutating func backspace() {
        guard var last = parts.last else { return }
        if inNumber, last.count > 1 {
            last.removeLast()
            parts[parts.count - 1] = last
        } else {
            parts.removeLast()
        }
    }

    public mutating func reset() {
        parts.removeAll()
    }

    public var command: String { parts.joined(separator: " ") }
    public var isEmpty: Bool { parts.isEmpty }
}
