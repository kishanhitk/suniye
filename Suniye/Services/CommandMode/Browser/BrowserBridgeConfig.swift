import Foundation

/// Static configuration for the localhost bridge the Chrome extension connects to.
/// A FIXED candidate-port list (not an OS-assigned free port) because an external,
/// file-sandboxed extension can't discover an ephemeral port — it reads the port
/// from its `pairing.json`. The shared `token` authenticates the extension's
/// `hello` frame; it is the WHOLE authentication (NWProtocolWebSocket exposes no
/// server-side handshake headers, so an Origin check is not possible).
struct BrowserBridgeConfig: Sendable, Equatable {
    let portCandidates: [UInt16]
    let token: String
    /// JSON `{"type":"ping"}` cadence — WebSocket activity keeps the extension's
    /// MV3 service worker alive (Chrome evicts idle workers after ~30s). 0 = off.
    var keepaliveInterval: TimeInterval = 20
    /// Connections that don't present a valid `hello` within this window are closed.
    var handshakeTimeout: TimeInterval = 5

    /// Bumped when the wire protocol changes; sent back in `welcome`.
    static let protocolVersion = 1

    /// A fresh per-launch secret, same shape as the llama-server key.
    static func makeToken() -> String {
        "suniye-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func standard(token: String = makeToken()) -> BrowserBridgeConfig {
        BrowserBridgeConfig(portCandidates: [7225, 7226, 7227], token: token)
    }
}
