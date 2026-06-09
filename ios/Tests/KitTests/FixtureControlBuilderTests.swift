import XCTest
@testable import SaettaKit

final class FixtureControlBuilderTests: XCTestCase {

    func test_intensity_nudge_positive_and_negative() {
        XCTAssertEqual(FixtureControlBuilder.intensityNudge(5), "At + 5")
        XCTAssertEqual(FixtureControlBuilder.intensityNudge(-5), "At - 5")
        XCTAssertNil(FixtureControlBuilder.intensityNudge(0), "zero delta emits nothing")
    }

    func test_attribute_nudge() {
        XCTAssertEqual(FixtureControlBuilder.attributeNudge("Pan", 5), "Attribute \"Pan\" At + 5")
        XCTAssertEqual(FixtureControlBuilder.attributeNudge("Tilt", -3), "Attribute \"Tilt\" At - 3")
        XCTAssertNil(FixtureControlBuilder.attributeNudge("Pan", 0))
    }

    func test_recall_preset_uses_pool_number() {
        XCTAssertEqual(FixtureControlBuilder.recallPreset(pool: .color, number: 3), "At Preset 4.3")
        XCTAssertEqual(FixtureControlBuilder.recallPreset(pool: .gobo, number: 1), "At Preset 3.1")
    }

    func test_clear_constant() {
        XCTAssertEqual(FixtureControlBuilder.clear, "ClearAll")
    }

    func test_store_cue_overwrite_and_merge() {
        XCTAssertEqual(FixtureControlBuilder.storeCue(sequence: 5, cue: 2, mode: .overwrite),
                       "Store Sequence 5 Cue 2 /Overwrite /NoConfirmation")
        XCTAssertEqual(FixtureControlBuilder.storeCue(sequence: 5, cue: 2, mode: .merge),
                       "Store Sequence 5 Cue 2 /Merge /NoConfirmation")
    }

    func test_update_preset() {
        XCTAssertEqual(FixtureControlBuilder.updatePreset(pool: .color, number: 3, mode: .overwrite),
                       "Store Preset 4.3 /Overwrite /NoConfirmation")
        XCTAssertEqual(FixtureControlBuilder.updatePreset(pool: .position, number: 1, mode: .merge),
                       "Store Preset 2.1 /Merge /NoConfirmation")
    }
}
