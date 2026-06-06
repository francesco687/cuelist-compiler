import XCTest
@testable import SaettaKit

final class ConsoleMessageTests: XCTestCase {

    func test_normal_text_builds_messagebox_line() {
        let line = ConsoleMessage.line(text: "hello")
        XCTAssertEqual(
            line,
            "Lua \"MessageBox({title=[[Saetta]], message=[[hello]], commands={{value=1,name=[[OK]]}}})\""
        )
    }

    func test_body_contains_no_double_quote() {
        // MA3 tokenizer terminates Lua "..." at the first inner ". Body must have none.
        let line = ConsoleMessage.line(text: "say \"go\" now")!
        // Strip the two outer wrapper quotes, assert nothing left inside is a quote.
        let inner = line.dropFirst("Lua \"".count).dropLast(1)   // remove `Lua "` and trailing `"`
        XCTAssertFalse(inner.contains("\""), "body must contain no double-quote")
    }

    func test_strips_double_quotes_from_text() {
        let line = ConsoleMessage.line(text: "a\"b")
        XCTAssertEqual(line, "Lua \"MessageBox({title=[[Saetta]], message=[[ab]], commands={{value=1,name=[[OK]]}}})\"")
    }

    func test_strips_long_bracket_close_from_text() {
        let line = ConsoleMessage.line(text: "a]]b")
        XCTAssertEqual(line, "Lua \"MessageBox({title=[[Saetta]], message=[[ab]], commands={{value=1,name=[[OK]]}}})\"")
    }

    func test_collapses_newlines_tabs_and_runs_to_single_space() {
        let line = ConsoleMessage.line(text: "a\n\tb   c")
        XCTAssertEqual(line, "Lua \"MessageBox({title=[[Saetta]], message=[[a b c]], commands={{value=1,name=[[OK]]}}})\"")
    }

    func test_trims_leading_and_trailing_whitespace() {
        let line = ConsoleMessage.line(text: "  hi  ")
        XCTAssertEqual(line, "Lua \"MessageBox({title=[[Saetta]], message=[[hi]], commands={{value=1,name=[[OK]]}}})\"")
    }

    func test_caps_message_at_200_chars() {
        let long = String(repeating: "x", count: 250)
        let line = ConsoleMessage.line(text: long)!
        // Extract the message between `message=[[` and `]], commands`.
        let start = line.range(of: "message=[[")!.upperBound
        let end = line.range(of: "]], commands")!.lowerBound
        let msg = String(line[start..<end])
        XCTAssertEqual(msg.count, 200)
    }

    func test_empty_text_returns_nil() {
        XCTAssertNil(ConsoleMessage.line(text: ""))
    }

    func test_whitespace_only_returns_nil() {
        XCTAssertNil(ConsoleMessage.line(text: "   \n\t "))
    }

    func test_sanitizes_to_empty_returns_nil() {
        XCTAssertNil(ConsoleMessage.line(text: "\"\""))   // both quotes stripped → empty
    }

    func test_custom_title_appears_and_is_sanitized() {
        let line = ConsoleMessage.line(text: "hi", title: "LX\"Note")
        XCTAssertEqual(line, "Lua \"MessageBox({title=[[LXNote]], message=[[hi]], commands={{value=1,name=[[OK]]}}})\"")
    }
}
