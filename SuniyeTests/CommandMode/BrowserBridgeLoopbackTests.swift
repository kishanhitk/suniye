import Foundation
import Network
import XCTest
@testable import Suniye

/// Integration tests for the REAL `BrowserBridge` over a real loopback WebSocket,
/// using an in-process client that plays the extension. Covers the security
/// contract (token auth, forged-response rejection, handshake expiry,
/// last-authed-wins) and the request/response lifecycle (correlation, timeout,
/// disconnect, keepalive) — fully autonomous, no Chrome involved.
final class BrowserBridgeLoopbackTests: XCTestCase {
    private var bridge: BrowserBridge!
    private var clients: [BridgeTestClient] = []

    override func tearDown() async throws {
        for client in clients { client.cancel() }
        clients = []
        await bridge?.stop()
        bridge = nil
    }

    private func makeBridge(token: String = "tok",
                            keepalive: TimeInterval = 0,
                            handshakeTimeout: TimeInterval = 5) async throws -> UInt16 {
        var config = BrowserBridgeConfig(portCandidates: [0], token: token)
        config.keepaliveInterval = keepalive
        config.handshakeTimeout = handshakeTimeout
        bridge = BrowserBridge(config: config)
        try await bridge.start()
        let port = await bridge.port
        XCTAssertNotNil(port)
        return port ?? 0
    }

    @discardableResult
    private func connectClient(port: UInt16, hello token: String? = nil) async -> BridgeTestClient {
        let client = BridgeTestClient(port: port)
        clients.append(client)
        client.start()
        if let token {
            client.send(["type": "hello", "protocol": 1, "token": token])
        }
        return client
    }

    private func waitUntil(_ timeout: TimeInterval = 3, _ condition: @escaping () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return await condition()
    }

    // MARK: - Handshake + request/response

