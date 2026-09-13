import CryptoKit
import Foundation
import Security

enum PKCEError: Error {
    case randomGeneration(OSStatus)
}

struct PKCEPair: Sendable {
    let verifier: String
    let challenge: String
}

enum PKCE {
    static func makePair(byteCount: Int = 64) throws -> PKCEPair {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw PKCEError.randomGeneration(status) }
        let verifier = base64URL(Data(bytes))
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = base64URL(Data(digest))
        return PKCEPair(verifier: verifier, challenge: challenge)
    }

    static func makeState(byteCount: Int = 32) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw PKCEError.randomGeneration(status) }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
