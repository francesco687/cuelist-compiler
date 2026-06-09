import Foundation

/// Turns live fixture-control intents into grandMA3 command-line strings.
/// Mirrors the style of `MA3CommandBuilder`. All output is sent over the
/// optimistic `cmd` transport; relative forms verified in the Phase-0 spike.
public enum FixtureControlBuilder {

    /// "At + 5" / "At - 5" for relative intensity. Returns nil for a zero delta.
    public static func intensityNudge(_ delta: Int) -> String? {
        guard delta != 0 else { return nil }
        return "At \(sign(delta)) \(abs(delta))"
    }

    /// "Attribute \"Pan\" At + 5" for a relative attribute nudge. Nil for zero.
    public static func attributeNudge(_ attribute: String, _ delta: Int) -> String? {
        guard delta != 0 else { return nil }
        return "Attribute \"\(attribute)\" At \(sign(delta)) \(abs(delta))"
    }

    /// "At Preset 4.3" — recall preset `number` from `pool` onto the selection.
    public static func recallPreset(pool: Pool, number: Int) -> String {
        "At Preset \(pool.number).\(number)"
    }

    /// Drop the programmer.
    public static let clear = "ClearAll"

    /// "Store Sequence 5 Cue 2 /Overwrite /NoConfirmation" (mode-dependent flag).
    public static func storeCue(sequence: Int, cue: Int, mode: StoreMode) -> String {
        "Store Sequence \(sequence) Cue \(cue) \(mode.flag) /NoConfirmation"
    }

    /// "Store Preset 4.3 /Overwrite /NoConfirmation" (mode-dependent flag).
    public static func updatePreset(pool: Pool, number: Int, mode: StoreMode) -> String {
        "Store Preset \(pool.number).\(number) \(mode.flag) /NoConfirmation"
    }

    private static func sign(_ n: Int) -> String { n < 0 ? "-" : "+" }
}
