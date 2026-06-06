import Foundation

/// Builds the grandMA3 command-line string that pops a `MessageBox` on the desk
/// from a free-text operator note. Sent over the existing `cmd` OSC passthrough.
///
/// HARD CONSTRAINT (see TimecodeBuilder): MA3's command-line tokenizer terminates a
/// `Lua "..."` argument at the first inner `"` and ignores backslash escapes — so the
/// body must contain NO double-quotes. We wrap title/message in Lua long brackets
/// `[[ ... ]]` (no quotes needed) and strip `"` and square brackets from the text.
public enum ConsoleMessage {

    /// Max characters kept from the note (the `Lua "..."` arg also truncates near 1 KB
    /// on the desk; 200 keeps us comfortably under and readable on screen).
    static let maxLength = 200

    /// One command-line string, or `nil` if the message sanitizes to empty.
    /// `title` defaults to the app name so the operator knows the source at a glance.
    public static func line(text: String, title: String = "Saetta") -> String? {
        let msg = sanitize(text)
        guard !msg.isEmpty else { return nil }
        let t = sanitize(title)
        return "Lua \"MessageBox({title=[[\(t)]], message=[[\(msg)]], commands={{value=1,name=[[OK]]}}})\""
    }

    /// Make arbitrary text safe for the two parsers (MA command line + Lua long bracket)
    /// and the OSC string transport (which is NUL-terminated — a stray control byte
    /// would truncate the command mid-flight).
    static func sanitize(_ s: String) -> String {
        var out = s
        for ws in ["\n", "\r", "\t"] { out = out.replacingOccurrences(of: ws, with: " ") }
        // Drop remaining control characters (NUL/DEL etc.) before they reach the wire.
        out = String(out.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F })
        out = out.replacingOccurrences(of: "\"", with: "")   // would close the outer Lua "..."
        // Strip ALL square brackets. A lone trailing `]` merges with our `]]`
        // delimiter into `]]]`, closing the Lua [[ ... ]] long string early and
        // leaving a stray `]` → Lua syntax error on the desk. Stripping both is
        // obviously safe and avoids depending on Lua long-string nesting rules.
        out = out.replacingOccurrences(of: "[", with: "")
        out = out.replacingOccurrences(of: "]", with: "")
        // Collapse runs of spaces (and trim ends) in one O(n) pass.
        out = out.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        if out.count > maxLength { out = String(out.prefix(maxLength)) }
        return out
    }
}
