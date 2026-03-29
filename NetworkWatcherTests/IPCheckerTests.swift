import XCTest

// MARK: - Mock URLProtocol

private class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
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

    func testFetchExternalIP_emptyURL() async {
        do {
            _ = try await checker.fetchExternalIP(from: "")
            XCTFail("Should have thrown")
        } catch let error as IPCheckerError {
            XCTAssertEqual(error, .invalidURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchExternalIP_urlWithSpaces() async {
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

    func testFetchExternalIP_success() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, TestIP.stub.data(using: .utf8)!)
        }

        let ip = try await checker.fetchExternalIP(from: "https://example.com/ip")
        XCTAssertEqual(ip, TestIP.stub)
    }

    func testFetchExternalIP_trimsWhitespace() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, "  \(TestIP.stub)\n".data(using: .utf8)!)
        }

        let ip = try await checker.fetchExternalIP(from: "https://example.com/ip")
        XCTAssertEqual(ip, TestIP.stub)
    }

    // MARK: - Auth Token

    func testFetchExternalIP_setsAuthorizationHeader() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, TestIP.stub.data(using: .utf8)!)
        }

        _ = try await checker.fetchExternalIP(from: "https://example.com/ip", authToken: "myToken123")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer myToken123")
    }

    func testFetchExternalIP_noAuthHeaderWhenTokenNil() async throws {
        var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, TestIP.stub.data(using: .utf8)!)
        }

        _ = try await checker.fetchExternalIP(from: "https://example.com/ip", authToken: nil)
        XCTAssertNil(capturedRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    func testFetchExternalIP_noAuthHeaderWhenTokenEmpty() async throws {
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

    func testFetchExternalIP_badResponse_404() async {
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

    func testFetchExternalIP_badResponse_500() async {
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

    func testFetchExternalIP_emptyBody() async {
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

    func testFetchExternalIP_whitespaceOnlyBody() async {
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
}
