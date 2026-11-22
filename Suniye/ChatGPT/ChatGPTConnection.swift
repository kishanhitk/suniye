import Foundation
import SuniyeAnalytics

/// Why a request that needs the user's ChatGPT sign-in or plan failed.
enum ChatGPTError: Error, Equatable {
    /// The user must sign in again.
    case signInEnded
    case planLimit
    /// OpenAI does not let this account use its plan in an app.
    case planNotAllowed
    case network
    case timeout
    case service
    /// The answer stopped before its end.
    case incomplete
}

/// The ChatGPT account of this Mac: the sign-in in the browser, the tokens
/// in the credential store, their refresh, and the disconnect. Nothing reads
/// the store before the first call that needs it.
actor ChatGPTConnection {
    enum State: Equatable, Sendable {
        case notConnected
        case connected(email: String?)
        /// The tokens are gone and the registration stays: the next sign-in
        /// is for the same account.
        case signInEnded(email: String?)
    }

    /// A token that ends sooner than this is refreshed before a request.
    static let refreshMargin: TimeInterval = 300
    static let hostIDKey = "dev.suniye.chatgpt.hostID"
    /// These answers of a refresh say that the refresh token cannot work again.
    static let endedSignInCodes: Set<String> = [
        "invalid_grant", "invalid_refresh_token", "token_expired",
        "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused",
    ]

    private struct Discovery: Decodable {
        let jwksURI: URL
        let revocationEndpoint: URL

        enum CodingKeys: String, CodingKey {
            case jwksURI = "jwks_uri"
            case revocationEndpoint = "revocation_endpoint"
        }
    }

    private let store: ChatGPTCredentialStore
    private let session: URLSession
    private let defaults: UserDefaults
    private let openURL: @Sendable (URL) -> Void
    private let now: @Sendable () -> Date
    private let signInTimeoutSeconds: Double
    private let revocationRetryDelay: Duration

    private var loaded = false
    private var credentials: ChatGPTCredentials?
    /// Goes up at each disconnect: a refresh that began before does not
    /// save its tokens.
    private var generation = 0
    /// The one refresh in progress. Each caller that needs a new token
    /// waits for it: a refresh token works once.
    private var refreshTask: Task<String, Error>?
    private var discovery: Discovery?

    init(
        store: ChatGPTCredentialStore,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        openURL: @escaping @Sendable (URL) -> Void,
        now: @escaping @Sendable () -> Date = Date.init,
        signInTimeoutSeconds: Double = 300,
        revocationRetryDelay: Duration = .seconds(2)
    ) {
        self.store = store
        self.session = session
        self.defaults = defaults
        self.openURL = openURL
        self.now = now
        self.signInTimeoutSeconds = signInTimeoutSeconds
        self.revocationRetryDelay = revocationRetryDelay
    }

    func state() -> State {
        guard let credentials = current() else { return .notConnected }
        return credentials.tokens == nil ? .signInEnded(email: credentials.email) : .connected(email: credentials.email)
    }

    // MARK: - Sign-in

    /// Opens the browser for the sign-in and waits for its return. Cancel
    /// the task to stop the wait.
    func connect() async -> ChatGPTSignInOutcome {
        let saved = current()
        let registration = saved?.registration
        let attempt = ChatGPTOAuth.Attempt()
        let (callbacks, continuation) = AsyncStream<ChatGPTOAuth.Callback>.makeStream()
        let listener: ChatGPTLoopbackListener
        do {
            listener = try await ChatGPTLoopbackListener.start(preferredPort: ChatGPTOAuth.preferredCallbackPort) { target in
                guard let callback = ChatGPTOAuth.callback(target: target, attempt: attempt, registration: registration) else {
                    return .notFound
                }
                continuation.yield(callback)
                if case .authorized = callback {
                    return ChatGPTLoopbackListener.Page(status: 200, text: "You can close this tab and go back to Suniye.")
                }
                return ChatGPTLoopbackListener.Page(status: 200, text: "ChatGPT sign-in did not finish. Go back to Suniye.")
            }
        } catch {
            AppLogger.shared.log(.error, "chatgpt sign-in: no callback listener")
            return .failed
        }
        defer { listener.stop() }
        let redirectURI = ChatGPTOAuth.redirectURI(port: listener.port)
        openURL(ChatGPTOAuth.authorizeURL(attempt: attempt, redirectURI: redirectURI, hostID: hostID(), registration: registration))

        let callback: ChatGPTOAuth.Callback
        do {
            callback = try await withTimeout(seconds: signInTimeoutSeconds) {
                for await callback in callbacks {
                    return callback
                }
                throw CancellationError()
            }
        } catch is TimeoutError {
            return .timedOut
        } catch {
            return .canceled
        }

        guard case let .authorized(code, clientID) = callback else {
            return callback == .denied ? .denied : .failed
        }
        do {
            let (data, status) = try await send(ChatGPTOAuth.codeExchange(code: code, clientID: clientID, attempt: attempt, redirectURI: redirectURI))
            guard status == 200, let response = try? JSONDecoder().decode(ChatGPTOAuth.TokenResponse.self, from: data), let idToken = response.idToken else {
                AppLogger.shared.log(.error, "chatgpt sign-in: code exchange status=\(status) code=\(ChatGPTOAuth.loggable(ChatGPTOAuth.errorCode(in: data)))")
                return .failed
            }
            let claims = try ChatGPTIDToken.validate(idToken, keys: try await signingKeys(), clientID: clientID, nonce: attempt.nonce, now: now())
            if let saved, saved.subject != claims.subject {
                AppLogger.shared.log(.error, "chatgpt sign-in: another account than the saved one")
                return .failed
            }
            guard response.allowsPlanUse else {
                _ = await revoke(refreshToken: response.refreshToken, clientID: clientID)
                return .noPlanPermission
            }
            // A cancel after the last request: the user stopped this sign-in.
            guard !Task.isCancelled else {
                _ = await revoke(refreshToken: response.refreshToken, clientID: clientID)
                return .canceled
            }
            let signedIn = ChatGPTCredentials(
                clientID: clientID,
                subject: claims.subject,
                email: claims.email,
                idToken: idToken,
                tokens: tokens(from: response)
            )
            try store.save(signedIn)
            credentials = signedIn
            loaded = true
            return .connected
        } catch is CancellationError {
            return .canceled
        } catch {
            AppLogger.shared.log(.error, "chatgpt sign-in: not finished error=\(type(of: error))")
            return .failed
        }
    }

    /// Ends the sign-in on this Mac, then asks OpenAI to end it. False when
    /// OpenAI did not confirm: the user can then remove the access in
    /// ChatGPT settings.
    func disconnect() async -> Bool {
        let saved = current()
        generation += 1
        credentials = nil
        store.delete()
        guard let saved, let tokens = saved.tokens else { return true }
        return await revoke(refreshToken: tokens.refreshToken, clientID: saved.clientID)
    }

    // MARK: - Tokens

    /// The access token for a request. `rejected`: a token that the service
    /// refused. It causes a refresh only while it is still the saved token:
    /// another request can have replaced it already.
    func accessToken(rejected: String? = nil) async throws -> String {
        guard let tokens = current()?.tokens else { throw ChatGPTError.signInEnded }
        if tokens.accessToken != rejected, tokens.expiresAt.timeIntervalSince(now()) > Self.refreshMargin {
            return tokens.accessToken
        }
        if let refreshTask {
            return try await refreshTask.value
        }
        let started = generation
        let task = Task { try await refresh(startedIn: started) }
        refreshTask = task
        return try await task.value
    }

    private func refresh(startedIn started: Int) async throws -> String {
        defer { refreshTask = nil }
        guard let saved = credentials, let old = saved.tokens else { throw ChatGPTError.signInEnded }
        let (data, status) = try await send(ChatGPTOAuth.refresh(refreshToken: old.refreshToken, clientID: saved.clientID))
        if status == 200, let response = try? JSONDecoder().decode(ChatGPTOAuth.TokenResponse.self, from: data) {
            guard generation == started else {
                // A disconnect came first: the new sign-in must not stay.
                _ = await revoke(refreshToken: response.refreshToken, clientID: saved.clientID)
                throw ChatGPTError.signInEnded
            }
            var updated = saved
            updated.tokens = tokens(from: response)
            save(updated)
            return response.accessToken
        }
        guard generation == started else { throw ChatGPTError.signInEnded }
        let code = ChatGPTOAuth.errorCode(in: data)
        AppLogger.shared.log(.error, "chatgpt refresh failed status=\(status) code=\(ChatGPTOAuth.loggable(code))")
        if let code, Self.endedSignInCodes.contains(code) {
            var ended = saved
            ended.tokens = nil
            save(ended)
            throw ChatGPTError.signInEnded
        }
        if code == "invalid_client" {
            credentials = nil
            store.delete()
            throw ChatGPTError.signInEnded
        }
        throw ChatGPTError.service
    }

    private func tokens(from response: ChatGPTOAuth.TokenResponse) -> ChatGPTCredentials.Tokens {
        ChatGPTCredentials.Tokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            scopes: response.scopes,
            expiresAt: now().addingTimeInterval(response.expiresIn)
        )
    }

    private func save(_ updated: ChatGPTCredentials) {
        credentials = updated
        do {
            try store.save(updated)
        } catch {
            // The tokens work until the app quits; the next launch asks for
            // a new sign-in.
            AppLogger.shared.log(.error, "chatgpt credentials not saved")
        }
    }

    private func current() -> ChatGPTCredentials? {
        if !loaded {
            credentials = store.load()
            loaded = true
        }
        return credentials
    }

    /// Names this Mac to OpenAI. Not a secret; it stays after a disconnect.
    private func hostID() -> String {
        if let saved = defaults.string(forKey: Self.hostIDKey) {
            return saved
        }
        let made = "urn:uuid:\(UUID().uuidString.lowercased())"
        defaults.set(made, forKey: Self.hostIDKey)
        return made
    }

    // MARK: - Requests

    private func revoke(refreshToken: String, clientID: String) async -> Bool {
        for attempt in 0 ..< 2 {
            if attempt > 0 {
                try? await Task.sleep(for: revocationRetryDelay)
            }
            guard let endpoint = try? await discovered().revocationEndpoint,
                  let (_, status) = try? await send(ChatGPTOAuth.revocation(at: endpoint, refreshToken: refreshToken, clientID: clientID))
            else { continue }
            if status == 200 {
                return true
            }
            AppLogger.shared.log(.error, "chatgpt revocation status=\(status)")
        }
        return false
    }

    private func signingKeys() async throws -> [ChatGPTIDToken.Key] {
        let (data, status) = try await send(URLRequest(url: try await discovered().jwksURI, timeoutInterval: 30))
        guard status == 200 else { throw ChatGPTError.service }
        return try JSONDecoder().decode(ChatGPTIDToken.KeyList.self, from: data).keys
    }

    private func discovered() async throws -> Discovery {
        if let discovery {
            return discovery
        }
        let (data, status) = try await send(URLRequest(url: ChatGPTOAuth.discoveryURL, timeoutInterval: 30))
        guard status == 200 else { throw ChatGPTError.service }
        let read = try JSONDecoder().decode(Discovery.self, from: data)
        discovery = read
        return read
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw try ChatGPTError(transport: error)
        }
    }
}

extension ChatGPTError {
    /// A URL loading failure. A canceled task stays a cancel.
    init(transport error: Error) throws {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            throw CancellationError()
        }
        self = (error as? URLError)?.code == .timedOut ? .timeout : .network
    }
}
