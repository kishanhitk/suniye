// Verifies a Sparkle EdDSA (ed25519) signature over an update archive the way
// Sparkle's installer does: over the whole file, with the public key that the
// installed app embeds as SUPublicEDKey.
import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(Data("Usage: verify_sparkle_signature.swift <archive> <base64-public-key> <base64-signature>\n".utf8))
    exit(2)
}

guard let publicKeyData = Data(base64Encoded: arguments[2]),
      let signature = Data(base64Encoded: arguments[3]) else {
    FileHandle.standardError.write(Data("Public key or signature is not valid base64.\n".utf8))
    exit(2)
}

do {
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[1]), options: .mappedIfSafe)
    guard publicKey.isValidSignature(signature, for: archive) else {
        FileHandle.standardError.write(Data("Sparkle EdDSA signature does not match \(arguments[1]).\n".utf8))
        exit(1)
    }
    print("Sparkle EdDSA signature is valid for \(arguments[1])")
} catch {
    FileHandle.standardError.write(Data("Sparkle signature check failed: \(error)\n".utf8))
    exit(1)
}
