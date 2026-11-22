import Foundation
import Security

/// The check of the ID token that a sign-in returns. The token says which
/// ChatGPT account signed in; only a token that passes is used.
enum ChatGPTIDToken {
    struct Claims: Equatable {
        let subject: String
        let email: String?
    }

    /// One RSA key of OpenAI's published key list.
    struct Key: Decodable, Equatable {
        let kid: String
        let kty: String
        let n: String
        let e: String
    }

    struct KeyList: Decodable {
        let keys: [Key]
    }

    enum Failure: Error, Equatable {
        case malformed
        case algorithm
        case unknownKey
        case signature
        case issuer
        case audience
        case expired
        case nonce
    }

    static func validate(_ token: String, keys: [Key], clientID: String, nonce: String, now: Date) throws -> Claims {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              let headerData = Data(base64URLEncoded: parts[0]),
              let payloadData = Data(base64URLEncoded: parts[1]),
              let signature = Data(base64URLEncoded: parts[2]),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else { throw Failure.malformed }

        guard header["alg"] as? String == "RS256" else { throw Failure.algorithm }
        guard let kid = header["kid"] as? String,
              let key = keys.first(where: { $0.kid == kid && $0.kty == "RSA" }),
              let publicKey = publicKey(key)
        else { throw Failure.unknownKey }
        let signed = Data("\(parts[0]).\(parts[1])".utf8)
        guard SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256, signed as CFData, signature as CFData, nil) else {
            throw Failure.signature
        }

        guard payload["iss"] as? String == ChatGPTOAuth.issuer else { throw Failure.issuer }
        // One audience is a string, several are a list.
        let audience = (payload["aud"] as? [String]) ?? (payload["aud"] as? String).map { [$0] } ?? []
        guard audience.contains(clientID) else { throw Failure.audience }
        guard let expiry = payload["exp"] as? Double, Date(timeIntervalSince1970: expiry) > now else { throw Failure.expired }
        guard payload["nonce"] as? String == nonce else { throw Failure.nonce }
        guard let subject = payload["sub"] as? String, !subject.isEmpty else { throw Failure.malformed }
        return Claims(subject: subject, email: payload["email"] as? String)
    }

    private static func publicKey(_ key: Key) -> SecKey? {
        guard let modulus = Data(base64URLEncoded: key.n), let exponent = Data(base64URLEncoded: key.e) else { return nil }
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        return SecKeyCreateWithData(rsaPublicKey(modulus: modulus, exponent: exponent) as CFData, attributes as CFDictionary, nil)
    }

    /// The key as the Security framework reads it: a DER sequence of the two
    /// integers.
    static func rsaPublicKey(modulus: Data, exponent: Data) -> Data {
        der(tag: 0x30, integer(modulus) + integer(exponent))
    }

    private static func integer(_ bytes: Data) -> Data {
        var value = bytes.drop { $0 == 0 }
        // A first bit of 1 would read as a negative number.
        if value.first.map({ $0 & 0x80 != 0 }) ?? true {
            value = [0] + value
        }
        return der(tag: 0x02, Data(value))
    }

    private static func der(tag: UInt8, _ content: Data) -> Data {
        var length = [UInt8]()
        if content.count < 0x80 {
            length = [UInt8(content.count)]
        } else {
            var count = content.count
            while count > 0 {
                length.insert(UInt8(count & 0xFF), at: 0)
                count >>= 8
            }
            length.insert(0x80 | UInt8(length.count), at: 0)
        }
        return Data([tag] + length) + content
    }
}
