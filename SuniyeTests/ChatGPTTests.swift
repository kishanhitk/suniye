import Network
import Security
import SuniyeAnalytics
import XCTest
@testable import Suniye

// MARK: - Support

/// An RSA key that signs ID tokens as OpenAI does, and its public half as a
/// published key.
private struct TokenSigner {
    let key: SecKey
    let published: ChatGPTIDToken.Key

    init(kid: String = "test-key") throws {
        var error: Unmanaged<CFError>?
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048]
        key = try XCTUnwrap(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(key))
        let der = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, &error)) as Data
        var reader = DERReader(bytes: [UInt8](der))
        _ = try reader.read(tag: 0x30, enter: true)
        let modulus = try reader.read(tag: 0x02)
        let exponent = try reader.read(tag: 0x02)
        published = ChatGPTIDToken.Key(
            kid: kid,
            kty: "RSA",
            n: Data(modulus.drop { $0 == 0 }).base64URLEncodedString(),
            e: Data(exponent).base64URLEncodedString()
        )
    }

    func token(_ claims: [String: Any], algorithm: String = "RS256", kid: String? = nil) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: ["alg": algorithm, "kid": kid ?? published.kid, "typ": "JWT"])
        let payload = try JSONSerialization.data(withJSONObject: claims)
        let signed = "\(header.base64URLEncodedString()).\(payload.base64URLEncodedString())"
        var error: Unmanaged<CFError>?
        let signature = try XCTUnwrap(SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(signed.utf8) as CFData, &error)) as Data
        return "\(signed).\(signature.base64URLEncodedString())"
    }

    func claims(clientID: String = "oaiapp_1", nonce: String, subject: String = "user-1", expiry: Date = Date(timeIntervalSince1970: 2_000_000_000)) -> [String: Any] {
        ["iss": "https://auth.openai.com", "aud": [clientID], "sub": subject, "email": "user@example.com", "nonce": nonce, "exp": expiry.timeIntervalSince1970]
    }
}

private struct DERReader {
    struct Malformed: Error {}

    let bytes: [UInt8]
    var position = 0

    /// The content of the next element. `enter` leaves the position at the
    /// start of the content.
    mutating func read(tag: UInt8, enter: Bool = false) throws -> [UInt8] {
        guard position + 2 <= bytes.count, bytes[position] == tag else { throw Malformed() }
        var length = Int(bytes[position + 1])
        position += 2
        if length & 0x80 != 0 {
            let count = length & 0x7F
            guard position + count <= bytes.count else { throw Malformed() }
            length = bytes[position ..< position + count].reduce(0) { $0 << 8 | Int($1) }
            position += count
        }
        guard position + length <= bytes.count else { throw Malformed() }
        let content = Array(bytes[position ..< position + length])
        if !enter {
            position += length
        }
        return content
    }
}

private final class MemoryCredentialStore: ChatGPTCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var saved: ChatGPTCredentials?

    init(_ credentials: ChatGPTCredentials? = nil) {
        saved = credentials
    }

    func load() -> ChatGPTCredentials? {
        lock.withLock { saved }
    }

    func save(_ credentials: ChatGPTCredentials) throws {
        lock.withLock { saved = credentials }
    }

    func delete() {
        lock.withLock { saved = nil }
    }
}

