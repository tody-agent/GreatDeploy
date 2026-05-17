## Setup SPM trước khi paste code

Trong `Package.swift` hoặc Xcode → **File > Add Package Dependencies**:

```
https://github.com/tmthecoder/Argon2Swift   (from: 1.0.0)
```

Rồi link target `Argon2Swift` vào target `GreatDeploy`.

---

## `Services/CryptoService.swift`

```swift
//
//  CryptoService.swift
//  GreatDeploy
//
//  End-to-end encryption service for the sync vault.
//
//  Design goals:
//  - Derive a 256-bit master key from a user passphrase (16 chars recommended)
//    using Argon2id (memory-hard, side-channel resistant).
//  - Encrypt sensitive payloads with ChaCha20-Poly1305 (AEAD) so any tampering
//    is detected and arbitrary "associated data" (AAD) binds ciphertexts to
//    their slot (e.g. "github_pat:personal") preventing swap attacks.
//  - Sign manifests with HMAC-SHA256 so even plain-text files (markdown,
//    scripts, skills) cannot be silently modified by the relay.
//  - Cache the derived key in memory only; persistence of the passphrase
//    itself is handled by KeychainService (kSecAttrAccessibleWhenUnlockedThisDeviceOnly).
//
//  Dependencies:
//    - CryptoKit            (system, macOS 10.15+)
//    - Argon2Swift          (SPM: https://github.com/tmthecoder/Argon2Swift)
//

import Foundation
import CryptoKit
import Argon2Swift

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

// MARK: - Envelope (wire format for encrypted items)

/// JSON envelope that wraps a single encrypted blob.
/// Stored as-is in the vault DB and shipped over the wire.
public struct CryptoEnvelope: Codable, Equatable {
    public let v: Int                 // schema version
    public let alg: String            // "chacha20poly1305"
    public let kdf: KDFParams         // params needed to re-derive the key
    public let nonce: Data            // 12 bytes
    public let ct: Data               // ciphertext || auth tag (combined .ciphertext + .tag)
    public let aad: String?           // human-readable AAD, e.g. "github_pat:personal"

    public struct KDFParams: Codable, Equatable {
        public let name: String       // "argon2id"
        public let salt: Data         // per-vault salt, 16 bytes
        public let memKiB: Int        // memory cost (KiB)
        public let iters: Int         // time cost
        public let parallel: Int      // lanes
    }
}

// MARK: - Manifest signature (for plain-text integrity)

public struct SignedManifest: Codable, Equatable {
    public let payload: Data          // canonical JSON bytes of the manifest
    public let hmac: Data             // HMAC-SHA256(master_key_sig, payload)
    public let alg: String            // "hmac-sha256"
}

// MARK: - CryptoService

public final class CryptoService {

    // MARK: Singleton (optional — feel free to inject if you prefer DI)
    public static let shared = CryptoService()

    // MARK: Tunables
    /// We require exactly 16 characters per the product spec ("16-digit wallet-style key").
    public static let requiredPassphraseLength = 16

    /// Argon2id params. ~250 ms on Apple M-series, ~600 ms on Intel Mac.
    /// Bumped from OWASP minimum because we only run KDF once per app session.
    public static let kdfMemoryKiB = 64 * 1024     // 64 MiB
    public static let kdfIterations = 3
    public static let kdfParallelism = 1
    public static let kdfSaltBytes = 16
    public static let derivedKeyBytes = 32         // 256-bit

    // MARK: State (in-memory only)
    private let queue = DispatchQueue(label: "com.greatdeploy.crypto", qos: .userInitiated)
    private var masterKey: SymmetricKey?           // for AEAD
    private var signingKey: SymmetricKey?          // for HMAC, separate per HKDF
    private var currentSalt: Data?                 // remembered after unlock for re-use

    private init() {}

    // MARK: - Public API: lifecycle

    /// Whether the vault is currently unlocked in memory.
    public var isUnlocked: Bool {
        queue.sync { masterKey != nil }
    }

    /// Forget the master key. Call when app locks, sleeps, or user signs out.
    public func lock() {
        queue.sync {
            masterKey = nil
            signingKey = nil
            currentSalt = nil
        }
    }

    /// Generate a fresh random salt to use when initializing a brand-new vault.
    public static func newSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: kdfSaltBytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, kdfSaltBytes, &bytes)
        return Data(bytes)
    }

    /// Generate a cryptographically strong random 16-char alphanumeric passphrase.
    /// Entropy ≈ log2(62^16) ≈ 95 bits.
    public static func generatePassphrase() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
        // Removed ambiguous 0/O/1/l/I for human transcription friendliness.
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

    /// Derive and cache the master key from a passphrase + per-vault salt.
    /// Pass `salt = nil` only when bootstrapping a brand-new vault; in that case
    /// `newSalt()` is called for you and the salt is returned for persistence.
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

        // HKDF-expand into two domain-separated subkeys so AEAD key and HMAC
        // key never coincide. This is best practice even with a 256-bit root.
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

    /// Verify a candidate passphrase by attempting to decrypt a known
    /// "sentinel" envelope previously stored at vault creation time.
    /// Use this when the user is asked to re-enter the passphrase.
    public func verify(passphrase: String, sentinel: CryptoEnvelope) -> Bool {
        do {
            _ = try unlock(passphrase: passphrase, salt: sentinel.kdf.salt)
            _ = try decrypt(envelope: sentinel)
            return true
        } catch {
            return false
        }
    }

    /// Build a sentinel envelope when initializing a vault. Persist it to disk.
    /// The plaintext is a fixed magic string so we never log secrets.
    public func makeSentinel() throws -> CryptoEnvelope {
        return try encrypt(
            plaintext: Data("GREATDEPLOY-VAULT-OK".utf8),
            aad: "vault:sentinel"
        )
    }

    // MARK: - Public API: encryption

    /// Encrypt arbitrary bytes. `aad` binds the ciphertext to a logical slot
    /// (e.g. "github_pat:work") — decrypting with a different aad will fail.
    public func encrypt(plaintext: Data, aad: String?) throws -> CryptoEnvelope {
        guard let key = queue.sync(execute: { masterKey }),
              let salt = queue.sync(execute: { currentSalt }) else {
            throw CryptoError.keyNotUnlocked
        }

        // 12-byte random nonce. Acceptable for personal vault scale.
        // For multi-user / high-volume scenarios, migrate to XChaCha20 via libsodium.
        let nonce = ChaChaPoly.Nonce()
        let aadBytes = aad.map { Data($0.utf8) } ?? Data()
        let sealed: ChaChaPoly.SealedBox
        if aadBytes.isEmpty {
            sealed = try ChaChaPoly.seal(plaintext, using: key)
        } else {
            sealed = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce, authenticating: aadBytes)
        }

        // .combined = nonce(12) || ct || tag(16). We split because we want to
        // version the nonce explicitly in the envelope (helps future migrations).
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

    /// Decrypt an envelope produced by `encrypt`. Throws on any tampering.
    public func decrypt(envelope: CryptoEnvelope) throws -> Data {
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

    // MARK: - Public API: convenience for strings

    public func encryptString(_ s: String, aad: String?) throws -> CryptoEnvelope {
        try encrypt(plaintext: Data(s.utf8), aad: aad)
    }

    public func decryptString(_ env: CryptoEnvelope) throws -> String {
        let d = try decrypt(envelope: env)
        guard let s = String(data: d, encoding: .utf8) else {
            throw CryptoError.malformedEnvelope(reason: "plaintext is not valid UTF-8")
        }
        return s
    }

    // MARK: - Public API: manifest signing (for plain files & global integrity)

    /// Sign the canonical bytes of a manifest. The receiver re-computes the HMAC
    /// using the same derived signingKey and compares constant-time.
    public func sign(_ payload: Data) throws -> SignedManifest {
        guard let mk = queue.sync(execute: { signingKey }) else {
            throw CryptoError.keyNotUnlocked
        }
        let mac = HMAC<SHA256>.authenticationCode(for: payload, using: mk)
        return SignedManifest(payload: payload, hmac: Data(mac), alg: "hmac-sha256")
    }

    /// Verify a SignedManifest. Returns the payload on success, throws on failure.
    @discardableResult
    public func verify(_ signed: SignedManifest) throws -> Data {
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

    /// SHA-256 helper for building Merkle leaves over plain files.
    public static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    // MARK: - Internal: KDF

    private static func deriveKey(passphrase: String, salt: Data) throws -> Data {
        do {
            let saltObj = Salt(bytes: salt)
            let result = try Argon2Swift.hashPasswordString(
                password: passphrase,
                salt: saltObj,
                iterations: Int32(kdfIterations),
                memory: Int32(kdfMemoryKiB),
                parallelism: Int32(kdfParallelism),
                length: Int32(derivedKeyBytes),
                type: .id   // Argon2id
            )
            return result.hashData()
        } catch {
            throw CryptoError.kdfFailed(underlying: error)
        }
    }
}
```

