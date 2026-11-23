import Foundation

/// Answers every request of a session built from `sessionConfiguration()`.
/// The handler is shared by all tests, so each test sets it before its first request.
final class StubURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (URLResponse, Data)

    struct Response {
        var statusCode = 200
        var body = Data()
        var error: Error?
    }

    private static let lock = NSLock()
    private static var storedHandler: Handler?

    static var handler: Handler? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedHandler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedHandler = newValue
        }
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    /// Answers each listed URL with its response and a matching Content-Length.
    /// Any other URL fails with `URLError(.unsupportedURL)`.
    static func serve(_ responses: [URL: Response]) {
        handler = { request in
            guard let url = request.url, let response = responses[url] else {
                throw URLError(.unsupportedURL)
            }
            if let error = response.error {
                throw error
            }
            let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "\(response.body.count)"]
            )!
            return (httpResponse, response.body)
        }
    }

    /// URLSession moves an upload body into `httpBodyStream`, so read the stream when `httpBody` is nil.
    static func requestBody(of request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                return nil
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
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
