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

    override func stopLoading() {
        // No cleanup needed for mock protocol
    }
}

// MARK: - Tests

final class IPCheckerTests: XCTestCase {

    private var checker: IPChecker!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        checker = IPChecker(session: session)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - Invalid URL

    func testFetchExternalIPEmptyURL() async {
        do {
            _ = try await checker.fetchExternalIP(from: "")
            XCTFail("Should have thrown")
        } catch let error as IPCheckerError {
            XCTAssertEqual(error, .invalidURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchExternalIPUrlWithSpaces() async {
        do {
            _ = try await checker.fetchExternalIP(from: "ht tp://bad url")
            XCTFail("Should have thrown")
        } catch let error as IPCheckerError {
            XCTAssertEqual(error, .invalidURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Success

    func testFetchExternalIPSuccess() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, TestIP.stub.data(using: .utf8)!)
        }

        let ip = try await checker.fetchExternalIP(from: "https://example.com/ip")
        XCTAssertEqual(ip, TestIP.stub)
    }

    func testFetchExternalIPTrimsWhitespace() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "  \(TestIP.stub)\n".data(using: .utf8)!)
        }

        let ip = try await checker.fetchExternalIP(from: "https://example.com/ip")
        XCTAssertEqual(ip, TestIP.stub)
    }

    // MARK: - Auth Token

    func testFetchExternalIPSetsAuthorizationHeader() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, TestIP.stub.data(using: .utf8)!)
        }

        _ = try await checker.fetchExternalIP(from: "https://example.com/ip", authToken: "myToken123")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer myToken123")
    }

    func testFetchExternalIPNoAuthHeaderWhenTokenNil() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, TestIP.stub.data(using: .utf8)!)
        }

        _ = try await checker.fetchExternalIP(from: "https://example.com/ip", authToken: nil)
        XCTAssertNil(capturedRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    func testFetchExternalIPNoAuthHeaderWhenTokenEmpty() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, TestIP.stub.data(using: .utf8)!)
        }

        _ = try await checker.fetchExternalIP(from: "https://example.com/ip", authToken: "")
        XCTAssertNil(capturedRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: - Error Responses

    func testFetchExternalIPBadResponse404() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await checker.fetchExternalIP(from: "https://example.com/ip")
            XCTFail("Should have thrown")
        } catch let error as IPCheckerError {
            XCTAssertEqual(error, .badResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchExternalIPBadResponse500() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await checker.fetchExternalIP(from: "https://example.com/ip")
            XCTFail("Should have thrown")
        } catch let error as IPCheckerError {
            XCTAssertEqual(error, .badResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchExternalIPEmptyBody() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await checker.fetchExternalIP(from: "https://example.com/ip")
            XCTFail("Should have thrown")
        } catch let error as IPCheckerError {
            XCTAssertEqual(error, .invalidData)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchExternalIPWhitespaceOnlyBody() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "  \n  ".data(using: .utf8)!)
        }

        do {
            _ = try await checker.fetchExternalIP(from: "https://example.com/ip")
            XCTFail("Should have thrown")
        } catch let error as IPCheckerError {
            XCTAssertEqual(error, .invalidData)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Error Descriptions

    func testIPCheckerErrorDescriptions() {
        XCTAssertNotNil(IPCheckerError.invalidURL.errorDescription)
        XCTAssertNotNil(IPCheckerError.badResponse.errorDescription)
        XCTAssertNotNil(IPCheckerError.invalidData.errorDescription)

        XCTAssertEqual(IPCheckerError.invalidURL.errorDescription, "Invalid IP lookup URL")
        XCTAssertEqual(IPCheckerError.badResponse.errorDescription, "Bad response from IP lookup service")
        XCTAssertEqual(IPCheckerError.invalidData.errorDescription, "Could not parse IP address from response")
    }

    // MARK: - Response validation

    private func assertInvalidData(body: String, file: StaticString = #filePath, line: UInt = #line) async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
        do {
            let ip = try await checker.fetchExternalIP(from: "https://example.com/ip")
            XCTFail("Should have thrown, got \(ip)", file: file, line: line)
        } catch let error as IPCheckerError {
            XCTAssertEqual(error, .invalidData, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    func testCaptivePortalHTMLIsRejected() async {
        await assertInvalidData(body: "<html><head><title>Wi-Fi Login</title></head><body>Sign in</body></html>")
    }

    func testCIDRBodyIsRejected() async {
        await assertInvalidData(body: TestIP.cidr10_24)
    }

    func testWildcardBodyIsRejected() async {
        await assertInvalidData(body: "*")
    }

    func testMultipleAddressesAreRejected() async {
        await assertInvalidData(body: "\(TestIP.stub)\n\(TestIP.secondary)")
    }

    func testJSONBodyIsRejected() async {
        await assertInvalidData(body: #"{"ip":"1.2.3.4"}"#)
    }

    func testIPv6BodyIsAccepted() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("\(TestIP.v6)\n".utf8))
        }
        let ip = try await checker.fetchExternalIP(from: "https://example.com/ip")
        XCTAssertEqual(ip, TestIP.v6)
    }

    // MARK: - Timeout

    func testRequestUsesShortTimeout() async throws {
        var timeout: TimeInterval?
        MockURLProtocol.requestHandler = { request in
            timeout = request.timeoutInterval
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(TestIP.stub.utf8))
        }
        _ = try await checker.fetchExternalIP(from: "https://example.com/ip")
        XCTAssertEqual(timeout, 10)
        XCTAssertEqual(IPChecker.requestTimeout, 10)
    }

    // MARK: - Failure reasons

    func testFailureReasonForCheckerErrors() {
        XCTAssertEqual(IPChecker.failureReason(for: IPCheckerError.invalidURL), "invalid lookup URL")
        XCTAssertEqual(IPChecker.failureReason(for: IPCheckerError.badResponse), "lookup service error")
        XCTAssertEqual(IPChecker.failureReason(for: IPCheckerError.invalidData), "no valid IP in response")
    }

    func testFailureReasonForURLErrors() {
        XCTAssertEqual(IPChecker.failureReason(for: URLError(.timedOut)), "lookup timed out")
        XCTAssertEqual(IPChecker.failureReason(for: URLError(.notConnectedToInternet)), "offline")
        XCTAssertEqual(IPChecker.failureReason(for: URLError(.networkConnectionLost)), "offline")
        XCTAssertEqual(IPChecker.failureReason(for: URLError(.cannotFindHost)), "lookup host not found")
        XCTAssertEqual(IPChecker.failureReason(for: URLError(.badServerResponse)), "lookup failed")
    }

    func testFailureReasonForOtherErrors() {
        XCTAssertEqual(IPChecker.failureReason(for: NSError(domain: "x", code: 1)), "lookup failed")
    }
}
