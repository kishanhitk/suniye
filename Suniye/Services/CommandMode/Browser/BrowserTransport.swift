import Foundation

/// One reply from the browser extension for a tool request. Scalar result fields
/// are flattened to strings (e.g. `["text": "...", "truncated": "false"]`) so the
/// transport stays as simple as `ToolCall.arguments`; richer shapes (arrays) are
/// carried as a JSON string under their key and parsed by the specific tool.
struct BrowserResponse: Sendable, Equatable {
    let ok: Bool
    let result: [String: String]
    let errorCode: String?
    let errorMessage: String?

    static func success(_ result: [String: String]) -> BrowserResponse {
        BrowserResponse(ok: true, result: result, errorCode: nil, errorMessage: nil)
    }
}

enum BrowserBridgeError: Error, Equatable {
    case notConnected
    case timedOut
    case badResponse(String)
}

/// The seam the browser tools + snapshot reader depend on — NOT the concrete
/// `BrowserBridge` actor — so tests inject a `FakeBrowserTransport` with no sockets
/// (mirrors how `ClickTool` depends on `ElementResolving`, not `AXTreeReader`).
protocol BrowserTransport: Sendable {
    /// Whether a paired extension is currently connected + handshaken.
    var isConnected: Bool { get async }
    /// Send one tool request and await the correlated reply. Throws on timeout /
    /// no connection; a tool-level failure comes back as `ok == false`.
    func send(tool: String, args: [String: String], timeout: TimeInterval) async throws -> BrowserResponse
}

extension BrowserTransport {
    func send(tool: String, args: [String: String]) async throws -> BrowserResponse {
        try await send(tool: tool, args: args, timeout: 15)
    }
}
