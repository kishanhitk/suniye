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

private func signedIn() throws -> KeychainChatGPTCredentialStore {
    let store = KeychainChatGPTCredentialStore(item: MemorySecretItem())
    try store.save(ChatGPTCredentials(
        clientID: "oaiapp_1",
        subject: "user-1",
        email: "user@example.com",
        idToken: "saved.id.token",
        tokens: .init(accessToken: "access-1", refreshToken: "refresh-1", scopes: ["chatgpt.tokens.use.direct"], expiresAt: fixedNow.addingTimeInterval(3_600))
    ))
    return store
}

private func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0 ..< 400 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
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

final class ChatGPTSignInFlowTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "ChatGPTSignInFlowTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        ConcurrentStubURLProtocol.handler = nil
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func connection(_ store: KeychainChatGPTCredentialStore, _ openAI: FakeOpenAI, openURL: @escaping @Sendable (URL) -> Void = { _ in }, signInTimeout: Double = 5) -> ChatGPTConnection {
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
        let store = KeychainChatGPTCredentialStore(item: MemorySecretItem())
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

    func testASignInWithoutPlanUseOrWithAReplayedOrForgedTokenSavesNothing() async throws {
        let signer = try TokenSigner()
        let openAI = FakeOpenAI(keys: [signer.published])
        let store = KeychainChatGPTCredentialStore(item: MemorySecretItem())
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

        gate = openAI.hold(ChatGPTOAuth.tokenURL)
        signIn = Task { await connection.connect() }
        _ = await eventually { openAI.sent(to: ChatGPTOAuth.tokenURL).count == 3 }
        let forger = try TokenSigner(kid: signer.published.kid)
        idToken = try forger.token(forger.claims(nonce: nonce(in: opened)))
        openAI.answer(ChatGPTOAuth.tokenURL, (200, FakeOpenAI.tokens(idToken: idToken)))
        gate.signal()
        let forged = await signIn.value

        XCTAssertEqual(noPlan, .noPlanPermission)
        XCTAssertEqual(openAI.sent(to: FakeOpenAI.revocationURL).compactMap { $0.form["token"] }, ["refresh-no-plan"])
        XCTAssertEqual(replayed, .failed)
        XCTAssertEqual(forged, .failed, "a token signed by a key that OpenAI did not publish")
        XCTAssertNil(store.load())
    }
}

@MainActor
final class ChatGPTDisconnectFlowTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "ChatGPTDisconnectFlowTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        ConcurrentStubURLProtocol.handler = nil
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func setup(_ openAI: FakeOpenAI, _ store: KeychainChatGPTCredentialStore) -> (ChatGPTSummarySetup, MeetingCoordinator) {
        let connection = ChatGPTConnection(store: store, session: openAI.session, defaults: defaults, openURL: { _ in }, now: { fixedNow }, revocationRetryDelay: .zero)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let meetings = makeTestMeetingCoordinator(engine: StubTranscriptionService(), root: root, defaults: defaults)
        let setup = ChatGPTSummarySetup(connection: connection, client: ChatGPTPlanClient(connection: connection, session: openAI.session), meetings: meetings, analytics: SpyAnalytics())
        return (setup, meetings)
    }

    func testDisconnectPutsTheSummaryModelBackOnTheMac() async throws {
        let openAI = FakeOpenAI()
        openAI.answer(FakeOpenAI.revocationURL, (503, ""))
        let store = try signedIn()
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
