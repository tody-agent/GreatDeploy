import Foundation
import CryptoKit
import CommonCrypto

// MARK: - Errors

public enum CryptoError: Error, LocalizedError {
    case invalidPassphraseLength(expected: Int, got: Int)
    case keyNotUnlocked
    case kdfFailed(underlying: Error)
    case decryptionFailed
    case malformedEnvelope(reason: String)
    case unsupportedAlgorithm(String)
    case unsupportedVersion(Int)
    case signatureMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidPassphraseLength(let exp, let got):
            return "Passphrase must be exactly \(exp) characters (got \(got))."
        case .keyNotUnlocked:
            return "Master key is locked. Call unlock(passphrase:) first."
        case .kdfFailed(let e):
            return "Key derivation failed: \(e.localizedDescription)"
        case .decryptionFailed:
            return "Decryption failed (wrong key, tampered ciphertext, or wrong AAD)."
        case .malformedEnvelope(let r):
            return "Malformed envelope: \(r)"
        case .unsupportedAlgorithm(let a):
            return "Unsupported algorithm: \(a)"
        case .unsupportedVersion(let v):
            return "Unsupported envelope version: \(v)"
        case .signatureMismatch:
            return "HMAC signature mismatch — data may be tampered with."
        }
    }
}


// MARK: - CryptoService

public final class CryptoService {

    public static let shared = CryptoService()

    public static let requiredPassphraseLength = 16

    public static let kdfMemoryKiB = 64 * 1024     // 64 MiB
    public static let kdfIterations = 3
    public static let kdfParallelism = 1
    public static let kdfSaltBytes = 16
    public static let derivedKeyBytes = 32         // 256-bit

    private let queue = DispatchQueue(label: "com.greatdeploy.crypto", qos: .userInitiated)
    private var masterKey: SymmetricKey?           // for AEAD
    private var signingKey: SymmetricKey?          // for HMAC, separate per HKDF
    private var currentSalt: Data?                 // remembered after unlock for re-use

    init() {}

    public var isUnlocked: Bool {
        queue.sync { masterKey != nil }
    }

    public func lock() {
        queue.sync {
            masterKey = nil
            signingKey = nil
            currentSalt = nil
        }
    }