---

## Cách dùng nhanh (ví dụ)

```swift
// 1) Vault bootstrap (lần đầu)
let pass = CryptoService.generatePassphrase()      // hiển thị 1 lần cho user copy
let salt = try CryptoService.shared.unlock(passphrase: pass, salt: nil)
let sentinel = try CryptoService.shared.makeSentinel()
// → Persist `salt` và `sentinel` vào VaultStore. Persist `pass` vào Keychain
//   (kSecAttrAccessibleWhenUnlockedThisDeviceOnly).

// 2) Mã hoá một PAT
let env = try CryptoService.shared.encryptString(
    "ghp_xxxxxxxxxxxxxxxx",
    aad: "github_pat:personal"
)
// → lưu `env` (Codable JSON) vào DB

// 3) Mã hoá lại trên máy khác sau khi user nhập 16 ký tự
let ok = CryptoService.shared.verify(passphrase: typedPass, sentinel: storedSentinel)
guard ok else { /* sai passphrase */ return }
let pat = try CryptoService.shared.decryptString(env)

// 4) Ký manifest cho phần plain (skills .md, scripts)
let manifestJSON = try JSONEncoder().encode(manifestStruct)
let signed = try CryptoService.shared.sign(manifestJSON)
// → gửi `signed` cho client; client gọi try CryptoService.shared.verify(signed)
```

