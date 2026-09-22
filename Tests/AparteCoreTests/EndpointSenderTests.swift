import Foundation
import XCTest
@testable import AparteCore

final class EndpointSenderTests: XCTestCase {
    func testBareHostGetsHTTPS() throws {
        let url = try EndpointURLValidator.validate("example.com/webhook").get()
        XCTAssertEqual(url.absoluteString, "https://example.com/webhook")
    }

    func testHTTPSIsAccepted() throws {
        let url = try EndpointURLValidator.validate("https://example.com/hook").get()
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "example.com")
    }

    func testHTTPLocalhostIsAccepted() throws {
        let names = ["localhost", "127.0.0.1", "[::1]"]
        for name in names {
            let url = try EndpointURLValidator.validate("http://\(name):5678/webhook").get()
            XCTAssertEqual(url.scheme, "http", name)
        }
    }

    func testHTTPRemoteHostIsRejected() {
        XCTAssertEqual(
            EndpointURLValidator.validate("http://example.com/hook"),
            .failure(.insecureHost)
        )
    }

    func testHostAndPortWithoutASchemeGetsHTTPS() throws {
        let remote = try EndpointURLValidator.validate("example.com:8443/hook").get()
        XCTAssertEqual(remote.absoluteString, "https://example.com:8443/hook")

        let local = try EndpointURLValidator.validate("localhost:5678/webhook").get()
        XCTAssertEqual(local.absoluteString, "https://localhost:5678/webhook")

        let explicit = try EndpointURLValidator.validate("http://localhost:5678/webhook").get()
        XCTAssertEqual(explicit.scheme, "http")
        XCTAssertEqual(explicit.host, "localhost")
        XCTAssertEqual(explicit.port, 5678)
    }

    func testUnsupportedSchemesAreRejected() {
        for text in ["ftp://example.com/file", "file:///tmp/note.md", "javascript:alert(1)", "mailto:a@b", "file:/tmp/x"] {
            XCTAssertEqual(EndpointURLValidator.validate(text), .failure(.unsupportedScheme), text)
        }
    }

    func testEmbeddedCredentialsAreRejected() {
        XCTAssertEqual(
            EndpointURLValidator.validate("https://user:pass@example.com/hook"),
            .failure(.embeddedCredentials)
        )
        XCTAssertEqual(
            EndpointURLValidator.validate("https://user@example.com/hook"),
            .failure(.embeddedCredentials)
        )
        XCTAssertEqual(
            EndpointURLError.embeddedCredentials.errorDescription,
            "Remove the username from the address."
        )
    }

    func testEmptyAndWhitespaceAreRejected() {
        XCTAssertEqual(EndpointURLValidator.validate(""), .failure(.empty))
        XCTAssertEqual(EndpointURLValidator.validate("   \n"), .failure(.empty))
    }

    func testMissingHostIsRejected() {
        XCTAssertEqual(EndpointURLValidator.validate("https://"), .failure(.missingHost))
    }

    func testWhitespaceAroundAValidAddressIsTrimmed() throws {
        let url = try EndpointURLValidator.validate("  https://example.com/hook  ").get()
        XCTAssertEqual(url.absoluteString, "https://example.com/hook")
    }

    func testPayloadJSONHasTheThreeKeys() throws {
        let sentAt = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = EndpointPayload(markdown: "# Note\n\nBody", title: "Note", sentAt: sentAt)
        XCTAssertEqual(payload.title, MarkdownFileExporter.suggestedBaseName(for: payload.markdown))

        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let data = try encoder.encode(payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(Set(object.keys), ["markdown", "title", "sentAt"])
        XCTAssertEqual(object["markdown"], "# Note\n\nBody")
        XCTAssertEqual(object["title"], "Note")
        XCTAssertEqual(object["sentAt"], "2023-11-14T22:13:20Z")
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("\\/"))
    }

    func testSuccessStatuses() async throws {
        for status in [200, 201, 204, 299] {
            let sender = EndpointSender(session: try stubSession(status: status))
            let result = await sender.send(samplePayload, to: sampleURL)
            guard case .success = result else {
                return XCTFail("status \(status) should succeed, got \(result)")
            }
        }
    }

    func testFailureStatusesNameTheCode() async throws {
        for status in [404, 500] {
            let sender = EndpointSender(session: try stubSession(status: status))
            let result = await sender.send(samplePayload, to: sampleURL)
            guard case let .failure(error) = result else {
                return XCTFail("status \(status) should fail")
            }
            XCTAssertEqual(error, .badStatus(status))
            XCTAssertEqual(error.errorDescription, "The endpoint answered \(status).")
        }
    }

    func testRequestIsAPOSTOfThePayloadWithNoAuthorization() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EndpointCapturingStub.self]
        EndpointCapturingStub.reset()
        let sender = EndpointSender(session: URLSession(configuration: configuration))
        let payload = EndpointPayload(markdown: "# Note\n\nBody", title: "Note", sentAt: Date(timeIntervalSince1970: 1_700_000_000))

        let result = await sender.send(payload, to: sampleURL)
        guard case .success = result else {
            return XCTFail("expected success, got \(result)")
        }

        let request = try XCTUnwrap(EndpointCapturingStub.requests.first)
        XCTAssertEqual(EndpointCapturingStub.requests.count, 1)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        // URLSession moves httpBody onto the stream before the protocol sees the request.
        let body = try XCTUnwrap(Self.bodyData(from: request))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(object["markdown"], payload.markdown)
        XCTAssertEqual(object["title"], payload.title)
        XCTAssertEqual(object["sentAt"], payload.sentAt)
    }

    func testRedirectIsRefusedAndNotFollowed() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EndpointRedirectStub.self]
        EndpointRedirectStub.reset()
        let delegate = EndpointRedirectRefuser()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let sender = EndpointSender(session: session)

        let result = await sender.send(samplePayload, to: sampleURL)
        guard case let .failure(error) = result else {
            return XCTFail("a redirect should fail, got \(result)")
        }
        XCTAssertEqual(error, .redirected)
        XCTAssertEqual(error.errorDescription, "The endpoint redirected. Use the final address.")
        XCTAssertEqual(EndpointRedirectStub.requestedURLs, [sampleURL])
    }

    func testTransportFailureSurfacesTheMessage() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EndpointTransportStub.self]
        let sender = EndpointSender(session: URLSession(configuration: configuration))
        let result = await sender.send(samplePayload, to: sampleURL)
        guard case let .failure(.transport(message)) = result else {
            return XCTFail("expected a transport failure, got \(result)")
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testChunkedResponseCompletesWithoutKeepingItsBody() async throws {
        let session = streamingSession()
        defer { session.invalidateAndCancel() }
        EndpointStreamingStub.events.reset()
        let result = await EndpointSender(session: session).send(samplePayload, to: sampleURL.appendingPathComponent("chunks"))
        guard case .success = result else { return XCTFail("expected completed transfer, got \(result)") }
        XCTAssertEqual(EndpointStreamingStub.events.chunkCount, 128)
    }

    func testTransportFailureAfterSuccessfulHeadersIsStillAFailure() async throws {
        let session = streamingSession()
        defer { session.invalidateAndCancel() }
        let result = await EndpointSender(session: session).send(samplePayload, to: sampleURL.appendingPathComponent("late-failure"))
        guard case let .failure(.transport(message)) = result else {
            return XCTFail("must wait for the body and report its failure, got \(result)")
        }
        XCTAssertEqual(message, URLError(.networkConnectionLost).localizedDescription)
    }

    func testCancellingAnActiveResponseStopsTheTransfer() async throws {
        let session = streamingSession()
        defer { session.invalidateAndCancel() }
        let started = expectation(description: "response started")
        let stopped = expectation(description: "transfer cancelled")
        EndpointStreamingStub.events.reset(started: started, stopped: stopped)
        let sender = EndpointSender(session: session)
        let payload = samplePayload
        let url = sampleURL.appendingPathComponent("hang")
        let task = Task { await sender.send(payload, to: url) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        await fulfillment(of: [stopped], timeout: 2)
        guard case .failure(.transport) = await task.value else { return XCTFail("cancelled send must fail") }
    }

    func testCancellationBeforeTaskCreationCompletes() async throws {
        let session = streamingSession()
        defer { session.invalidateAndCancel() }
        let sender = EndpointSender(session: session)
        let payload = samplePayload
        let url = sampleURL.appendingPathComponent("chunks")
        let finished = expectation(description: "cancelled task completed")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let result = await sender.send(payload, to: url)
            finished.fulfill()
            return result
        }
        await fulfillment(of: [finished], timeout: 2)
        guard case .failure(.transport) = await task.value else { return XCTFail("pre-cancelled send must fail") }
    }

    func testRedirectIsRefusedWithoutASessionDelegate() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EndpointRedirectStub.self]
        EndpointRedirectStub.reset()
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let result = await EndpointSender(session: session).send(samplePayload, to: sampleURL)
        guard case .failure(.redirected) = result else { return XCTFail("redirect should be refused") }
        XCTAssertEqual(EndpointRedirectStub.requestedURLs, [sampleURL])
    }

    private func streamingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EndpointStreamingStub.self]
        return URLSession(configuration: configuration)
    }

    private var samplePayload: EndpointPayload {
        EndpointPayload(markdown: "Hello", title: "Hello", sentAt: Date(timeIntervalSince1970: 0))
    }

    private var sampleURL: URL {
        URL(string: "https://example.com/webhook")!
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1024)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private func stubSession(status: Int, body: Data = Data()) throws -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EndpointStatusStub.self]
        EndpointStatusStub.responseStatus = status
        EndpointStatusStub.responseBody = body
        return URLSession(configuration: configuration)
    }
}

