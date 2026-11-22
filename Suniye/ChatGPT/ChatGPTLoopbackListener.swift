import Foundation
import Network

/// A small HTTP listener on 127.0.0.1 for the browser's return from the
/// ChatGPT sign-in. Only this Mac can reach it.
final class ChatGPTLoopbackListener: @unchecked Sendable {
    struct Page: Equatable, Sendable {
        let status: Int
        let text: String

        static let notFound = Page(status: 404, text: "Not found.")
    }

    let port: UInt16
    private let listener: NWListener

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.port = port
    }

    /// Listens on `preferredPort`, or on a free port when that one is in
    /// use. `route` gets the target of each GET request, such as
    /// "/auth/callback?code=…", and gives the page for the browser.
    static func start(preferredPort: UInt16, route: @escaping @Sendable (String) -> Page) async throws -> ChatGPTLoopbackListener {
        do {
            return try await start(port: preferredPort, route: route)
        } catch {
            return try await start(port: 0, route: route)
        }
    }

    func stop() {
        listener.cancel()
    }

    private static func start(port: UInt16, route: @escaping @Sendable (String) -> Page) async throws -> ChatGPTLoopbackListener {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port) ?? .any)
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "dev.suniye.chatgpt.callback")
        listener.newConnectionHandler = { connection in
            serve(connection, on: queue, route: route)
        }
        return try await withCheckedThrowingContinuation { continuation in
            // The first result ends the wait: the handler goes, so the
            // continuation gets one answer.
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    if let bound = listener.port?.rawValue {
                        continuation.resume(returning: ChatGPTLoopbackListener(listener: listener, port: bound))
                    } else {
                        listener.cancel()
                        continuation.resume(throwing: POSIXError(.EADDRNOTAVAIL))
                    }
                case let .failed(error), let .waiting(error):
                    listener.stateUpdateHandler = nil
                    listener.cancel()
                    continuation.resume(throwing: error)
                case .cancelled:
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: CancellationError())
                case .setup:
                    break
                @unknown default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private static func serve(_ connection: NWConnection, on queue: DispatchQueue, route: @escaping @Sendable (String) -> Page) {
        connection.start(queue: queue)
        // The request line of a callback fits in the first read.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, _ in
            let page = data.flatMap(target(ofRequest:)).map(route) ?? .notFound
            connection.send(content: response(page), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    /// "/path?query" of "GET /path?query HTTP/1.1".
    static func target(ofRequest data: Data) -> String? {
        guard let line = String(decoding: data, as: UTF8.self).components(separatedBy: "\r\n").first else { return nil }
        let words = line.split(separator: " ")
        guard words.count == 3, words[0] == "GET" else { return nil }
        return String(words[1])
    }

    static func response(_ page: Page) -> Data {
        let body = Data("<!doctype html><meta charset=\"utf-8\"><title>Suniye</title><body style=\"font: 15px -apple-system, sans-serif; margin: 3em\"><p>\(page.text)</p>".utf8)
        let head = "HTTP/1.1 \(page.status) \(page.status == 200 ? "OK" : "Not Found")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
