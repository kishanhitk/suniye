import CryptoKit
import Foundation

/// The requests and the checks of Sign in with ChatGPT for an open-source
/// app: a public client with PKCE, a callback on 127.0.0.1, and a client ID
/// that OpenAI issues at the first sign-in.
enum ChatGPTOAuth {
    static let authorizeURL = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    static let tokenURL = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    static let discoveryURL = URL(string: "https://auth.openai.com/.well-known/openid-configuration")!
    static let issuer = "https://auth.openai.com"
    static let resource = "https://api.openai.com/v1"
    static let scopes = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    /// Without this scope a token cannot use the user's ChatGPT plan.
    static let planScope = "chatgpt.tokens.use.direct"
    /// The client ID of a first sign-in. It is never saved: the callback
    /// gives the issued one.
    static let registrationClientID = "dynamic_agent_client"
    static let appName = "Suniye"
    static let callbackPath = "/auth/callback"
    static let preferredCallbackPort: UInt16 = 1455

    /// The random values of one sign-in attempt.
    struct Attempt: Equatable, Sendable {
        let state: String
        let nonce: String
        let verifier: String

        init() {
            state = ChatGPTOAuth.randomValue()
            nonce = ChatGPTOAuth.randomValue()
            verifier = ChatGPTOAuth.randomValue()
        }

        var challenge: String {
            Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        }
    }

    /// What an earlier sign-in left: the next sign-in is for the same
    /// account.
    struct Registration: Equatable, Sendable {
        let clientID: String
        let idToken: String
        let email: String?
    }

    enum Callback: Equatable, Sendable {
        case authorized(code: String, clientID: String)
        case denied
        case failed
    }

    struct TokenResponse: Decodable, Equatable {
        let accessToken: String
        let refreshToken: String
        let idToken: String?
        let expiresIn: Double
        let scope: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
            case expiresIn = "expires_in"
            case scope
        }

        var scopes: [String] {
            scope.split(separator: " ").map(String.init)
        }

        var allowsPlanUse: Bool {
            scopes.contains(ChatGPTOAuth.planScope)
        }
    }

    /// Never "localhost": OpenAI matches the host exactly. Only the port can
    /// change between attempts.
    static func redirectURI(port: UInt16) -> String {
        "http://127.0.0.1:\(port)\(callbackPath)"
    }

    /// The page that the browser opens. It can hold the saved ID token, so
    /// it is never logged.
    static func authorizeURL(attempt: Attempt, redirectURI: String, hostID: String, registration: Registration?) -> URL {
        var items = [URLQueryItem(name: "client_id", value: registration?.clientID ?? registrationClientID)]
        if let registration {
            items.append(URLQueryItem(name: "id_token_hint", value: registration.idToken))
            if let email = registration.email {
                items.append(URLQueryItem(name: "login_hint", value: email))
            }
        } else {
            items.append(URLQueryItem(name: "agent_name_hint", value: appName))
        }
        items += [
            URLQueryItem(name: "ext_agent_host_id", value: hostID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "resource", value: resource),
            URLQueryItem(name: "state", value: attempt.state),
            URLQueryItem(name: "nonce", value: attempt.nonce),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: attempt.challenge),
        ]
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = formEncoded(items)
        return components.url!
    }

    /// Reads the target of a request to the callback listener, such as
    /// "/auth/callback?code=…&state=…". Nil for another path or another
    /// `state`: the tab of an earlier attempt must not end this one.
    static func callback(target: String, attempt: Attempt, registration: Registration?) -> Callback? {
        guard let components = URLComponents(string: target), components.path == callbackPath else { return nil }
        let values = Dictionary((components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } }) { first, _ in first }
        guard values["state"] == attempt.state else { return nil }
        if let error = values["error"] {
            return error == "access_denied" ? .denied : .failed
        }
        guard let code = values["code"], !code.isEmpty else { return .failed }
        if let registration {
            // The callback of a sign-in again can leave the client ID out.
            guard values["client_id"] ?? registration.clientID == registration.clientID else { return .failed }
            return .authorized(code: code, clientID: registration.clientID)
        }
        guard let clientID = values["client_id"], !clientID.isEmpty, clientID != registrationClientID else { return .failed }
        return .authorized(code: code, clientID: clientID)
    }

    /// `redirectURI` must be the one of the authorize request.
    static func codeExchange(code: String, clientID: String, attempt: Attempt, redirectURI: String) -> URLRequest {
        formRequest(tokenURL, [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: attempt.verifier),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "resource", value: resource),
        ])
    }

    /// No `scope`: the refresh keeps what the user granted.
    static func refresh(refreshToken: String, clientID: String) -> URLRequest {
        formRequest(tokenURL, [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "resource", value: resource),
        ])
    }

    static func revocation(at endpoint: URL, refreshToken: String, clientID: String) -> URLRequest {
        formRequest(endpoint, [
            URLQueryItem(name: "token", value: refreshToken),
            URLQueryItem(name: "token_type_hint", value: "refresh_token"),
            URLQueryItem(name: "client_id", value: clientID),
        ])
    }

    /// The code of an error answer from the token endpoint, such as
    /// `invalid_grant`. The code is at `error`, at `error.code` or at `code`.
    static func errorCode(in body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        if let code = object["error"] as? String {
            return code
        }
        if let error = object["error"] as? [String: Any], let code = error["code"] as? String {
            return code
        }
        return object["code"] as? String
    }

    private static func formRequest(_ url: URL, _ items: [URLQueryItem]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(formEncoded(items).utf8)
        return request
    }

    /// `URLComponents` leaves "+" as it is, and a form reads "+" as a space.
    private static func formEncoded(_ items: [URLQueryItem]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return items.map { item in
            let value = (item.value ?? "").addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(item.name)=\(value)"
        }.joined(separator: "&")
    }

    private static func randomValue() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "no random bytes")
        return Data(bytes).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded text: String) {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
