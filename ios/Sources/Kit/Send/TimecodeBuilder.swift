import Foundation

/// Turns ticked cues into grandMA3 Timecode events via the Lua Object API,
/// OVERWRITING the track each send. TC pool number == sequence number. 25 fps.
///
/// Events on MA3 are NOT addressable via the command-line `Store Timecode ...`
/// syntax — that path only creates pool entries / TrackGroups / Tracks and
/// returns "Cannot Create Object" for events (proven dead-end on a real desk
/// 2026-06-06). Events live only behind the Object API (forum thread 68641).
///
/// Object hierarchy (see `shared/ma3-command-spec.md` §Timecode):
///   DataPool().timecodes[N] → TrackGroup `Children()[1]` → Track `tg[2]`
///   (tg[1] is an internal pseudo-track) → TimeRange `Acquire()` →
///   CmdSubTrack `Acquire('CmdSubTrack')` → Event `Acquire()` per cue, with
///   `rawtime` (1 s = 16777216 internal units) and `cuedestination` (Cue handle).
///
/// OVERWRITE (the web `buildTcCmdLines` proven path): each send wipes every
/// TimeRange on the track, then writes one fresh TimeRange + CmdSubTrack holding
/// exactly the ticked cues. So re-sending never duplicates a cue's event. A
/// blind-append variant was tried and abandoned: `Acquire()` creates a NEW empty
/// TimeRange every call, so prior events were never found and stacked up instead
/// (desk diagnostics 2026-06-06). Cost of overwrite: cues not ticked in a given
/// send are not on the track after it — send the full set you want each time.
///
/// We emit ONE inline-`Lua "..."` command per song carrying all ticked cues.
/// The body is single-quoted Lua throughout — it contains NO double-quotes, so
/// the outer `Lua "..."` wrapper parses cleanly through OSC and MA3's command
/// line (the MA3 tokenizer terminates a `Lua "..."` argument at the first `"`
/// and does NOT honor backslash escapes).
public enum TimecodeBuilder {

    /// MA3 internal time units per second (`2^24`).
    static let rawPerSecond = 16_777_216

    public struct Event: Equatable {
        public let sequence: Int
        public let cueN: Double
        public let rawtime: Int
    }

    private static func formatN(_ n: Double) -> String {
        n.rounded() == n ? String(Int(n)) : String(n)
    }

    /// SMPTE → MA3 `rawtime` integer: `round(seconds * 16777216)`.
    static func rawtime(_ position: String) -> Int? {
        guard let secs = Smpte.seconds(position) else { return nil }
        return Int((secs * Double(rawPerSecond)).rounded())
    }

    /// Ticked + valid cues for this song, ascending by cue number.
    public static func events(song: Song, ticked: Set<UUID>) -> [Event] {
        song.cues
            .filter { ticked.contains($0.id) }
            .filter { Smpte.isValid($0.position) }
            .sorted { $0.n < $1.n }
            .compactMap { cue -> Event? in
                guard let raw = rawtime(cue.position) else { return nil }
                return Event(sequence: song.sequence, cueN: cue.n, rawtime: raw)
            }
    }

    /// ONE inline-Lua command that OVERWRITES the song's TC track with the
    /// ticked+valid cues. Empty when nothing is ticked/valid.
    public static func lines(song: Song, ticked: Set<UUID>) -> [String] {
        let evs = events(song: song, ticked: ticked)
        guard !evs.isEmpty else { return [] }

        let n = song.sequence
        // {cueN,rawtime} pairs for the desk-side write loop.
        let cuesLit = evs.map { "{\(formatN($0.cueN)),\($0.rawtime)}" }.joined(separator: ",")

        // Single-quoted Lua only — NO double-quotes/backslashes inside the outer
        // `Lua "..."` wrapper (MA3's command-line tokenizer terminates the arg at
        // the first `"` and ignores backslash escapes).
        //
        // OVERWRITE (the web `buildTcCmdLines` proven path): wipe every TimeRange
        // on the track, then create one fresh TimeRange + CmdSubTrack and write the
        // ticked cues into it. This is why there are never duplicate events for a
        // re-sent cue — the track is rebuilt each send — and it sidesteps the
        // cross-command "find the existing event" problem (Acquire creates a NEW
        // empty TimeRange every call, so prior events were never found). The wipe
        // also clears any leftover empty ranges from the earlier append attempts.
        //
        // Diagnostics: work runs inside `go()` wrapped in `pcall`; every exit point
        // `Printf`s to MA3's System Monitor (the only feedback channel — the hub's
        // OSC is send-only). tg[2] is the first user Track (tg[1] is an internal
        // pseudo-track); a missing tg[2] reports the TrackGroup child count.
        let body = [
            "local n=\(n)",
            "local function go()",
            "local s=DataPool().sequences[n]",
            "local t=DataPool().timecodes[n]",
            "if not s then Printf('[Saetta TC] no Sequence '..n) return end",
            "if not t then Printf('[Saetta TC] no Timecode pool '..n) return end",
            "local tg=t:Children()[1]",
            "if not tg then Printf('[Saetta TC] TC '..n..' has no TrackGroup') return end",
            "local tr=tg[2]",
            "if not tr then Printf('[Saetta TC] TC '..n..' has no user Track at tg[2] (TrackGroup child count='..tostring(#tg)..') -- create a Track targeting Sequence '..n..' on the desk first') return end",
            // Wipe every existing TimeRange on the track (overwrite).
            "local trc=tr:Children()",
            "local wiped=#trc",
            "for i=#trc,1,-1 do trc[i]:Delete() end",
            "Printf('[Saetta TC] wiped '..wiped..' existing TimeRange(s)')",
            // Build one fresh TimeRange + CmdSubTrack and write the ticked cues.
            "local rng=tr:Acquire()",
            "if not rng then Printf('[Saetta TC] could not Acquire TimeRange on TC '..n) return end",
            "local sub=rng:Acquire('CmdSubTrack')",
            "if not sub then Printf('[Saetta TC] could not Acquire CmdSubTrack on TC '..n) return end",
            "local k=0",
            "for _,c in ipairs({\(cuesLit)}) do local e=sub:Acquire() e:Set('rawtime',c[2]) local cue=GetObject('Sequence '..n..' Cue '..c[1]) if cue then e:Set('cuedestination',cue) else Printf('[Saetta TC] warn: Sequence '..n..' Cue '..c[1]..' not found, event has no destination') end k=k+1 end",
            "Printf('[Saetta TC] seq '..n..' wrote '..k..' event(s)')",
            "end",
            "local ok,err=pcall(go)",
            "if not ok then Printf('[Saetta TC] ERROR: '..tostring(err)) end",
        ].joined(separator: " ")

        return ["Lua \"\(body)\""]
    }
}
