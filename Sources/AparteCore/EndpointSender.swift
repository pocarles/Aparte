import Foundation

/// The body posted when the user sends the pad to an endpoint.
public struct EndpointPayload: Encodable, Sendable, Equatable {
    public var markdown: String
    public var title: String
    public var sentAt: String

    public init(markdown: String, title: String, sentAt: Date = Date()) {
        self.markdown = markdown
        self.title = title
        self.sentAt = EndpointPayload.timestamp(for: sentAt)
    }

    /// ISO 8601 in UTC, without fractional seconds.
    static func timestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.string(from: date)
    }
}

public enum EndpointURLError: Error, LocalizedError, Equatable, Sendable {
    case empty
    case unsupportedScheme
    case insecureHost
    case missingHost
    case embeddedCredentials

    public var errorDescription: String? {
        switch self {
        case .empty:
            "Enter an address."
        case .unsupportedScheme:
            "Use an https address."
        case .insecureHost:
            "Use https, or http only for localhost."
        case .missingHost:
            "That address has no host."
        case .embeddedCredentials:
            "Remove the username from the address."
        }
    }
}

public enum EndpointURLValidator {
    /// Local hosts a self-hosted tool such as n8n may use over plain http.
    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    public static func validate(_ text: String) -> Result<URL, EndpointURLError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        let candidate: String
        if trimmed.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) != nil {
            candidate = trimmed
        } else if hasUnsupportedScheme(trimmed) {
            return .failure(.unsupportedScheme)
        } else {
            candidate = "https://\(trimmed)"
        }

        guard let components = URLComponents(string: candidate), let scheme = components.scheme?.lowercased() else {
            return .failure(.missingHost)
        }
        guard scheme == "https" || scheme == "http" else {
            return .failure(.unsupportedScheme)
        }
        guard let host = components.host, !host.isEmpty else {
            return .failure(.missingHost)
        }
        if components.user != nil || components.password != nil {
            return .failure(.embeddedCredentials)
        }
        // URLComponents keeps the brackets on an IPv6 host, so "[::1]" is "::1".
        let bareHost = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if scheme == "http", !loopbackHosts.contains(bareHost) {
            return .failure(.insecureHost)
        }
        guard let url = components.url else {
            return .failure(.missingHost)
        }
        return .success(url)
    }

    /// A colon before the first slash is a port only when digits follow it.
    /// `localhost:5678/webhook` is a host and port; `javascript:alert(1)` and `file:/tmp/x` are not.
    private static func hasUnsupportedScheme(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let slash = text.firstIndex(of: "/") ?? text.endIndex
        guard colon < slash else { return false }
        let port = text[text.index(after: colon)..<slash]
        return port.isEmpty || port.contains(where: { !$0.isNumber })
    }
}

public enum EndpointSendError: Error, LocalizedError, Equatable, Sendable {
    case badStatus(Int)
    case redirected
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case let .badStatus(status):
            "The endpoint answered \(status)."
        case .redirected:
            "The endpoint redirected. Use the final address."
        case let .transport(message):
            message
        }
    }
}

/// Declines every redirect so a POST cannot leave the address the user typed.
final class EndpointRedirectRefuser: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// One transfer, with only its continuation and task retained. URLSession delivers
/// response data in chunks; none of those chunks become part of the saved state.
private final class EndpointResponseDiscarder: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URLResponse?, Error>?
    private var task: URLSessionDataTask?
    private var cancelled = false

    func response(for request: URLRequest, using session: URLSession) async throws -> URLResponse? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request)
                task.delegate = self
                lock.lock()
                self.continuation = continuation
                self.task = task
                let alreadyCancelled = cancelled
                lock.unlock()
                if alreadyCancelled { task.cancel() }
                else { task.resume() }
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // The response body is not used. Discard each chunk but finish the transfer
        // so a transport failure after the headers still reports a failed send.
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        self.task = nil
        lock.unlock()
        if let error { continuation?.resume(throwing: error) }
        else { continuation?.resume(returning: task.response) }
    }
}

/// Performs one POST. Tests substitute `session`; the default never shares a cache.
public struct EndpointSender: Sendable {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        self.session = session ?? EndpointSender.makeSession()
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        // The delegate has to live as long as the session, so the session retains it.
        return URLSession(configuration: configuration, delegate: EndpointRedirectRefuser(), delegateQueue: nil)
    }

    public func send(_ payload: EndpointPayload, to url: URL) async -> Result<Void, EndpointSendError> {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        do {
            request.httpBody = try encoder.encode(payload)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }

        let response: URLResponse
        do {
            guard let received = try await EndpointResponseDiscarder().response(for: request, using: session) else {
                return .failure(.transport("The endpoint did not answer."))
            }
            response = received
        } catch {
            return .failure(.transport(error.localizedDescription))
        }

        guard let http = response as? HTTPURLResponse else {
            return .failure(.transport("The endpoint did not answer."))
        }
        if (300...399).contains(http.statusCode) {
            return .failure(.redirected)
        }
        guard (200...299).contains(http.statusCode) else {
            return .failure(.badStatus(http.statusCode))
        }
        return .success(())
    }
}