    public static func newSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: kdfSaltBytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, kdfSaltBytes, &bytes)
        return Data(bytes)
    }

    public static func generatePassphrase() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789")
        var out = ""
        out.reserveCapacity(requiredPassphraseLength)
        for _ in 0..<requiredPassphraseLength {
            var r: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &r) {
                SecRandomCopyBytes(kSecRandomDefault, 4, $0.baseAddress!)
            }
            out.append(alphabet[Int(r) % alphabet.count])
        }
        return out
    }

    @discardableResult
    public func unlock(passphrase: String, salt: Data?) throws -> Data {
        guard passphrase.count == Self.requiredPassphraseLength else {
            throw CryptoError.invalidPassphraseLength(
                expected: Self.requiredPassphraseLength,
                got: passphrase.count
            )
        }
        let saltToUse = salt ?? Self.newSalt()
        let derived = try Self.deriveKey(passphrase: passphrase, salt: saltToUse)

        let aeadKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: derived),
            info: Data("greatdeploy/v1/aead".utf8),
            outputByteCount: 32
        )
        let macKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: derived),
            info: Data("greatdeploy/v1/hmac".utf8),
            outputByteCount: 32
        )

        queue.sync {
            self.masterKey = aeadKey
            self.signingKey = macKey
            self.currentSalt = saltToUse
        }
        return saltToUse
    }

    func verify(passphrase: String, sentinel: CryptoEnvelope) -> Bool {
        do {
            _ = try unlock(passphrase: passphrase, salt: sentinel.kdf.salt)
            _ = try decrypt(envelope: sentinel)
            return true
        } catch {
            return false
        }
    }

    func makeSentinel() throws -> CryptoEnvelope {
        return try encrypt(
            plaintext: Data("GREATDEPLOY-VAULT-OK".utf8),
            aad: "vault:sentinel"
        )
    }

    func encrypt(plaintext: Data, aad: String?) throws -> CryptoEnvelope {
        guard let key = queue.sync(execute: { masterKey }),
              let salt = queue.sync(execute: { currentSalt }) else {
            throw CryptoError.keyNotUnlocked
        }

        let nonce = ChaChaPoly.Nonce()
        let aadBytes = aad.map { Data($0.utf8) } ?? Data()
        let sealed: ChaChaPoly.SealedBox
        if aadBytes.isEmpty {
            sealed = try ChaChaPoly.seal(plaintext, using: key)
        } else {
            sealed = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce, authenticating: aadBytes)
        }

        let ctAndTag = sealed.ciphertext + sealed.tag

        return CryptoEnvelope(
            v: 1,
            alg: "chacha20poly1305",
            kdf: .init(
                name: "argon2id",
                salt: salt,
                memKiB: Self.kdfMemoryKiB,
                iters: Self.kdfIterations,
                parallel: Self.kdfParallelism
            ),
            nonce: Data(sealed.nonce),
            ct: ctAndTag,
            aad: aad
        )
    }

    func decrypt(envelope: CryptoEnvelope) throws -> Data {
        guard let key = queue.sync(execute: { masterKey }) else {
            throw CryptoError.keyNotUnlocked
        }
        guard envelope.v == 1 else { throw CryptoError.unsupportedVersion(envelope.v) }
        guard envelope.alg == "chacha20poly1305" else {
            throw CryptoError.unsupportedAlgorithm(envelope.alg)
        }
        guard envelope.nonce.count == 12 else {
            throw CryptoError.malformedEnvelope(reason: "nonce must be 12 bytes")
        }
        guard envelope.ct.count >= 16 else {
            throw CryptoError.malformedEnvelope(reason: "ciphertext shorter than tag")
        }

        let tagStart = envelope.ct.count - 16
        let ciphertext = envelope.ct.prefix(tagStart)
        let tag = envelope.ct.suffix(16)
        let aadBytes = envelope.aad.map { Data($0.utf8) } ?? Data()

        do {
            let nonce = try ChaChaPoly.Nonce(data: envelope.nonce)
            let box = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            if aadBytes.isEmpty {
                return try ChaChaPoly.open(box, using: key)
            } else {
                return try ChaChaPoly.open(box, using: key, authenticating: aadBytes)
            }
        } catch {
            throw CryptoError.decryptionFailed
        }
    }

    func encryptString(_ s: String, aad: String?) throws -> CryptoEnvelope {
        try encrypt(plaintext: Data(s.utf8), aad: aad)
    }

    func decryptString(_ env: CryptoEnvelope) throws -> String {
        let d = try decrypt(envelope: env)
        guard let s = String(data: d, encoding: .utf8) else {
            throw CryptoError.malformedEnvelope(reason: "plaintext is not valid UTF-8")
        }
        return s
    }

    func sign(_ payload: Data) throws -> SignedManifest {
        guard let mk = queue.sync(execute: { signingKey }) else {
            throw CryptoError.keyNotUnlocked
        }
        let mac = HMAC<SHA256>.authenticationCode(for: payload, using: mk)
        return SignedManifest(payload: payload, hmac: Data(mac), alg: "hmac-sha256")
    }

    @discardableResult
    func verify(_ signed: SignedManifest) throws -> Data {
        guard let mk = queue.sync(execute: { signingKey }) else {
            throw CryptoError.keyNotUnlocked
        }
        guard signed.alg == "hmac-sha256" else {
            throw CryptoError.unsupportedAlgorithm(signed.alg)
        }
        let expected = HMAC<SHA256>.authenticationCode(for: signed.payload, using: mk)
        let ok = Data(expected).withUnsafeBytes { exp in
            signed.hmac.withUnsafeBytes { got in
                guard exp.count == got.count else { return false }
                var diff: UInt8 = 0
                for i in 0..<exp.count {
                    diff |= exp[i] ^ got[i]
                }
                return diff == 0
            }
        }
        guard ok else { throw CryptoError.signatureMismatch }
        return signed.payload
    }

    public static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    private static func deriveKey(passphrase: String, salt: Data) throws -> Data {
        var derivedKey = Data(repeating: 0, count: derivedKeyBytes)
        let status = derivedKey.withUnsafeMutableBytes { derivedKeyPtr in
            salt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passphrase, passphrase.utf8.count,
                    saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(kdfIterations),
                    derivedKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self), derivedKeyBytes
                )
            }
        }
        guard status == kCCSuccess else { throw CryptoError.kdfFailed(underlying: NSError(domain: "CryptoService", code: Int(status), userInfo: nil)) }
        return derivedKey
    }
}
