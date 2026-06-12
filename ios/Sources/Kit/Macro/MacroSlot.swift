import Foundation

/// Which grandMA3 function an executor macro button performs.
/// `rawValue` doubles as the persisted codec segment.
public enum ExecutorFunction: String, CaseIterable, Sendable {
    case toggle, flash, on

    /// The grandMA3 keyword that engages the function.
    var keyword: String {
        switch self {
        case .toggle: "Toggle"
        case .flash: "Flash"
        case .on: "On"
        }
    }

    /// Caption rendered under the target on the macro cell.
    public var caption: String { rawValue.uppercased() }
}

/// What an executor macro button targets: an executor number on the desk's
/// current page, or an executor by its desk label.
///
/// - Note: The codec (`MacroSlot.init?(rawValue:)`) and `MacroPad.loadExecutor`
///   are the sanctioned producers — direct `.name`/`.number` construction
///   bypasses validation (quote/control-char checks, range enforcement).
public enum ExecutorTarget: Equatable, Sendable {
    case number(Int)      // 1...9999, current page
    case name(String)     // non-empty, trimmed, no quotes or control chars

    /// The form persisted inside the slot string (no quoting).
    var encoded: String {
        switch self {
        case .number(let n): String(n)
        case .name(let s): s
        }
    }

    /// How the target renders in a grandMA3 command: bare number, quoted name.
    var commandForm: String {
        switch self {
        case .number(let n): String(n)
        case .name(let s): "\"\(s)\""
        }
    }

    /// What the macro cell displays.
    public var display: String {
        switch self {
        case .number(let n): String(n)
        case .name(let s): s
        }
    }
}

/// The value held by one Live-tab macro-pad slot: either a curated parameter-free
/// action, or an executor button (toggle / flash / on) targeting a desk executor
/// by number (current page) or by name. Encodes to/from the single `String` per
/// slot that `MacroPad` persists — an `"exec:"` prefix marks executor slots;
/// anything else is an action id. New form is `exec:<function>:<target>`; legacy
/// `exec:` / `exec:<digits>` (PR #32) decodes as a toggle, so saved pads load
/// unchanged.
public enum MacroSlot: RawRepresentable, Equatable, Sendable {
    case action(MacroAction)
    /// `target == nil` — assigned but not yet loaded; renders as pending, never fires.
    case executor(function: ExecutorFunction, target: ExecutorTarget?)

    /// Executor numbers the load sheet and the decoder accept.
    public static let executorRange: ClosedRange<Int> = 1...9999

    private static let execPrefix = "exec:"

    /// Classify and validate a raw target string the way the codec does: if the
    /// raw string is entirely ASCII digits (untrimmed), it is treated as a number
    /// and must fall in `executorRange`; anything else is treated as a name,
    /// trimmed of whitespace, and refused if it contains quotes, control characters,
    /// or is empty after trimming. Returns nil for anything that would decode to
    /// nil — a single source of truth shared by the decoder and
    /// `MacroPad.loadExecutor`, so a persisted target always round-trips.
    /// An empty string returns nil; callers own the unloaded-slot distinction.
    internal static func validatedTarget(fromRaw raw: String) -> ExecutorTarget? {
        guard !raw.isEmpty else { return nil }
        if raw.allSatisfy({ $0.isASCII && $0.isNumber }) {
            // All ASCII-digits (untrimmed) — same branch as the decoder.
            guard let n = Int(raw), executorRange.contains(n) else { return nil }
            return .number(n)
        } else {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            guard !name.contains("\"") else { return nil }
            guard !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
            return .name(name)
        }
    }

    /// Decode a persisted slot string. Unknown action ids, unknown functions,
    /// out-of-range numbers, and whitespace-only names decode to nil (empty
    /// slot) — never a crash or a bad command.
    public init?(rawValue: String) {
        guard rawValue.hasPrefix(Self.execPrefix) else {
            guard let action = MacroAction.find(rawValue) else { return nil }
            self = .action(action)
            return
        }
        let body = rawValue.dropFirst(Self.execPrefix.count)
        let function: ExecutorFunction
        let targetRaw: Substring
        if let colon = body.firstIndex(of: ":") {
            guard let parsed = ExecutorFunction(rawValue: String(body[..<colon])) else { return nil }
            function = parsed
            targetRaw = body[body.index(after: colon)...]
        } else {
            // Legacy form only ever held ASCII digits (or nothing) and meant toggle.
            guard body.isEmpty || body.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            function = .toggle
            targetRaw = body
        }
        if targetRaw.isEmpty {
            self = .executor(function: function, target: nil)
        } else if let target = Self.validatedTarget(fromRaw: String(targetRaw)) {
            self = .executor(function: function, target: target)
        } else {
            return nil
        }
    }

    /// The string `MacroPad` persists for this slot — always the new
    /// three-segment form for executors.
    public var rawValue: String {
        switch self {
        case .action(let action): action.id
        case .executor(let function, let target):
            Self.execPrefix + function.rawValue + ":" + (target?.encoded ?? "")
        }
    }

    /// The command-line string a tap (toggle/on) or touch-down (flash) fires,
    /// or nil if this slot can't fire yet.
    public var command: String? {
        switch self {
        case .action(let action): action.command
        case .executor(let function, let target):
            target.map { "\(function.keyword) Executor \($0.commandForm)" }
        }
    }

    /// The command touch-up fires — only flash needs a release.
    public var releaseCommand: String? {
        guard case .executor(function: .flash, target: let target?) = self else { return nil }
        return "FlashOff Executor \(target.commandForm)"
    }
}
