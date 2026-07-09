import Foundation
import Network

/// Localhost WebSocket server the Suniye Chrome extension connects to. The APP is
/// the server but INITIATES tool requests (`{id, tool, args}`); the extension
/// replies (`{id, ok, result|error}`). Correlated by `id` via a pending-continuation
/// map. Loopback-only bind + a per-launch token in the extension's `hello` frame.
///
/// Security model (localhost is reachable by any local process):
///  - loopback-only bind, token required in the first (`hello`) frame,
///  - ONLY the authenticated connection may deliver responses — frames from any
///    other socket are dropped and the socket closed (no forged tool results),
///  - unauthenticated connections are closed after `config.handshakeTimeout`,
///  - a second valid `hello` replaces the current connection (last-authed-wins,
///    which is how the extension recovers from service-worker restarts).
///  (NWProtocolWebSocket exposes no server-side handshake headers, so an Origin
///  check is not possible here; the token is the authentication.)
///
/// Reliability: the app sends a JSON `{"type":"ping"}` every `keepaliveInterval`
/// — WebSocket activity is what keeps the extension's MV3 service worker alive
/// (Chrome evicts idle workers after ~30s, which showed up as connect/disconnect
/// churn before this existed).
actor BrowserBridge: BrowserTransport {
    private let config: BrowserBridgeConfig
    private let onStateChange: (@Sendable (Bool) -> Void)?
    private let queue = DispatchQueue(label: "dev.suniye.browserbridge")

    private var listener: NWListener?
    private var connection: NWConnection?
    private var handshakeComplete = false
    private var boundPort: UInt16?
    private var pending: [String: CheckedContinuation<BrowserResponse, Error>] = [:]
    private var timeouts: [String: Task<Void, Never>] = [:]
    /// Pre-auth deadline per connection: no valid `hello` in time → closed.
    private var authDeadlines: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var keepalive: Task<Void, Never>?

    init(config: BrowserBridgeConfig, onStateChange: (@Sendable (Bool) -> Void)? = nil) {
        self.config = config
        self.onStateChange = onStateChange
    }

    var isConnected: Bool { connection != nil && handshakeComplete }
    var port: UInt16? { boundPort }
    var pairingToken: String { config.token }

    // MARK: - Lifecycle

    /// Binds the first available candidate port and returns only once the listener
    /// is actually READY — NWListener reports bind failures asynchronously, so
    /// returning after `start()` alone could claim a port another process owns.
    func start() async throws {
        guard listener == nil else { return }
        var lastError: Error?
        for candidate in config.portCandidates {
            do {
                let candidateListener = try makeListener(port: candidate)
                candidateListener.newConnectionHandler = { [weak self] conn in
                    Task { await self?.accept(conn) }
                }
                let port = try await Self.startAndAwaitReady(candidateListener, on: queue)
                candidateListener.stateUpdateHandler = { state in
                    if case let .failed(error) = state {
                        AppLogger.shared.log(.warning, "browser bridge listener failed: \(error)")
                    }
                }
                listener = candidateListener
                boundPort = port
                AppLogger.shared.log(.info, "browser bridge listening on 127.0.0.1:\(port)")
                return
            } catch {
                lastError = error
            }
        }
        AppLogger.shared.log(.warning, "browser bridge could not bind any port \(config.portCandidates)")
        throw lastError ?? BrowserBridgeError.bindFailed
    }

    func stop() {
        keepalive?.cancel(); keepalive = nil
        for (_, task) in authDeadlines { task.cancel() }
        authDeadlines.removeAll()
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
            throw BrowserBridgeError.bindFailed
        }
        return try NWListener(using: params, on: nwPort)
    }

    /// Starts the listener and resolves with the bound port on `.ready`, or throws
    /// on `.failed`/`.cancelled`/a 5s guard. Port 0 (tests) resolves to the
    /// OS-assigned port. Nonisolated: pure state-machine bridging, no actor state.
    private static func startAndAwaitReady(_ listener: NWListener, on queue: DispatchQueue) async throws -> UInt16 {
        final class Once: @unchecked Sendable {
            private let lock = NSLock()
            private var done = false
            func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
        }
        let once = Once()
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                case let .failed(error):
                    if once.claim() { continuation.resume(throwing: error) }
                    listener.cancel()
                case .cancelled:
                    if once.claim() { continuation.resume(throwing: BrowserBridgeError.bindFailed) }
                default:
                    break
                }
            }
            queue.asyncAfter(deadline: .now() + 5) {
                if once.claim() {
                    listener.cancel()
                    continuation.resume(throwing: BrowserBridgeError.bindFailed)
                }
            }
            listener.start(queue: queue)
        }
    }

    // MARK: - Connection handling

    private func accept(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: Task { await self?.connectionReady(conn) }
            case .failed, .cancelled: Task { await self?.connectionClosed(conn) }
            default: break
            }
        }
        conn.start(queue: queue)
    }

    private func connectionReady(_ conn: NWConnection) {
        receive(on: conn)
        // Close connections that never authenticate.
        let key = ObjectIdentifier(conn)
        authDeadlines[key] = Task { [timeout = config.handshakeTimeout] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
            self.expireUnauthenticated(conn)
        }
    }

    private func expireUnauthenticated(_ conn: NWConnection) {
        guard authDeadlines.removeValue(forKey: ObjectIdentifier(conn)) != nil else { return }
        if connection !== conn {
            AppLogger.shared.log(.info, "browser bridge closed a connection that never authenticated")
            conn.cancel()
        }
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
        authDeadlines.removeValue(forKey: ObjectIdentifier(conn))?.cancel()
        guard connection === conn else { return }         // replaced/stranger connections: no teardown
        connection = nil
        handshakeComplete = false
        keepalive?.cancel(); keepalive = nil
        failAllPending(BrowserBridgeError.notConnected)
        onStateChange?(false)
    }

    private func handleInbound(_ data: Data, from conn: NWConnection) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if conn !== connection { conn.cancel() }      // garbage from a stranger → drop it
            return
        }

        if obj["type"] as? String == "hello" {
            guard obj["token"] as? String == config.token else {
                AppLogger.shared.log(.warning, "browser bridge rejected connection: bad token")
                conn.cancel()
                return
            }
            authDeadlines.removeValue(forKey: ObjectIdentifier(conn))?.cancel()
            // Reassign BEFORE cancelling the old connection so its close callback
            // fails the `connection === conn` guard and can't flap the state.
            let old = connection
            connection = conn
            handshakeComplete = true
            if let old, old !== conn { old.cancel() }     // last-authenticated-wins
            send(json: ["type": "welcome", "protocol": BrowserBridgeConfig.protocolVersion], on: conn)
            AppLogger.shared.log(.info, "browser bridge: extension connected")
            startKeepalive()
            onStateChange?(true)
            return
        }

        // SECURITY: beyond `hello`, only the authenticated connection may speak.
        // Anything else could be a local process trying to forge tool responses.
        guard conn === connection, handshakeComplete else {
            AppLogger.shared.log(.warning, "browser bridge dropped a message from an unauthenticated connection")
            conn.cancel()
            return
        }

        if let type = obj["type"] as? String, type == "ping" || type == "pong" { return }

        guard let id = obj["id"] as? String, pending[id] != nil else { return }
        var result: [String: String] = [:]
        if let raw = obj["result"] as? [String: Any] {
            for (key, value) in raw { result[key] = Self.stringify(value) }
        }
        let error = obj["error"] as? [String: Any]
        resolvePending(id, BrowserResponse(
            ok: obj["ok"] as? Bool ?? false, result: result,
            errorCode: error?["code"] as? String, errorMessage: error?["message"] as? String
        ))
    }

    // MARK: - Keepalive (keeps the MV3 service worker alive between commands)

    private func startKeepalive() {
        keepalive?.cancel()
        guard config.keepaliveInterval > 0 else { return }
        keepalive = Task { [interval = config.keepaliveInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                self.sendKeepalivePing()
            }
        }
    }

    private func sendKeepalivePing() {
        guard let conn = connection, handshakeComplete else { return }
        send(json: ["type": "ping", "t": Int(Date().timeIntervalSince1970 * 1000)], on: conn)
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
                if let error { Task { await self?.failPending(id, BrowserBridgeError.badResponse("send failed: \(error)")) } }
            })
            timeouts[id] = Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                self.failPending(id, BrowserBridgeError.timedOut)
            }
        }
    }

    private func resolvePending(_ id: String, _ response: BrowserResponse) {
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(returning: response)
    }

    private func failPending(_ id: String, _ error: Error) {
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func failAllPending(_ error: Error) {
        for (_, task) in timeouts { task.cancel() }
        timeouts.removeAll()
        let continuations = pending
        pending.removeAll()
        for (_, continuation) in continuations { continuation.resume(throwing: error) }
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
