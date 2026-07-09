import Foundation

/// Static configuration for the localhost bridge the Chrome extension connects to.
/// A FIXED candidate-port list (not an OS-assigned free port) because an external,
/// file-sandboxed extension can't discover an ephemeral port — it probes these in
/// order. The shared `token` authenticates the extension's `hello` frame.
struct BrowserBridgeConfig: Sendable, Equatable {
    let portCandidates: [UInt16]
    let token: String

    /// Bumped when the wire protocol changes; the extension sends it in `hello`.
    static let protocolVersion = 1
    /// The pinned extension id (from the manifest `key`); the bridge accepts only
    /// `Origin: chrome-extension://<expectedExtensionID>`. Set once the key is minted.
    static let expectedExtensionID: String? = nil

    /// A fresh per-launch secret, same shape as the llama-server key.
    static func makeToken() -> String {
        "suniye-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func standard(token: String = makeToken()) -> BrowserBridgeConfig {
        BrowserBridgeConfig(portCandidates: [7225, 7226, 7227], token: token)
    }
}
