import Foundation
import Network

/// Localhost WebSocket server the Suniye Chrome extension connects to. The APP is
/// the server but INITIATES tool requests (`{id, tool, args}`); the extension
/// replies (`{id, ok, result|error}`). Correlated by `id` via a pending-continuation
/// map. Loopback-only bind + a per-launch token in the extension's `hello` frame.
///
/// Modeled on `LocalGemmaLlamaServer`'s lifecycle (start/stop, per-process token).
/// Uses `NWProtocolWebSocket`, so Network.framework does the RFC-6455 handshake,
/// masking, and fragmentation — we only see complete JSON frames.
actor BrowserBridge: BrowserTransport {
    private let config: BrowserBridgeConfig
    private let onStateChange: (@Sendable (Bool) -> Void)?
    private let queue = DispatchQueue(label: "dev.suniye.browserbridge")

    private var listener: NWListener?
    private var connection: NWConnection?
    private var handshakeComplete = false
    private var boundPort: UInt16?
    private var pending: [String: CheckedContinuation<BrowserResponse, Error>] = [:]

    init(config: BrowserBridgeConfig, onStateChange: (@Sendable (Bool) -> Void)? = nil) {
        self.config = config
        self.onStateChange = onStateChange
    }

    var isConnected: Bool { connection != nil && handshakeComplete }
    var port: UInt16? { boundPort }
    var pairingToken: String { config.token }

    // MARK: - Lifecycle

    func start() throws {
        guard listener == nil else { return }
        var lastError: Error?
        for candidate in config.portCandidates {
            do {
                let listener = try makeListener(port: candidate)
                listener.newConnectionHandler = { [weak self] conn in
                    Task { await self?.accept(conn) }
                }
                listener.stateUpdateHandler = { state in
                    if case let .failed(error) = state {
                        AppLogger.shared.log(.warning, "browser bridge listener failed: \(error)")
                    }
                }
                listener.start(queue: queue)
                self.listener = listener
                self.boundPort = candidate
                AppLogger.shared.log(.info, "browser bridge listening on 127.0.0.1:\(candidate)")
                return
            } catch {
                lastError = error
            }
        }
        AppLogger.shared.log(.warning, "browser bridge could not bind any port \(config.portCandidates)")
        throw lastError ?? BrowserBridgeError.notConnected
    }

    func stop() {
        listener?.cancel(); listener = nil
        connection?.cancel(); connection = nil
        handshakeComplete = false
        boundPort = nil
        failAllPending(BrowserBridgeError.notConnected)
        onStateChange?(false)
    }

    private func makeListener(port candidate: UInt16) throws -> NWListener {
        let params = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        params.requiredInterfaceType = .loopback         // never reachable off-box
        params.allowLocalEndpointReuse = true
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        guard let nwPort = NWEndpoint.Port(rawValue: candidate) else {
            throw BrowserBridgeError.badResponse("invalid port \(candidate)")
        }
        return try NWListener(using: params, on: nwPort)
    }

    // MARK: - Connection handling

    private func accept(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: Task { await self?.receive(on: conn) }
            case .failed, .cancelled: Task { await self?.connectionClosed(conn) }
            default: break
            }
        }
        conn.start(queue: queue)
    }

    private func receive(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            if let data, !data.isEmpty {
                Task { await self?.handleInbound(data, from: conn) }
            }
            if error == nil {
                Task { await self?.receive(on: conn) }    // keep reading this connection
            } else {
                Task { await self?.connectionClosed(conn) }
            }
        }
    }

    private func connectionClosed(_ conn: NWConnection) {
        guard connection === conn else { return }         // ignore replaced/stale connections
        connection = nil
        handshakeComplete = false
        failAllPending(BrowserBridgeError.notConnected)
        onStateChange?(false)
    }

    private func handleInbound(_ data: Data, from conn: NWConnection) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if obj["type"] as? String == "hello" {
            guard obj["token"] as? String == config.token else {
                AppLogger.shared.log(.warning, "browser bridge rejected connection: bad token")
                conn.cancel()
                return
            }
            if let old = connection, old !== conn { old.cancel() }   // last-authenticated-wins
            connection = conn
            handshakeComplete = true
            send(json: ["type": "welcome", "protocol": BrowserBridgeConfig.protocolVersion], on: conn)
            AppLogger.shared.log(.info, "browser bridge: extension connected")
            onStateChange?(true)
            return
        }
        if let type = obj["type"] as? String, type == "ping" || type == "pong" { return }

        guard let id = obj["id"] as? String, let cont = pending.removeValue(forKey: id) else { return }
        var result: [String: String] = [:]
        if let raw = obj["result"] as? [String: Any] {
            for (key, value) in raw { result[key] = Self.stringify(value) }
        }
        let error = obj["error"] as? [String: Any]
        cont.resume(returning: BrowserResponse(
            ok: obj["ok"] as? Bool ?? false, result: result,
            errorCode: error?["code"] as? String, errorMessage: error?["message"] as? String
        ))
    }

    // MARK: - Send

    func send(tool: String, args: [String: String], timeout: TimeInterval) async throws -> BrowserResponse {
        guard let conn = connection, handshakeComplete else { throw BrowserBridgeError.notConnected }
        let id = UUID().uuidString
        let payload: [String: Any] = ["id": id, "tool": tool, "args": args]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            throw BrowserBridgeError.badResponse("encode failed")
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            conn.send(content: data, contentContext: Self.wsTextContext(), isComplete: true,
                      completion: .contentProcessed { [weak self] error in
                if let error { Task { await self?.failPending(id, BrowserBridgeError.badResponse("\(error)")) } }
            })
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                self.failPending(id, BrowserBridgeError.timedOut)
            }
        }
    }

    private func failPending(_ id: String, _ error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func failAllPending(_ error: Error) {
        let conts = pending; pending.removeAll()
        for (_, cont) in conts { cont.resume(throwing: error) }
    }

    private func send(json: [String: Any], on conn: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        conn.send(content: data, contentContext: Self.wsTextContext(), isComplete: true, completion: .contentProcessed { _ in })
    }

    private static func wsTextContext() -> NWConnection.ContentContext {
        NWConnection.ContentContext(identifier: "textMessage", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
    }

    /// JSON scalar → string, disambiguating CFBoolean from numeric NSNumber, and
    /// serializing arrays/objects to a JSON string (so richer tool results survive).
    static func stringify(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        }
        if let data = try? JSONSerialization.data(withJSONObject: value),
           let string = String(data: data, encoding: .utf8) { return string }
        return String(describing: value)
    }
}