---

## Ghi chú quan trọng

**Về AAD và `nonce` trong `encrypt`**: tôi gọi `ChaChaPoly.seal(_, using:, nonce:, authenticating:)` khi có AAD, nhưng overload không-AAD lại không nhận `nonce` trong cùng signature. Nếu Xcode complain, đơn giản hoá thành luôn dùng cùng một overload có `nonce` và truyền `Data()` cho AAD rỗng — kết quả tương đương về mặt mã hoá nhưng `aad` trong envelope vẫn nên là `nil` để rõ ý.

**`ChaChaPoly.Nonce()` mặc định** đã sinh ngẫu nhiên 12 byte qua `SecRandomCopyBytes`, không cần làm thêm.

**Argon2Swift API surface**: tên class/struct (`Salt`, `Argon2Swift.hashPasswordString`, `.id`, `.hashData()`) đúng với version 1.x của tmthecoder. Nếu bạn pin version khác, double-check 2 dòng trong `deriveKey` — đó là chỗ duy nhất phụ thuộc API ngoài.

**Tham số Argon2id**: 64 MiB / 3 iter / 1 lane là cao hơn khuyến nghị OWASP 2024 (19 MiB / 2 iter) — đổi lấy ~250 ms trên M-series. Vì ta chỉ chạy KDF một lần khi unlock, đây là trade-off hợp lý. Nếu thấy chậm trên Intel Mac cũ, hạ `kdfMemoryKiB` xuống `19 * 1024`.

**Limit của `ChaChaPoly` nonce 12-byte**: an toàn đến ~2^32 messages cùng key. Vault cá nhân không bao giờ đụng tới ngưỡng đó. Nếu bạn mở rộng thành multi-tenant, migrate sang `Sodium.SecretStream` (XChaCha20-Poly1305, nonce 24-byte).

**Thread safety**: dùng `DispatchQueue` serial bọc state mutable. CryptoKit operations bản thân là thread-safe.

**Unit test gợi ý** (tối thiểu): round-trip encrypt/decrypt, sai AAD phải throw, sai passphrase phải throw, sentinel verify true/false, HMAC tamper detect, JSON encode/decode `CryptoEnvelope` ổn định.
