import Foundation

/// Turns ticked cues into grandMA3 Timecode events via the Lua Object API,
/// UPSERTing per cue. Convention: TC pool number == sequence number. 25 fps.
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
/// UPSERT variant of the web `buildTcCmdLines` path: instead of wiping the whole
/// track (web) or blindly appending (which stacked duplicate events for a
/// re-sent cue), we delete only the existing events whose `cuedestination` points
/// to a cue we're re-sending, then append the fresh ones. Events for OTHER cues
/// stay untouched, and re-sending a cue replaces rather than duplicates it.
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

    /// At most ONE inline-Lua command for the song's ticked+valid cues.
    /// Empty when nothing is ticked/valid. Append-only: no delete phase.
    public static func lines(song: Song, ticked: Set<UUID>) -> [String] {
        let evs = events(song: song, ticked: ticked)
        guard !evs.isEmpty else { return [] }

        let n = song.sequence
        // {cueN,rawtime} pairs for the desk-side append loop.
        let cuesLit = evs.map { "{\(formatN($0.cueN)),\($0.rawtime)}" }.joined(separator: ",")
        // Set of cue numbers we're (re)sending, for the per-cue cleanup pass.
        let wantLit = evs.map { "[\(formatN($0.cueN))]=true" }.joined(separator: ",")

        // Single-quoted Lua only — NO double-quotes/backslashes inside the outer
        // `Lua "..."` wrapper (MA3's command-line tokenizer terminates the arg at
        // the first `"` and ignores backslash escapes).
        //
        // Diagnostics: the work runs inside `go()` wrapped in `pcall`, and every
        // exit point `Printf`s to MA3's System Monitor / command-line feedback.
        // Silent guard bails were why an "accepted" command could leave the
        // timeline empty with zero feedback — now each failure names itself, the
        // TrackGroup child count is reported when `tg[2]` is missing (the prime
        // suspect: only the internal pseudo-track exists, so the user Track at
        // tg[2] was never created), and runtime errors surface via pcall.
        //
        // tg[2] is the first user Track (tg[1] is an internal pseudo-track).
        // UPSERT per cue: we never wipe the whole track, but before appending we
        // delete any existing event whose `cuedestination` points to a cue we're
        // re-sending — so re-sending replaces that cue's event instead of stacking
        // a duplicate, while events for OTHER cues are left untouched. Matching is
        // by cue number read off the event's `cuedestination` handle (`.no`),
        // wrapped in pcall; a `removed N` Printf confirms the cleanup landed.
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
            "local rng=tr:Acquire()",
            "if not rng then Printf('[Saetta TC] could not Acquire TimeRange on TC '..n) return end",
            "local sub=rng:Acquire('CmdSubTrack')",
            "if not sub then Printf('[Saetta TC] could not Acquire CmdSubTrack on TC '..n) return end",
            // Per-cue cleanup: drop existing events for the cues we're re-sending.
            "local want={\(wantLit)}",
            "local existing=sub:Children()",
            "local removed=0 local unresolved=0",
            "for i=#existing,1,-1 do local e=existing[i] local no pcall(function() local d=e.cuedestination if d~=nil then no=tonumber(tostring(d.no)) end end) if no==nil then unresolved=unresolved+1 elseif want[no] then e:Delete() removed=removed+1 end end",
            "Printf('[Saetta TC] removed '..removed..' existing event(s) for re-sent cue(s)'..(unresolved>0 and ' (warn: '..unresolved..' event(s) had no readable cuedestination)' or ''))",
            // Append the fresh events.
            "local k=0",
            "for _,c in ipairs({\(cuesLit)}) do local e=sub:Acquire() e:Set('rawtime',c[2]) local cue=GetObject('Sequence '..n..' Cue '..c[1]) if cue then e:Set('cuedestination',cue) else Printf('[Saetta TC] warn: Sequence '..n..' Cue '..c[1]..' not found, event has no destination') end k=k+1 end",
            "Printf('[Saetta TC] seq '..n..' appended '..k..' event(s)')",
            "end",
            "local ok,err=pcall(go)",
            "if not ok then Printf('[Saetta TC] ERROR: '..tostring(err)) end",
        ].joined(separator: " ")

        return ["Lua \"\(body)\""]
    }
}