/// Answers each request on a thread of its own, so a request that a test
/// holds does not block the next one.
private final class ConcurrentStubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var storedHandler: StubURLProtocol.Handler?

    static var handler: StubURLProtocol.Handler? {
        get { lock.withLock { storedHandler } }
        set { lock.withLock { storedHandler = newValue } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let request = request
        DispatchQueue.global().async { [self] in
            do {
                guard let handler = Self.handler else { throw URLError(.unsupportedURL) }
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }
}

/// Answers the requests to auth.openai.com and api.openai.com, and keeps
/// what was sent.
private final class FakeOpenAI: @unchecked Sendable {
    struct Sent {
        let url: URL
        let form: [String: String]
        let json: [String: Any]
        let authorization: String?
    }

    static let jwksURL = URL(string: "https://auth.openai.com/.well-known/jwks.json")!
    static let revocationURL = URL(string: "https://auth.openai.com/api/accounts/oauth/revoke")!

    private let lock = NSLock()
    private var requests: [Sent] = []
    private var answers: [URL: [(status: Int, body: String)]] = [:]
    private var gates: [URL: DispatchSemaphore] = [:]
    var failure: URLError?

    init(keys: [ChatGPTIDToken.Key] = []) {
        let keyList = keys.map { #"{"kid":"\#($0.kid)","kty":"\#($0.kty)","n":"\#($0.n)","e":"\#($0.e)"}"# }.joined(separator: ",")
        answers[ChatGPTOAuth.discoveryURL] = [(200, #"{"jwks_uri":"\#(Self.jwksURL.absoluteString)","revocation_endpoint":"\#(Self.revocationURL.absoluteString)"}"#)]
        answers[Self.jwksURL] = [(200, #"{"keys":[\#(keyList)]}"#)]
        answers[Self.revocationURL] = [(200, "")]
        ConcurrentStubURLProtocol.handler = { [unowned self] request in try self.answer(request) }
    }

    var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConcurrentStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    var sent: [Sent] {
        lock.withLock { requests }
    }

    func sent(to url: URL) -> [Sent] {
        sent.filter { $0.url == url }
    }

    /// The answers to `url`, in order; the last one repeats.
    func answer(_ url: URL, _ list: (status: Int, body: String)...) {
        lock.withLock { answers[url] = list }
    }

    /// The next requests to `url` wait until the returned semaphore gets a
    /// signal.
    func hold(_ url: URL) -> DispatchSemaphore {
        let gate = DispatchSemaphore(value: 0)
        lock.withLock { gates[url] = gate }
        return gate
    }

    static func tokens(access: String = "access-2", refresh: String = "refresh-2", idToken: String? = nil, scope: String = ChatGPTOAuth.scopes) -> String {
        let id = idToken.map { #","id_token":"\#($0)""# } ?? ""
        return #"{"access_token":"\#(access)","refresh_token":"\#(refresh)","token_type":"Bearer","expires_in":3600,"scope":"\#(scope)"\#(id)}"#
    }

    private func answer(_ request: URLRequest) throws -> (URLResponse, Data) {
        let url = try XCTUnwrap(request.url)
        let body = StubURLProtocol.requestBody(of: request) ?? Data()
        var form: [String: String] = [:]
        if request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded" {
            var components = URLComponents()
            components.percentEncodedQuery = String(decoding: body, as: UTF8.self)
            form = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { first, _ in first }
        }
        let json = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        let (gate, error): (DispatchSemaphore?, URLError?) = lock.withLock {
            requests.append(Sent(url: url, form: form, json: json, authorization: request.value(forHTTPHeaderField: "Authorization")))
            return (gates.removeValue(forKey: url), failure)
        }
        gate?.wait()
        if let error {
            throw error
        }
        let next: (status: Int, body: String) = try lock.withLock {
            var list = try XCTUnwrap(answers[url], "no answer for \(url)")
            let first = list[0]
            if list.count > 1 {
                list.removeFirst()
                answers[url] = list
            }
            return first
        }
        return (HTTPURLResponse(url: url, statusCode: next.status, httpVersion: "HTTP/1.1", headerFields: nil)!, Data(next.body.utf8))
    }
}

private let fixedNow = Date(timeIntervalSince1970: 1_900_000_000)

private func credentials(expiresIn seconds: TimeInterval = 3_600, tokens: Bool = true) -> ChatGPTCredentials {
    ChatGPTCredentials(
        clientID: "oaiapp_1",
        subject: "user-1",
        email: "user@example.com",
        idToken: "saved.id.token",
        tokens: tokens ? .init(accessToken: "access-1", refreshToken: "refresh-1", scopes: ["chatgpt.tokens.use.direct"], expiresAt: fixedNow.addingTimeInterval(seconds)) : nil
    )
}

private func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0 ..< 400 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}

// MARK: - OAuth requests

final class ChatGPTOAuthTests: XCTestCase {
    private let attempt = ChatGPTOAuth.Attempt()
    private let registration = ChatGPTOAuth.Registration(clientID: "oaiapp_1", idToken: "saved.id.token", email: "user+work@example.com")

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }) { first, _ in first }
    }

    func testTheFirstSignInRegistersTheAppAndALaterOneNamesTheSavedAccount() {
        let redirect = ChatGPTOAuth.redirectURI(port: 1455)
        let first = ChatGPTOAuth.authorizeURL(attempt: attempt, redirectURI: redirect, hostID: "urn:uuid:host", registration: nil)
        let again = ChatGPTOAuth.authorizeURL(attempt: attempt, redirectURI: redirect, hostID: "urn:uuid:host", registration: registration)

        XCTAssertEqual(first.host, "auth.openai.com")
        XCTAssertEqual(first.path, "/api/accounts/authorize")
        let firstQuery = query(first)
        XCTAssertEqual(firstQuery["client_id"], "dynamic_agent_client")
        XCTAssertEqual(firstQuery["agent_name_hint"], "Suniye")
        XCTAssertEqual(firstQuery["ext_agent_host_id"], "urn:uuid:host")
        XCTAssertEqual(firstQuery["redirect_uri"], "http://127.0.0.1:1455/auth/callback")
        XCTAssertEqual(firstQuery["scope"], "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct")
        XCTAssertEqual(firstQuery["resource"], "https://api.openai.com/v1")
        XCTAssertEqual(firstQuery["response_type"], "code")
        XCTAssertEqual(firstQuery["state"], attempt.state)
        XCTAssertEqual(firstQuery["nonce"], attempt.nonce)
        XCTAssertEqual(firstQuery["code_challenge_method"], "S256")
        XCTAssertEqual(firstQuery["code_challenge"], attempt.challenge)
        XCTAssertNil(firstQuery["id_token_hint"])

        let againQuery = query(again)
        XCTAssertEqual(againQuery["client_id"], "oaiapp_1")
        XCTAssertNil(againQuery["agent_name_hint"])
        XCTAssertEqual(againQuery["id_token_hint"], "saved.id.token")
        XCTAssertEqual(againQuery["login_hint"], "user+work@example.com", "a plus sign is not read as a space")
        XCTAssertNotEqual(ChatGPTOAuth.Attempt().state, attempt.state)
    }

    func testOnlyTheCallbackOfThisAttemptEndsTheWait() {
        let state = attempt.state
        func callback(_ target: String, _ registration: ChatGPTOAuth.Registration? = nil) -> ChatGPTOAuth.Callback? {
            ChatGPTOAuth.callback(target: target, attempt: attempt, registration: registration)
        }

        XCTAssertEqual(callback("/auth/callback?code=abc&state=\(state)&client_id=oaiapp_9&scope=openid"), .authorized(code: "abc", clientID: "oaiapp_9"))
        XCTAssertNil(callback("/auth/callback?code=abc&state=other&client_id=oaiapp_9"), "the tab of an earlier attempt")
        XCTAssertNil(callback("/favicon.ico"))
        XCTAssertNil(callback("/callback?code=abc&state=\(state)&client_id=oaiapp_9"))
        XCTAssertEqual(callback("/auth/callback?error=access_denied&state=\(state)"), .denied)
        XCTAssertEqual(callback("/auth/callback?error=server_error&state=\(state)"), .failed)
        XCTAssertEqual(callback("/auth/callback?code=abc&state=\(state)"), .failed, "a first sign-in needs the issued client ID")
        XCTAssertEqual(callback("/auth/callback?code=abc&state=\(state)&client_id=dynamic_agent_client"), .failed)

        XCTAssertEqual(callback("/auth/callback?code=abc&state=\(state)", registration), .authorized(code: "abc", clientID: "oaiapp_1"))
        XCTAssertEqual(callback("/auth/callback?code=abc&state=\(state)&client_id=oaiapp_1", registration), .authorized(code: "abc", clientID: "oaiapp_1"))
        XCTAssertEqual(callback("/auth/callback?code=abc&state=\(state)&client_id=oaiapp_2", registration), .failed, "another client than the saved one")
    }

    func testThePlanScopeMustBeGranted() throws {
        let granted = try JSONDecoder().decode(ChatGPTOAuth.TokenResponse.self, from: Data(FakeOpenAI.tokens().utf8))
        let identityOnly = try JSONDecoder().decode(ChatGPTOAuth.TokenResponse.self, from: Data(FakeOpenAI.tokens(scope: "openid profile email offline_access").utf8))

        XCTAssertTrue(granted.allowsPlanUse)
        XCTAssertFalse(identityOnly.allowsPlanUse)
        XCTAssertEqual(ChatGPTOAuth.errorCode(in: Data(#"{"error":"invalid_grant"}"#.utf8)), "invalid_grant")
        XCTAssertEqual(ChatGPTOAuth.errorCode(in: Data(#"{"error":{"code":"refresh_token_reused","message":"x"}}"#.utf8)), "refresh_token_reused")
        XCTAssertNil(ChatGPTOAuth.errorCode(in: Data("<html>".utf8)))
        XCTAssertEqual(ChatGPTOAuth.loggable("invalid_grant"), "invalid_grant")
        XCTAssertEqual(ChatGPTOAuth.loggable("We agreed to ship on Friday"), "other", "text from a service never reaches the log")
        XCTAssertEqual(ChatGPTOAuth.loggable(nil), "none")
    }
}

// MARK: - ID token

final class ChatGPTIDTokenTests: XCTestCase {
    func testOnlyATokenThatOpenAISignedForThisSignInPasses() throws {
        let signer = try TokenSigner()
        let other = try TokenSigner()
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        func validate(_ token: String, keys: [ChatGPTIDToken.Key]? = nil) -> Result<ChatGPTIDToken.Claims, ChatGPTIDToken.Failure> {
            Result { try ChatGPTIDToken.validate(token, keys: keys ?? [signer.published], clientID: "oaiapp_1", nonce: "nonce-1", now: now) }
                .mapError { $0 as? ChatGPTIDToken.Failure ?? .malformed }
        }
        var claims = signer.claims(nonce: "nonce-1")

        XCTAssertEqual(try validate(signer.token(claims)).get(), ChatGPTIDToken.Claims(subject: "user-1", email: "user@example.com"))
        claims["aud"] = "oaiapp_1"
        XCTAssertEqual(try validate(signer.token(claims)).get().subject, "user-1", "one audience can be a string")

        let forged = try other.token(signer.claims(nonce: "nonce-1"), kid: signer.published.kid)
        XCTAssertEqual(validate(forged), .failure(.signature))
        XCTAssertEqual(validate(try signer.token(claims, algorithm: "none")), .failure(.algorithm))
        XCTAssertEqual(validate(try signer.token(claims, algorithm: "HS256")), .failure(.algorithm))
        XCTAssertEqual(validate(try signer.token(claims), keys: [other.published].map { ChatGPTIDToken.Key(kid: "other", kty: $0.kty, n: $0.n, e: $0.e) }), .failure(.unknownKey))
        XCTAssertEqual(validate("not.a.token"), .failure(.malformed))

        var wrong = signer.claims(nonce: "nonce-1")
        wrong["iss"] = "https://auth.example.com"
        XCTAssertEqual(validate(try signer.token(wrong)), .failure(.issuer))
        XCTAssertEqual(validate(try signer.token(signer.claims(clientID: "oaiapp_2", nonce: "nonce-1"))), .failure(.audience))
        XCTAssertEqual(validate(try signer.token(signer.claims(nonce: "nonce-2"))), .failure(.nonce))
        XCTAssertEqual(validate(try signer.token(signer.claims(nonce: "nonce-1", expiry: now.addingTimeInterval(-1)))), .failure(.expired))

        let parts = try signer.token(signer.claims(nonce: "nonce-1")).split(separator: ".").map(String.init)
        let changed = try JSONSerialization.data(withJSONObject: signer.claims(nonce: "nonce-1", subject: "user-2")).base64URLEncodedString()
        XCTAssertEqual(validate("\(parts[0]).\(changed).\(parts[2])"), .failure(.signature), "a changed payload")
    }
}

// MARK: - Callback listener

final class ChatGPTLoopbackListenerTests: XCTestCase {
    func testTheBrowserGetsThePageOfItsRequestAndABusyPortGivesAnotherOne() async throws {
        let targets = LockedList()
        let first = try await ChatGPTLoopbackListener.start(preferredPort: 0) { target in
            targets.append(target)
            return target.hasPrefix("/auth/callback") ? .init(status: 200, text: "You can close this tab.") : .notFound
        }
        defer { first.stop() }
        let second = try await ChatGPTLoopbackListener.start(preferredPort: first.port) { _ in .notFound }
        defer { second.stop() }

        let session = URLSession(configuration: .ephemeral)
        let (page, response) = try await session.data(from: URL(string: "http://127.0.0.1:\(first.port)/auth/callback?code=abc&state=s1")!)
        let (_, missing) = try await session.data(from: URL(string: "http://127.0.0.1:\(first.port)/other")!)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: page, as: UTF8.self).contains("You can close this tab."))
        XCTAssertEqual((missing as? HTTPURLResponse)?.statusCode, 404)
        XCTAssertEqual(targets.values, ["/auth/callback?code=abc&state=s1", "/other"])
        XCTAssertNotEqual(first.port, 0)
        XCTAssertNotEqual(second.port, first.port)
    }

    func testARequestThatComesInTwoPiecesIsReadWhole() async throws {
        let listener = try await ChatGPTLoopbackListener.start(preferredPort: 0) { target in
            target == "/auth/callback?code=abc" ? .init(status: 200, text: "Whole.") : .notFound
        }
        defer { listener.stop() }
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: listener.port)!, using: .tcp)
        defer { connection.cancel() }
        connection.start(queue: .global())

        connection.send(content: Data("GET /auth/".utf8), completion: .contentProcessed { _ in })
        try await Task.sleep(for: .milliseconds(100))
        connection.send(content: Data("callback?code=abc HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8), completion: .contentProcessed { _ in })
        let answer: Data = await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { data, _, _, _ in
                continuation.resume(returning: data ?? Data())
            }
        }

        XCTAssertTrue(String(decoding: answer, as: UTF8.self).hasPrefix("HTTP/1.1 200"))
    }
}

private final class LockedList: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [String] = []

    var values: [String] {
        lock.withLock { list }
    }

    func append(_ value: String) {
        lock.withLock { list.append(value) }
    }
}

// MARK: - Connection

final class ChatGPTConnectionTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "ChatGPTConnectionTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        ConcurrentStubURLProtocol.handler = nil
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func connection(_ store: MemoryCredentialStore, _ openAI: FakeOpenAI, openURL: @escaping @Sendable (URL) -> Void = { _ in }, signInTimeout: Double = 5) -> ChatGPTConnection {
        ChatGPTConnection(
            store: store,
            session: openAI.session,
            defaults: defaults,
            openURL: openURL,
            now: { fixedNow },
            signInTimeoutSeconds: signInTimeout,
            revocationRetryDelay: .zero
        )
    }

    func testATokenNearItsEndIsRefreshedOnceForEveryCallerAndSavedWhole() async throws {
        let openAI = FakeOpenAI()
        openAI.answer(ChatGPTOAuth.tokenURL, (200, FakeOpenAI.tokens()))
        let store = MemoryCredentialStore(credentials(expiresIn: 60))
        let connection = connection(store, openAI)
        let gate = openAI.hold(ChatGPTOAuth.tokenURL)

        async let modelList = connection.accessToken()
        async let summary = connection.accessToken()
        _ = await eventually { openAI.sent(to: ChatGPTOAuth.tokenURL).count == 1 }
        try await Task.sleep(for: .milliseconds(30))
        gate.signal()
        let tokens = try await [modelList, summary]

        XCTAssertEqual(tokens, ["access-2", "access-2"])
        let refreshes = openAI.sent(to: ChatGPTOAuth.tokenURL)
        XCTAssertEqual(refreshes.count, 1, "a refresh token works once")
        XCTAssertEqual(refreshes[0].form, ["grant_type": "refresh_token", "client_id": "oaiapp_1", "refresh_token": "refresh-1", "resource": "https://api.openai.com/v1"])
        XCTAssertEqual(store.load()?.tokens, .init(accessToken: "access-2", refreshToken: "refresh-2", scopes: ChatGPTOAuth.scopes.split(separator: " ").map(String.init), expiresAt: fixedNow.addingTimeInterval(3_600)))

        let later = try await connection.accessToken()
        let afterALateRefusal = try await connection.accessToken(rejected: "access-1")
        XCTAssertEqual([later, afterALateRefusal], ["access-2", "access-2"])
        XCTAssertEqual(openAI.sent(to: ChatGPTOAuth.tokenURL).count, 1, "a fresh token needs no refresh, also when an older one was refused")

        openAI.answer(ChatGPTOAuth.tokenURL, (200, FakeOpenAI.tokens(access: "access-3", refresh: "refresh-3")))
        let afterARefusal = try await connection.accessToken(rejected: "access-2")
        XCTAssertEqual(afterARefusal, "access-3", "a refused token is replaced")
    }

    func testARefreshTokenThatCannotWorkAgainEndsTheSignInAndKeepsTheRegistration() async {
        let openAI = FakeOpenAI()
        openAI.answer(ChatGPTOAuth.tokenURL, (400, #"{"error":"invalid_grant"}"#))
        let store = MemoryCredentialStore(credentials(expiresIn: -10))
        let connection = connection(store, openAI)

        do {
            _ = try await connection.accessToken()
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? ChatGPTError, .signInEnded)
        }

        let state = await connection.state()
        XCTAssertEqual(state, .signInEnded(email: "user@example.com"))
        XCTAssertEqual(store.load(), credentials(tokens: false))
    }

    func testAFailedConnectionOrAServerErrorKeepsTheTokens() async {
        let openAI = FakeOpenAI()
        openAI.answer(ChatGPTOAuth.tokenURL, (503, "{}"))
        let store = MemoryCredentialStore(credentials(expiresIn: -10))
        let connection = connection(store, openAI)

        var errors: [ChatGPTError?] = []
        do { _ = try await connection.accessToken() } catch { errors.append(error as? ChatGPTError) }
        openAI.failure = URLError(.notConnectedToInternet)
        do { _ = try await connection.accessToken() } catch { errors.append(error as? ChatGPTError) }

        XCTAssertEqual(errors, [.service, .network])
        XCTAssertEqual(store.load(), credentials(expiresIn: -10))
    }

    func testDisconnectDeletesTheSignInAndSaysWhenOpenAIDidNotConfirm() async {
        let openAI = FakeOpenAI()
        let store = MemoryCredentialStore(credentials())
        let confirmed = await connection(store, openAI).disconnect()

        XCTAssertTrue(confirmed)
        XCTAssertNil(store.load())
        XCTAssertEqual(openAI.sent(to: FakeOpenAI.revocationURL).map(\.form), [["token": "refresh-1", "token_type_hint": "refresh_token", "client_id": "oaiapp_1"]])

        let failing = FakeOpenAI()
        failing.answer(FakeOpenAI.revocationURL, (503, ""))
        let other = MemoryCredentialStore(credentials())
        let connection = connection(other, failing)
        let unconfirmed = await connection.disconnect()
        let state = await connection.state()

        XCTAssertFalse(unconfirmed)
        XCTAssertNil(other.load(), "the sign-in goes from this Mac in each case")
        XCTAssertEqual(state, .notConnected)
        XCTAssertEqual(failing.sent(to: FakeOpenAI.revocationURL).count, 2, "one more try")
    }

    func testARefreshThatEndsAfterADisconnectSavesNothing() async {
        let openAI = FakeOpenAI()
        openAI.answer(ChatGPTOAuth.tokenURL, (200, FakeOpenAI.tokens()))
        let store = MemoryCredentialStore(credentials(expiresIn: -10))
        let connection = connection(store, openAI)
        let gate = openAI.hold(ChatGPTOAuth.tokenURL)

        let refresh = Task { try await connection.accessToken() }
        _ = await eventually { openAI.sent(to: ChatGPTOAuth.tokenURL).count == 1 }
        _ = await connection.disconnect()
        gate.signal()
        let result = await refresh.result

        XCTAssertThrowsError(try result.get()) { XCTAssertEqual($0 as? ChatGPTError, .signInEnded) }
        XCTAssertNil(store.load())
        XCTAssertEqual(openAI.sent(to: FakeOpenAI.revocationURL).compactMap { $0.form["token"] }, ["refresh-1", "refresh-2"], "the new sign-in ends too")
    }

    /// Plays the browser: reads the page that the app opens and calls the
    /// callback on 127.0.0.1.
    private func browser(_ answer: @escaping @Sendable (_ redirect: String, _ state: String) -> String?) -> (@Sendable (URL) -> Void, LockedList) {
        let opened = LockedList()
        return ({ url in
            opened.append(url.absoluteString)
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let value = { name in items.first { $0.name == name }?.value ?? "" }
            guard let target = answer(value("redirect_uri"), value("state")), let callback = URL(string: target) else { return }
            Task { _ = try? await URLSession(configuration: .ephemeral).data(from: callback) }
        }, opened)
    }

    private func nonce(in opened: LockedList) -> String {
        let url = opened.values.last.flatMap(URL.init(string:))
        return url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first { $0.name == "nonce" }?.value ?? ""
    }

    func testASignInSavesTheAccountThatTheCheckedIDTokenNames() async throws {
        let signer = try TokenSigner()
        let openAI = FakeOpenAI(keys: [signer.published])
        let store = MemoryCredentialStore()
        let (open, opened) = browser { redirect, state in "\(redirect)?code=code-1&state=\(state)&client_id=oaiapp_1" }
        let connection = connection(store, openAI, openURL: open)
        // The token must hold the nonce of this attempt, so it is made when
        // the code is exchanged.
        let gate = openAI.hold(ChatGPTOAuth.tokenURL)
        let signIn = Task { await connection.connect() }
        _ = await eventually { openAI.sent(to: ChatGPTOAuth.tokenURL).count == 1 }
        let idToken = try signer.token(signer.claims(nonce: nonce(in: opened)))
        openAI.answer(ChatGPTOAuth.tokenURL, (200, FakeOpenAI.tokens(access: "access-1", refresh: "refresh-1", idToken: idToken)))
        gate.signal()
        let outcome = await signIn.value

        XCTAssertEqual(outcome, .connected)
        let exchange = try XCTUnwrap(openAI.sent(to: ChatGPTOAuth.tokenURL).first?.form)
        XCTAssertEqual(exchange["grant_type"], "authorization_code")
        XCTAssertEqual(exchange["client_id"], "oaiapp_1", "the issued client ID, not the one of the registration")
        XCTAssertEqual(exchange["code"], "code-1")
        XCTAssertEqual(exchange["redirect_uri"]?.hasSuffix("/auth/callback"), true)
        XCTAssertNotNil(exchange["code_verifier"])
        let saved = try XCTUnwrap(store.load())
        XCTAssertEqual(saved.clientID, "oaiapp_1")
        XCTAssertEqual(saved.subject, "user-1")
        XCTAssertEqual(saved.idToken, idToken)
        XCTAssertEqual(saved.tokens?.refreshToken, "refresh-1")
        let state = await connection.state()
        XCTAssertEqual(state, .connected(email: "user@example.com"))
        XCTAssertEqual(defaults.string(forKey: ChatGPTConnection.hostIDKey)?.hasPrefix("urn:uuid:"), true)
        XCTAssertTrue(opened.values[0].contains("client_id=dynamic_agent_client"))
    }

    func testASignInWithoutPlanUseOrWithATokenForAnotherAttemptSavesNothing() async throws {
        let signer = try TokenSigner()
        let openAI = FakeOpenAI(keys: [signer.published])
        let store = MemoryCredentialStore()
        let (open, opened) = browser { redirect, state in "\(redirect)?code=code-1&state=\(state)&client_id=oaiapp_1" }
        let connection = connection(store, openAI, openURL: open)

        var gate = openAI.hold(ChatGPTOAuth.tokenURL)
        var signIn = Task { await connection.connect() }
        _ = await eventually { openAI.sent(to: ChatGPTOAuth.tokenURL).count == 1 }
        var idToken = try signer.token(signer.claims(nonce: nonce(in: opened)))
        openAI.answer(ChatGPTOAuth.tokenURL, (200, FakeOpenAI.tokens(refresh: "refresh-no-plan", idToken: idToken, scope: "openid profile email offline_access")))
        gate.signal()
        let noPlan = await signIn.value

        gate = openAI.hold(ChatGPTOAuth.tokenURL)
        signIn = Task { await connection.connect() }
        _ = await eventually { openAI.sent(to: ChatGPTOAuth.tokenURL).count == 2 }
        idToken = try signer.token(signer.claims(nonce: "the-nonce-of-another-attempt"))
        openAI.answer(ChatGPTOAuth.tokenURL, (200, FakeOpenAI.tokens(idToken: idToken)))
        gate.signal()
        let replayed = await signIn.value

        XCTAssertEqual(noPlan, .noPlanPermission)
        XCTAssertEqual(openAI.sent(to: FakeOpenAI.revocationURL).compactMap { $0.form["token"] }, ["refresh-no-plan"])
        XCTAssertEqual(replayed, .failed)
        XCTAssertNil(store.load())
    }

    func testASignInThatTheUserRefusesStopsOrLeavesOpenEndsWithItsCause() async {
        let openAI = FakeOpenAI()
        let store = MemoryCredentialStore()
        let (deny, _) = browser { redirect, state in "\(redirect)?error=access_denied&state=\(state)" }
        let denied = await connection(store, openAI, openURL: deny).connect()

        let (silent, opened) = browser { _, _ in nil }
        let waiting = connection(store, openAI, openURL: silent)
        let signIn = Task { await waiting.connect() }
        _ = await eventually { opened.values.count == 1 }
        signIn.cancel()
        let canceled = await signIn.value
        let timedOut = await connection(store, openAI, openURL: silent, signInTimeout: 0.05).connect()

        XCTAssertEqual(denied, .denied)
        XCTAssertEqual(canceled, .canceled)
        XCTAssertEqual(timedOut, .timedOut)
        XCTAssertTrue(openAI.sent(to: ChatGPTOAuth.tokenURL).isEmpty, "no code is exchanged")
        XCTAssertNil(store.load())
    }
}

// MARK: - Plan client

final class ChatGPTPlanClientTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "ChatGPTPlanClientTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        ConcurrentStubURLProtocol.handler = nil
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func client(_ openAI: FakeOpenAI, store: MemoryCredentialStore = MemoryCredentialStore(credentials())) -> ChatGPTPlanClient {
        let connection = ChatGPTConnection(store: store, session: openAI.session, defaults: defaults, openURL: { _ in }, now: { fixedNow }, revocationRetryDelay: .zero)
        return ChatGPTPlanClient(connection: connection, session: openAI.session)
    }

    private func stream(_ events: String...) -> String {
        events.map { "event: x\ndata: \($0)\n\n" }.joined()
    }

    private func failure(_ client: ChatGPTPlanClient) async -> ChatGPTError? {
        do {
            _ = try await client.respond(model: "gpt-6.1-sol", instructions: "Write.", input: "Text.")
            return nil
        } catch {
            return error as? ChatGPTError
        }
    }

    private let delta = #"{"type":"response.output_text.delta","delta":"Title: Plan"}"#
    private let limit = #"{"type":"response.failed","response":{"status":"failed","error":{"code":"subscription_sharing_usage_limit_exceeded","message":"x"}}}"#

    func testTheAnswerIsTheTextUpToTheCompletedEvent() async throws {
        let openAI = FakeOpenAI()
        openAI.answer(ChatGPTPlanClient.responsesURL, (200, stream(
            #"{"type":"response.created","response":{}}"#,
            delta,
            #"{"type":"response.output_text.delta","delta":"\n## Decisions"}"#,
            #"{"type":"response.completed","response":{"status":"completed"}}"#
        )))

        let text = try await client(openAI).respond(model: "gpt-6.1-sol", instructions: "You write the summary.", input: "<transcript>")

        XCTAssertEqual(text, "Title: Plan\n## Decisions")
        let sent = try XCTUnwrap(openAI.sent(to: ChatGPTPlanClient.responsesURL).first)
        XCTAssertEqual(sent.authorization, "Bearer access-1")
        XCTAssertEqual(Set(sent.json.keys), ["model", "instructions", "input", "store", "stream"], "nothing that the preview refuses")
        XCTAssertEqual(sent.json["model"] as? String, "gpt-6.1-sol")
        XCTAssertEqual(sent.json["instructions"] as? String, "You write the summary.")
        XCTAssertEqual(sent.json["store"] as? Bool, false)
        XCTAssertEqual(sent.json["stream"] as? Bool, true)
        XCTAssertEqual(sent.json["input"] as? [[String: String]], [["role": "user", "content": "<transcript>"]])
    }

    func testAnAnswerThatDoesNotCompleteFailsWithItsCause() async {
        let openAI = FakeOpenAI()
        openAI.answer(ChatGPTOAuth.tokenURL, (200, FakeOpenAI.tokens()))
        let client = client(openAI)
        func answer(_ status: Int = 200, _ body: String) async -> ChatGPTError? {
            openAI.answer(ChatGPTPlanClient.responsesURL, (status, body))
            await client.endPause()
            return await failure(client)
        }

        let incomplete = await answer(200, stream(delta, #"{"type":"response.incomplete","response":{"status":"incomplete"}}"#))
        let cutOff = await answer(200, stream(delta))
        let streamError = await answer(200, stream(delta, #"{"type":"error","code":"server_error","message":"x"}"#))
        let limitInStream = await answer(200, stream(delta, limit))
        let limitBefore = await answer(429, #"{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"x"}}"#)
        let notEligible = await answer(403, #"{"error":{"code":"subscription_sharing_user_not_eligible","message":"x"}}"#)
        let unavailable = await answer(503, #"{"detail":"Direct routing is unavailable."}"#)
        let refusedTwice = await answer(401, #"{"detail":"x"}"#)

        XCTAssertEqual(incomplete, .incomplete)
        XCTAssertEqual(cutOff, .network, "only the completed event is a whole answer")
        XCTAssertEqual(streamError, .service)
        XCTAssertEqual(limitInStream, .planLimit)
        XCTAssertEqual(limitBefore, .planLimit)
        XCTAssertEqual(notEligible, .planNotAllowed)
        XCTAssertEqual(unavailable, .service)
        XCTAssertEqual(refusedTwice, .service)
    }

    func testAfterAPlanLimitNothingIsSentUntilTheUserAsksAgain() async {
        let openAI = FakeOpenAI()
        openAI.answer(ChatGPTPlanClient.responsesURL, (200, stream(delta, limit)))
        let client = client(openAI)

        let first = await failure(client)
        let second = await failure(client)
        let sentWhilePaused = openAI.sent(to: ChatGPTPlanClient.responsesURL).count
        await client.endPause()
        _ = await failure(client)

        XCTAssertEqual([first, second], [.planLimit, .planLimit])
        XCTAssertEqual(sentWhilePaused, 1)
        XCTAssertEqual(openAI.sent(to: ChatGPTPlanClient.responsesURL).count, 2)
    }

    func testARefusedTokenIsRefreshedOnceAndTheRequestGoesAgain() async throws {
        let openAI = FakeOpenAI()
        openAI.answer(ChatGPTOAuth.tokenURL, (200, FakeOpenAI.tokens()))
        openAI.answer(ChatGPTPlanClient.responsesURL, (401, #"{"detail":"x"}"#), (200, stream(delta, #"{"type":"response.completed","response":{}}"#)))

        let text = try await client(openAI).respond(model: "gpt-6.1-sol", instructions: "Write.", input: "Text.")

        XCTAssertEqual(text, "Title: Plan")
        XCTAssertEqual(openAI.sent(to: ChatGPTPlanClient.responsesURL).map(\.authorization), ["Bearer access-1", "Bearer access-2"])
        XCTAssertEqual(openAI.sent(to: ChatGPTOAuth.tokenURL).count, 1)
    }

    func testWithoutASignInNothingIsSent() async {
        let openAI = FakeOpenAI()
        let client = client(openAI, store: MemoryCredentialStore(credentials(tokens: false)))

        let ended = await failure(client)

        XCTAssertEqual(ended, .signInEnded)
        XCTAssertTrue(openAI.sent.isEmpty)
    }

    func testTheModelListKeepsTheModelsForAListInTheServersOrder() async throws {
        let openAI = FakeOpenAI()
        openAI.answer(ChatGPTPlanClient.modelsURL, (200, #"{"models":[{"slug":"gpt-6.1-sol","display_name":"GPT-6.1 Sol","visibility":"list"},{"slug":"internal","display_name":"Internal","visibility":"hide"},{"slug":"gpt-6.1-mini","display_name":"GPT-6.1 mini","visibility":"list"}]}"#))

        let models = try await client(openAI).models()

        XCTAssertEqual(models, [ChatGPTModel(slug: "gpt-6.1-sol", displayName: "GPT-6.1 Sol"), ChatGPTModel(slug: "gpt-6.1-mini", displayName: "GPT-6.1 mini")])
    }

    func testEachChatGPTErrorIsASummaryFailureKind() {
        XCTAssertEqual(
            [ChatGPTError.signInEnded, .planLimit, .planNotAllowed, .network, .timeout, .service, .incomplete].map(MeetingSummaryFailure.init),
            [.signInEnded, .planLimit, .planNotAllowed, .network, .timeout, .serviceError, .truncated]
        )
    }
}

// MARK: - Setup in Settings

@MainActor
final class ChatGPTSummarySetupTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "ChatGPTSummarySetupTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        ConcurrentStubURLProtocol.handler = nil
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func setup(_ openAI: FakeOpenAI, _ store: MemoryCredentialStore) -> (ChatGPTSummarySetup, MeetingCoordinator) {
        let connection = ChatGPTConnection(store: store, session: openAI.session, defaults: defaults, openURL: { _ in }, now: { fixedNow }, revocationRetryDelay: .zero)
        let meetings = makeTestMeetingCoordinator(engine: StubTranscriptionService(), analytics: SpyAnalytics())
        let setup = ChatGPTSummarySetup(connection: connection, client: ChatGPTPlanClient(connection: connection, session: openAI.session), meetings: meetings, analytics: SpyAnalytics())
        return (setup, meetings)
    }

    func testTheSheetShowsTheAccountAndPicksAModelThatTheAccountHas() async {
        let openAI = FakeOpenAI()
        openAI.answer(ChatGPTPlanClient.modelsURL, (200, #"{"models":[{"slug":"gpt-6.1-mini","display_name":"GPT-6.1 mini","visibility":"list"},{"slug":"gpt-6.1-sol","display_name":"GPT-6.1 Sol","visibility":"list"}]}"#))
        let (setup, meetings) = setup(openAI, MemoryCredentialStore(credentials()))
        meetings.updateSettings { $0.chatGPTModel = "a-model-that-went-away" }

        await setup.open()

        XCTAssertEqual(setup.state, .connected(email: "user@example.com"))
        XCTAssertEqual(setup.models.map(\.slug), ["gpt-6.1-mini", "gpt-6.1-sol"])
        XCTAssertEqual(setup.model, "gpt-6.1-sol", "the default model when the account has it")

        openAI.answer(ChatGPTPlanClient.modelsURL, (200, #"{"models":[{"slug":"gpt-6.1-mini","display_name":"GPT-6.1 mini","visibility":"list"}]}"#))
        await setup.open()
        XCTAssertEqual(meetings.settings.chatGPTModel, "gpt-6.1-mini", "else the first one")

        openAI.answer(ChatGPTPlanClient.modelsURL, (503, "{}"))
        await setup.open()
        XCTAssertEqual(setup.models, [])
        XCTAssertEqual(setup.model, "gpt-6.1-mini", "a list that does not load keeps the saved model")
    }

    func testDisconnectPutsTheSummaryModelBackOnTheMac() async {
        let openAI = FakeOpenAI()
        openAI.answer(FakeOpenAI.revocationURL, (503, ""))
        let store = MemoryCredentialStore(credentials())
        let (setup, meetings) = setup(openAI, store)
        setup.useChatGPT()
        XCTAssertEqual(meetings.settings.summaryModel, .chatGPT)

        await setup.disconnect()

        XCTAssertEqual(meetings.settings.summaryModel, .automatic)
        XCTAssertEqual(setup.state, .notConnected)
        XCTAssertNil(store.load())
        XCTAssertEqual(setup.message, "Disconnected on this Mac. To remove the access, open ChatGPT Settings > Security and login > Sign in with ChatGPT.")
    }
}
