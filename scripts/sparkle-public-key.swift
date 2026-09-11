import CryptoKit
import Foundation

// Read Sparkle's exported base64 Ed25519 seed from stdin. Only the public key leaves stdout.
let input = FileHandle.standardInput.readDataToEndOfFile()
guard let encoded = String(data: input, encoding: .utf8),
      let seed = Data(base64Encoded: encoded), seed.count == 32,
      seed.base64EncodedString() == encoded,
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else {
    FileHandle.standardError.write(Data("Expected a canonical base64 32-byte Sparkle signing seed.\n".utf8))
    exit(78)
}
print(key.publicKey.rawRepresentation.base64EncodedString())
