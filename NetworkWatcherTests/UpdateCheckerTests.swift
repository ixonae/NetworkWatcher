import XCTest

// MARK: - Mock URLProtocol

private class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Version Comparison Tests

final class UpdateCheckerTests: XCTestCase {

    private let checker = UpdateChecker()

    func testNewerMajorVersion() {
        XCTAssertTrue(checker.isNewerVersion("2.0.0", than: "1.0.0"))
    }

    func testNewerMinorVersion() {
        XCTAssertTrue(checker.isNewerVersion("1.1.0", than: "1.0.0"))
    }

    func testNewerPatchVersion() {
        XCTAssertTrue(checker.isNewerVersion("1.0.1", than: "1.0.0"))
    }

    func testSameVersion() {
        XCTAssertFalse(checker.isNewerVersion("1.0.0", than: "1.0.0"))
    }

    func testOlderVersion() {
        XCTAssertFalse(checker.isNewerVersion("1.0.0", than: "2.0.0"))
    }

    func testDifferentLengthVersionsNewerLatest() {
        XCTAssertTrue(checker.isNewerVersion("1.0.1", than: "1.0"))
    }

    func testDifferentLengthVersionsSameCurrent() {
        XCTAssertFalse(checker.isNewerVersion("1.0", than: "1.0.0"))
    }

    func testDifferentLengthVersionsOlderLatest() {
        XCTAssertFalse(checker.isNewerVersion("1.0", than: "1.0.1"))
    }

    func testTwoPartVersions() {
        XCTAssertTrue(checker.isNewerVersion("1.1", than: "1.0"))
        XCTAssertFalse(checker.isNewerVersion("1.0", than: "1.1"))
    }

    func testSinglePartVersions() {
        XCTAssertTrue(checker.isNewerVersion("2", than: "1"))
        XCTAssertFalse(checker.isNewerVersion("1", than: "2"))
    }
}

// MARK: - Network Tests

final class UpdateCheckerNetworkTests: XCTestCase {

    private var checker: UpdateChecker!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        checker = UpdateChecker(session: session)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testCheckForUpdateNewerVersionAvailable() async {
        let json: [String: Any] = [
            "tag_name": "v2.0.0",
            "html_url": "https://github.com/ixonae/NetworkWatcher/releases/tag/v2.0.0",
        ]
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try! JSONSerialization.data(withJSONObject: json)
            return (response, data)
        }

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")
        XCTAssertEqual(result, .available(version: "2.0.0", url: "https://github.com/ixonae/NetworkWatcher/releases/tag/v2.0.0"))
    }

    func testCheckForUpdateUpToDate() async {
        let json: [String: Any] = [
            "tag_name": "v1.0.0",
            "html_url": "https://github.com/ixonae/NetworkWatcher/releases/tag/v1.0.0",
        ]
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try! JSONSerialization.data(withJSONObject: json)
            return (response, data)
        }

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")
        XCTAssertEqual(result, .upToDate)
    }

    func testCheckForUpdateTagWithoutPrefix() async {
        let json: [String: Any] = [
            "tag_name": "2.0.0",
            "html_url": "https://github.com/ixonae/NetworkWatcher/releases/tag/2.0.0",
        ]
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try! JSONSerialization.data(withJSONObject: json)
            return (response, data)
        }

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")
        XCTAssertEqual(result, .available(version: "2.0.0", url: "https://github.com/ixonae/NetworkWatcher/releases/tag/2.0.0"))
    }

    func testCheckForUpdateServerError() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")
        XCTAssertEqual(result, .error("Could not fetch releases."))
    }

    func testCheckForUpdateMalformedJSON() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "not json".data(using: .utf8)!)
        }

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")
        XCTAssertEqual(result, .error("Could not parse release info."))
    }

    func testCheckForUpdateMissingFields() async {
        let json: [String: Any] = ["tag_name": "v2.0.0"]
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try! JSONSerialization.data(withJSONObject: json)
            return (response, data)
        }

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")
        XCTAssertEqual(result, .error("Could not parse release info."))
    }

    func testCheckForUpdateNetworkError() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")
        XCTAssertEqual(result, .error("Network error."))
    }

    func testCheckForUpdateSetsAcceptHeader() async {
        var capturedRequest: URLRequest?
        let json: [String: Any] = [
            "tag_name": "v1.0.0",
            "html_url": "https://github.com/ixonae/NetworkWatcher/releases/tag/v1.0.0",
        ]
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try! JSONSerialization.data(withJSONObject: json)
            return (response, data)
        }

        _ = await checker.checkForUpdate(currentVersion: "1.0.0")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
    }
}