/// Sends bounded chunks, then completes, fails late, or waits for cancellation.
private final class EndpointStreamingStub: URLProtocol, @unchecked Sendable {
    final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var chunks = 0
        private var started: XCTestExpectation?
        private var stopped: XCTestExpectation?
        var chunkCount: Int { lock.withLock { chunks } }

        func reset(started: XCTestExpectation? = nil, stopped: XCTestExpectation? = nil) {
            lock.withLock { chunks = 0; self.started = started; self.stopped = stopped }
        }
        func start() { lock.withLock { started }?.fulfill() }
        func stop() { lock.withLock { stopped }?.fulfill() }
        func chunk() { lock.withLock { chunks += 1 } }
    }
    static let events = Events()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if url.lastPathComponent == "hang" { Self.events.start(); return }
        let chunk = Data(repeating: 0x61, count: 64 * 1024)
        for _ in 0..<128 {
            Self.events.chunk()
            client?.urlProtocol(self, didLoad: chunk)
        }
        if url.lastPathComponent == "late-failure" {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {
        if request.url?.lastPathComponent == "hang" { Self.events.stop() }
    }
}

/// Records each request, then answers 204. Never opens a socket.
private final class EndpointCapturingStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [URLRequest] = []

    static func reset() { requests = [] }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard
            let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Offers a 302. URLSession only consults the redirect delegate when the protocol reports one.
/// A session that accepts the redirect requests the Location URL; this records that too.
private final class EndpointRedirectStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestedURLs: [URL] = []
    private static let redirected = URL(string: "https://elsewhere.example/stolen")!

    static func reset() { requestedURLs = [] }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.requestedURLs.append(url)
        if url.host == "example.com" {
            var redirectedRequest = request
            redirectedRequest.url = Self.redirected
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": Self.redirected.absoluteString]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, wasRedirectedTo: redirectedRequest, redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("followed".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Answers every request with a fixed status. Never opens a socket.
private final class EndpointStatusStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseStatus = 200
    nonisolated(unsafe) static var responseBody = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let status = Self.responseStatus
        let body = Self.responseBody
        guard
            let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Fails before any bytes leave the process.
private final class EndpointTransportStub: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
    }

    override func stopLoading() {}
}
