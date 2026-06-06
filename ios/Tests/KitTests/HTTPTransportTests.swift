import XCTest
@testable import SaettaKit

final class HTTPTransportTests: XCTestCase {
    func testMockReturnsScriptedResponse() async throws {
        let mock = MockHTTPTransport()
        mock.handler = { req in
            XCTAssertEqual(req.url?.host, "example.com")
            return (Data("ok".utf8), HTTPURLResponse(url: req.url!, statusCode: 200,
                                                     httpVersion: nil, headerFields: nil)!)
        }
        let (data, resp) = try await mock.send(URLRequest(url: URL(string: "https://example.com")!))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "ok")
        XCTAssertEqual(resp.statusCode, 200)
        XCTAssertEqual(mock.sentRequests.count, 1)
    }
}

// MockHTTPTransport is a reusable test double — define it in the test target now
// (later tasks reuse it). Append it to this same file.
final class MockHTTPTransport: HTTPTransport, @unchecked Sendable {
    var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?
    private(set) var sentRequests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sentRequests.append(request)
        guard let handler else { throw URLError(.badServerResponse) }
        return try handler(request)
    }
}
