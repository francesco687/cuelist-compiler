import Foundation

/// Turns ticked cues into APPEND-ONLY grandMA3 Timecode commands.
/// Convention: TC pool number == sequence number. 25 fps. `time` is float seconds.
///
/// Append-only is the whole point: we never issue the web overwrite path's
/// `Delete ... × 200` cleanup, so timecodes already on the desk for other cues are
/// untouched. Each ticked cue becomes ONE inline-Lua command that, desk-side:
///   1. reads the current event count of TC pool N's subtrack,
///   2. `Store`s a new `Goto Cue c Sequence N` event (lands at the next index),
///   3. `Set`s that event's `time` property to the SMPTE→seconds value.
/// The two inner `Cmd(...)` strings are proven (see web ma3-command-spec). Only the
/// count accessor (`tcCountLuaExpr`) is desk-verified in the onPC smoke task.
public enum TimecodeBuilder {

    public struct Event: Equatable {
        public let sequence: Int
        public let cueN: Double
        public let seconds: String
    }

    private static func formatN(_ n: Double) -> String {
        n.rounded() == n ? String(Int(n)) : String(n)
    }

    /// Lua expression (evaluated desk-side) yielding the count of existing events
    /// in TC pool `n`'s subtrack, so the new event appends at `count + 1`.
    /// HYPOTHESIS — verified/corrected in the onPC smoke task. Isolated here so the
    /// fix is one constant + one golden test, nothing else.
    static func tcCountLuaExpr(_ poolVar: String) -> String {
        "Root().ShowData.DataPools.Default.Timecodes:Ptr(\(poolVar)).Tracks:Ptr(1).TrackGroups:Ptr(1).Tracks:Ptr(1).Count"
    }

    /// Ticked + valid cues for this song, ascending by cue number.
    public static func events(song: Song, ticked: Set<UUID>) -> [Event] {
        song.cues
            .filter { ticked.contains($0.id) }
            .filter { Smpte.isValid($0.position) }
            .sorted { $0.n < $1.n }
            .compactMap { cue -> Event? in
                guard let secs = Smpte.secondsString(cue.position) else { return nil }
                return Event(sequence: song.sequence, cueN: cue.n, seconds: secs)
            }
    }

    /// One inline-Lua `cmd` line per ticked+valid cue. Append-only.
    public static func lines(song: Song, ticked: Set<UUID>) -> [String] {
        events(song: song, ticked: ticked).map { ev in
            let n = ev.sequence
            let c = formatN(ev.cueN)
            let s = ev.seconds
            // Build the Lua body, then escape the outer `cmd` string's quotes.
            // Inner single quotes wrap MA3 Cmd strings; \" appears in the Goto label.
            let count = tcCountLuaExpr("n")
            let body =
                "local n=\(n) " +
                "local i=(\(count) or 0)+1 " +
                "Cmd('Store Timecode '..n..'.1.1.1.1 \\\"Goto Cue \(c) Sequence '..n..'\\\" /NoConfirmation') " +
                "Cmd('Set Timecode '..n..'.1.1.1.1.'..i..' Property \\'time\\' \(s)')"
            return "Lua \"\(body)\""
        }
    }
}
