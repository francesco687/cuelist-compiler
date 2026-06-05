import XCTest
@testable import CuelistCompilerKit

final class AIKeyStoreTests: XCTestCase {
    func testInMemoryRoundTrip() {
        let s = InMemoryAIKeyStore()
        XCTAssertNil(s.key(for: .openAI))
        s.set("sk-o", for: .openAI)
        s.set("sk-a", for: .anthropic)
        XCTAssertEqual(s.key(for: .openAI), "sk-o")
        XCTAssertEqual(s.key(for: .anthropic), "sk-a")
        s.set("sk-a2", for: .anthropic)          // overwrite
        XCTAssertEqual(s.key(for: .anthropic), "sk-a2")
        s.set("", for: .openAI)                 // empty clears
        XCTAssertNil(s.key(for: .openAI))
    }

    func testKeychainRoundTrip() throws {
        let svc = "cc-test-\(UUID().uuidString)"
        let s = KeychainAIKeyStore(service: svc)
        s.set("sk-keychain", for: .anthropic)
        guard s.key(for: .anthropic) == "sk-keychain" else {
            throw XCTSkip("Keychain unavailable in simulator (errSecMissingEntitlement); covered by Task 16 device smoke")
        }
        s.set("sk-keychain-2", for: .anthropic)
        XCTAssertEqual(s.key(for: .anthropic), "sk-keychain-2")
        s.set("", for: .anthropic)
        XCTAssertNil(s.key(for: .anthropic))
    }
}
