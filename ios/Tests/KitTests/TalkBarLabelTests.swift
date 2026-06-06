import XCTest
@testable import SaettaKit

final class TalkBarLabelTests: XCTestCase {
    typealias Phase = VoiceCaptureController.Phase

    func testLabels() {
        XCTAssertEqual(Phase.idle.talkBarLabel, "Tap to talk")
        XCTAssertEqual(Phase.error("x").talkBarLabel, "Tap to talk")
        XCTAssertEqual(Phase.recording.talkBarLabel, "Listening\u{2026} tap to stop")
        XCTAssertEqual(Phase.transcribing.talkBarLabel, "Thinking\u{2026}")
        XCTAssertEqual(Phase.interpreting.talkBarLabel, "Thinking\u{2026}")
        XCTAssertEqual(Phase.preview.talkBarLabel, "Reviewing\u{2026}")
    }

    func testButtonLabels() {
        XCTAssertEqual(Phase.idle.talkButtonLabel, "Talk")
        XCTAssertEqual(Phase.error("x").talkButtonLabel, "Talk")
        XCTAssertEqual(Phase.recording.talkButtonLabel, "Stop")
        XCTAssertEqual(Phase.transcribing.talkButtonLabel, "\u{2026}")
        XCTAssertEqual(Phase.interpreting.talkButtonLabel, "\u{2026}")
        XCTAssertEqual(Phase.preview.talkButtonLabel, "\u{2026}")
    }

    func testFlags() {
        XCTAssertTrue(Phase.recording.isRecording)
        XCTAssertFalse(Phase.idle.isRecording)
        XCTAssertTrue(Phase.transcribing.isBusy)
        XCTAssertTrue(Phase.interpreting.isBusy)
        XCTAssertFalse(Phase.idle.isBusy)
        XCTAssertFalse(Phase.recording.isBusy)
        XCTAssertFalse(Phase.preview.isRecording)
        XCTAssertFalse(Phase.error("x").isRecording)
        XCTAssertFalse(Phase.transcribing.isRecording)
        XCTAssertFalse(Phase.interpreting.isRecording)
        XCTAssertFalse(Phase.preview.isBusy)
        XCTAssertFalse(Phase.error("x").isBusy)
    }
}