    func testHandshakeThenRequestResponseRoundTrip() async throws {
        let port = try await makeBridge()
        let client = await connectClient(port: port, hello: "tok")

        let welcomed = await client.waitForMessage(3) { $0["type"] as? String == "welcome" }
        XCTAssertNotNil(welcomed, "valid token → welcome")
        let connected = await waitUntil { await self.bridge.isConnected }
        XCTAssertTrue(connected)

        let sendTask = Task { try await self.bridge.send(tool: "echo", args: ["q": "1"], timeout: 3) }
        let request = await client.waitForMessage(3) { $0["tool"] as? String == "echo" }
        let id = try XCTUnwrap(request?["id"] as? String)
        XCTAssertEqual((request?["args"] as? [String: Any])?["q"] as? String, "1")

        client.send(["id": id, "ok": true, "result": ["text": "hi", "count": 2, "flag": true]])
        let response = try await sendTask.value
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.result["text"], "hi")
        XCTAssertEqual(response.result["count"], "2")
        XCTAssertEqual(response.result["flag"], "true")
    }

    func testBadTokenIsRejectedAndClosed() async throws {
        let port = try await makeBridge()
        let client = await connectClient(port: port, hello: "WRONG")
        let closed = await waitUntil { client.isClosed }
        XCTAssertTrue(closed, "bad token → connection closed")
        let connected = await bridge.isConnected
        XCTAssertFalse(connected)
    }

    // MARK: - Security: forged responses from other local processes

    func testForgedResponseFromUnauthenticatedConnectionIsIgnored() async throws {
        let port = try await makeBridge()
        let real = await connectClient(port: port, hello: "tok")
        _ = await real.waitForMessage(3) { $0["type"] as? String == "welcome" }

        let resolved = Resolved()
        let sendTask = Task {
            let response = try await self.bridge.send(tool: "secret", args: [:], timeout: 5)
            resolved.set()
            return response
        }
        let request = await real.waitForMessage(3) { $0["tool"] as? String == "secret" }
        let id = try XCTUnwrap(request?["id"] as? String)

        // A second local process (no hello) tries to forge the response.
        let attacker = await connectClient(port: port)
        try? await Task.sleep(nanoseconds: 200_000_000) // let it reach .ready
        attacker.send(["id": id, "ok": true, "result": ["text": "FORGED"]])

        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertFalse(resolved.value, "a forged response must not resolve the request")
        let attackerClosed = await waitUntil { attacker.isClosed }
        XCTAssertTrue(attackerClosed, "the forging connection must be closed")

        // The real extension then answers — and that's what wins.
        real.send(["id": id, "ok": true, "result": ["text": "REAL"]])
        let response = try await sendTask.value
        XCTAssertEqual(response.result["text"], "REAL")
    }

    func testSilentConnectionIsClosedAfterHandshakeTimeout() async throws {
        let port = try await makeBridge(handshakeTimeout: 0.3)
        let silent = await connectClient(port: port) // never says hello
        let closed = await waitUntil(2) { silent.isClosed }
        XCTAssertTrue(closed, "no hello within the window → closed")
    }

    func testLastAuthenticatedConnectionWins() async throws {
        let port = try await makeBridge()
        let first = await connectClient(port: port, hello: "tok")
        _ = await first.waitForMessage(3) { $0["type"] as? String == "welcome" }

        let second = await connectClient(port: port, hello: "tok")
        _ = await second.waitForMessage(3) { $0["type"] as? String == "welcome" }

        let firstClosed = await waitUntil { first.isClosed }
        XCTAssertTrue(firstClosed, "the replaced connection is closed")
        let connected = await waitUntil { await self.bridge.isConnected }
        XCTAssertTrue(connected, "replacement must not read as a disconnect")

        // Requests now flow to the new connection.
        let sendTask = Task { try await self.bridge.send(tool: "ping2", args: [:], timeout: 3) }
        let request = await second.waitForMessage(3) { $0["tool"] as? String == "ping2" }
        let id = try XCTUnwrap(request?["id"] as? String)
        second.send(["id": id, "ok": true, "result": [:]])
        _ = try await sendTask.value
    }

    // MARK: - Timeouts, disconnects, keepalive

    func testRequestTimesOutAndLateReplyIsIgnored() async throws {
        let port = try await makeBridge()
        let client = await connectClient(port: port, hello: "tok")
        _ = await client.waitForMessage(3) { $0["type"] as? String == "welcome" }

        do {
            _ = try await bridge.send(tool: "slow", args: [:], timeout: 0.2)
            XCTFail("expected timeout")
        } catch {
            XCTAssertEqual(error as? BrowserBridgeError, .timedOut)
        }
        // A reply arriving after the timeout must be silently ignored.
        if let request = await client.waitForMessage(1, { $0["tool"] as? String == "slow" }),
           let id = request["id"] as? String {
            client.send(["id": id, "ok": true, "result": [:]])
        }
        try? await Task.sleep(nanoseconds: 300_000_000) // no crash / no misdelivery
    }

    func testDisconnectFailsPendingRequests() async throws {
        let port = try await makeBridge()
        let client = await connectClient(port: port, hello: "tok")
        _ = await client.waitForMessage(3) { $0["type"] as? String == "welcome" }

        let sendTask = Task { try await self.bridge.send(tool: "never", args: [:], timeout: 5) }
        _ = await client.waitForMessage(3) { $0["tool"] as? String == "never" }
        client.cancel()

        do {
            _ = try await sendTask.value
            XCTFail("expected notConnected")
        } catch {
            XCTAssertEqual(error as? BrowserBridgeError, .notConnected)
        }
        let disconnected = await waitUntil { await !self.bridge.isConnected }
        XCTAssertTrue(disconnected)
    }

    func testKeepalivePingIsSent() async throws {
        let port = try await makeBridge(keepalive: 0.2)
        let client = await connectClient(port: port, hello: "tok")
        _ = await client.waitForMessage(3) { $0["type"] as? String == "welcome" }
        let ping = await client.waitForMessage(2) { $0["type"] as? String == "ping" }
        XCTAssertNotNil(ping, "the bridge pings to keep the MV3 service worker alive")
    }

    func testStartSkipsOccupiedCandidatePort() async throws {
        let port = try await makeBridge() // occupies an OS-assigned port
        var config = BrowserBridgeConfig(portCandidates: [port, 0], token: "other")
        config.keepaliveInterval = 0
        let second = BrowserBridge(config: config)
        defer { Task { await second.stop() } }
        try await second.start()
        let secondPort = await second.port
        XCTAssertNotNil(secondPort)
        XCTAssertNotEqual(secondPort, port, "occupied candidate must be skipped, not silently claimed")
        await second.stop()
    }
}

// MARK: - In-process WebSocket client (plays the extension)

private final class Resolved: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func set() { lock.lock(); flag = true; lock.unlock() }
}

private final class BridgeTestClient: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "test.ws.client")
    private let lock = NSLock()
    private var messages: [[String: Any]] = []
    private var closed = false

    init(port: UInt16) {
        let params = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        let ws = NWProtocolWebSocket.Options()
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        connection = NWConnection(to: .url(URL(string: "ws://127.0.0.1:\(port)")!), using: params)
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.markClosed()
            default: break
            }
        }
        connection.start(queue: queue)
        receiveLoop()
    }

    func cancel() { connection.cancel() }

    func send(_ json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        let context = NWConnection.ContentContext(
            identifier: "textMessage",
            metadata: [NWProtocolWebSocket.Metadata(opcode: .text)]
        )
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }

    var isClosed: Bool { lock.lock(); defer { lock.unlock() }; return closed }

    func waitForMessage(_ timeout: TimeInterval = 3, _ predicate: @escaping ([String: Any]) -> Bool) async -> [String: Any]? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let match = firstMessage(where: predicate) { return match }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return firstMessage(where: predicate)
    }

    private func firstMessage(where predicate: ([String: Any]) -> Bool) -> [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        return messages.first(where: predicate)
    }

    private func markClosed() {
        lock.lock(); closed = true; lock.unlock()
    }

    private func receiveLoop() {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.lock.lock(); self.messages.append(obj); self.lock.unlock()
            }
            if error == nil {
                self.receiveLoop()
            } else {
                self.markClosed()
            }
        }
    }
}
