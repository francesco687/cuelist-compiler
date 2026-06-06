import Foundation

/// SMPTE `HH:MM:SS:FF` helpers, hard-coded to 25 fps (PAL/EBU), matching the
/// web timecode contract. `time` on a grandMA3 Timecode event is float seconds.
public enum Smpte {
    public static let fps = 25

    private static let pattern = try! NSRegularExpression(pattern: "^(\\d{2}):(\\d{2}):(\\d{2}):(\\d{2})$")

    private static func parts(_ s: String) -> (h: Int, m: Int, sec: Int, f: Int)? {
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let m = pattern.firstMatch(in: s, range: range) else { return nil }
        func grp(_ i: Int) -> Int { Int((s as NSString).substring(with: m.range(at: i))) ?? 0 }
        return (grp(1), grp(2), grp(3), grp(4))
    }

    public static func isValid(_ s: String) -> Bool {
        guard let p = parts(s) else { return false }
        return p.m < 60 && p.sec < 60 && p.f < fps
    }

    /// Seconds as a float STRING for the MA3 `Set ... Property 'time' <secs>` command.
    /// nil for invalid input. Uses the shortest exact decimal (e.g. "0.2", "5.0").
    public static func secondsString(_ s: String) -> String? {
        guard isValid(s), let p = parts(s) else { return nil }
        let seconds = Double(p.h) * 3600 + Double(p.m) * 60 + Double(p.sec) + Double(p.f) / Double(fps)
        // Trim to avoid float noise; keep at least one decimal place.
        var str = String(format: "%.6f", seconds)
        while str.contains("."), str.hasSuffix("0") { str.removeLast() }
        if str.hasSuffix(".") { str += "0" }
        return str
    }
}
