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
