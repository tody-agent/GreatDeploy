import XCTest
import CryptoKit
@testable import GreatDeploy

final class CryptoServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService() -> CryptoService {
        // Use a fresh instance per test to avoid singleton state conflicts
        CryptoService()
    }

    private func unlockedService() throws -> CryptoService {
        let svc = makeService()
        let pass = CryptoService.generatePassphrase()
        let salt = CryptoService.newSalt()
        try svc.unlock(passphrase: pass, salt: salt)
        return svc
    }

    // MARK: - Encrypt / Decrypt Round-Trip

    func testRoundTripEncryptDecrypt() throws {
        let svc = try unlockedService()
        defer { svc.lock() }

        let plaintext = Data("Hello, GreatDeploy Vault!".utf8)
        let envelope = try svc.encrypt(plaintext: plaintext, aad: "test:roundtrip")

        let decrypted = try svc.decrypt(envelope: envelope)
        XCTAssertEqual(decrypted, plaintext)
    }

    // MARK: - Wrong AAD

    func testWrongAADThrows() throws {
        let svc = try unlockedService()
        defer { svc.lock() }

        let plaintext = Data("secret".utf8)
        let envelope = try svc.encrypt(plaintext: plaintext, aad: "correct:aad")

        // Tamper AAD in envelope
        let tampered = CryptoEnvelope(
            v: envelope.v,
            alg: envelope.alg,
            kdf: envelope.kdf,
            nonce: envelope.nonce,
            ct: envelope.ct,
            aad: "wrong:aad"
        )

        XCTAssertThrowsError(try svc.decrypt(envelope: tampered)) { error in
            guard let cryptoError = error as? CryptoError,
                  case .decryptionFailed = cryptoError else {
                return XCTFail("Expected CryptoError.decryptionFailed, got \(error)")
            }
        }
    }

    // MARK: - Wrong Passphrase

    func testWrongPassphraseThrows() throws {
        let salt = CryptoService.newSalt()
        let correctPass = CryptoService.generatePassphrase()

        let svc = makeService()
        try svc.unlock(passphrase: correctPass, salt: salt)
        defer { svc.lock() }

        let plaintext = Data("another secret".utf8)
        let envelope = try svc.encrypt(plaintext: plaintext, aad: "test:wrongpass")

        // Try decrypt with a different key
        let wrongPass = CryptoService.generatePassphrase()
        let svc2 = makeService()
        try svc2.unlock(passphrase: wrongPass, salt: salt)

        XCTAssertThrowsError(try svc2.decrypt(envelope: envelope)) { error in
            guard let cryptoError = error as? CryptoError,
                  case .decryptionFailed = cryptoError else {
                return XCTFail("Expected CryptoError.decryptionFailed, got \(error)")
            }
        }

        svc2.lock()
    }

    // MARK: - Sentinel Verify

    func testSentinelVerify() throws {
        let pass = CryptoService.generatePassphrase()
        let salt = CryptoService.newSalt()

        let svc = makeService()
        try svc.unlock(passphrase: pass, salt: salt)
        defer { svc.lock() }

        let sentinel = try svc.makeSentinel()
        XCTAssertTrue(svc.verify(passphrase: pass, sentinel: sentinel))
    }

    // MARK: - Sentinel Verify Wrong Passphrase

    func testSentinelVerifyWrongPassphrase() throws {
        let pass = CryptoService.generatePassphrase()
        let salt = CryptoService.newSalt()

        let svc = makeService()
        try svc.unlock(passphrase: pass, salt: salt)
        defer { svc.lock() }

        let sentinel = try svc.makeSentinel()

        let wrongPass = CryptoService.generatePassphrase()
        XCTAssertFalse(svc.verify(passphrase: wrongPass, sentinel: sentinel))
    }

    // MARK: - HMAC Tamper Detection

    func testHMACTamperDetect() throws {
        let svc = try unlockedService()
        defer { svc.lock() }

        let payload = Data("integrity-critical-data".utf8)
        let signed = try svc.sign(payload)

        // Should verify successfully
        try svc.verify(signed)

        // Tamper with payload
        var tamperedPayload = payload
        tamperedPayload[0] ^= 0xFF

        let tampered = SignedManifest(
            payload: tamperedPayload,
            hmac: signed.hmac,
            alg: signed.alg
        )

        XCTAssertThrowsError(try svc.verify(tampered)) { error in
            guard let cryptoError = error as? CryptoError,
                  case .signatureMismatch = cryptoError else {
                return XCTFail("Expected CryptoError.signatureMismatch, got \(error)")
            }
        }
    }

    // MARK: - Envelope JSON Stability

    func testEnvelopeJSONStable() throws {
        let kdf = CryptoEnvelope.KDFParams(
            name: "pbkdf2-sha256",
            salt: Data([UInt8](repeating: 0xAB, count: 16)),
            memKiB: 0,
            iters: 600000,
            parallel: 1
        )

        let envelope = CryptoEnvelope(
            v: 1,
            alg: "chacha20poly1305",
            kdf: kdf,
            nonce: Data([UInt8](repeating: 0xCD, count: 12)),
            ct: Data([UInt8](repeating: 0xEF, count: 48)),
            aad: "test:aad"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let jsonData = try encoder.encode(envelope)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CryptoEnvelope.self, from: jsonData)

        XCTAssertEqual(decoded, envelope)
        XCTAssertEqual(decoded.v, 1)
        XCTAssertEqual(decoded.alg, "chacha20poly1305")
        XCTAssertEqual(decoded.kdf.name, "pbkdf2-sha256")
        XCTAssertEqual(decoded.aad, "test:aad")
    }

    // MARK: - Generate Passphrase Length

    func testGeneratePassphraseLength() {
        let pass = CryptoService.generatePassphrase()
        XCTAssertEqual(pass.count, 16, "Passphrase must be 16 characters")
    }

    // MARK: - Generate Passphrase Charset

    func testGeneratePassphraseCharset() {
        let pass = CryptoService.generatePassphrase()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789")
        for char in pass {
            let scalar = String(char).unicodeScalars.first!
            XCTAssertTrue(allowed.contains(scalar), "Disallowed character: \(char)")
        }
    }

    // MARK: - New Salt Length

    func testNewSaltLength() {
        let salt = CryptoService.newSalt()
        XCTAssertEqual(salt.count, 16, "Salt must be 16 bytes")
    }

    // MARK: - Lock Clears State

    func testLockClearsState() throws {
        let svc = try unlockedService()
        // Encrypt works while unlocked
        let plaintext = Data("test".utf8)
        _ = try svc.encrypt(plaintext: plaintext, aad: "test")

        svc.lock()

        // Should throw after lock
        XCTAssertThrowsError(try svc.encrypt(plaintext: plaintext, aad: "test")) { error in
            guard let cryptoError = error as? CryptoError,
                  case .keyNotUnlocked = cryptoError else {
                return XCTFail("Expected CryptoError.keyNotUnlocked, got \(error)")
            }
        }
    }

    // MARK: - Performance

    func testUnlockPerformance() throws {
        let pass = CryptoService.generatePassphrase()
        let salt = CryptoService.newSalt()
        measure {
            let svc = makeService()
            try? svc.unlock(passphrase: pass, salt: salt)
        }
    }
}
