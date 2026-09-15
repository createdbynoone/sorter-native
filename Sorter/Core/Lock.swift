import Foundation
import CommonCrypto

// Only the PBKDF2-SHA512 hash + salt live here — the passphrase itself is never in
// source or in the bundle. Regenerate with:
//   openssl kdf -keylen 64 -kdfopt digest:SHA512 -kdfopt pass:'NEW' \
//     -kdfopt hexsalt:<salt> -kdfopt iter:200000 PBKDF2
enum AppLock {
    private static let saltHex = "2746d27a3e7748dc50a9c629e5f34076"
    private static let hashHex = "84aa6d1ac9c145a791878166c118fd54d00d21c6f976eafe4f0af94dfe2045304ad3d63a07e33abfb22d40cc4cbca57f1eca7484c152dcc912cfff992fe80e0c"
    private static let iterations: UInt32 = 200_000

    private static func bytes(fromHex hex: String) -> [UInt8] {
        var out: [UInt8] = []
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            out.append(UInt8(hex[idx..<next], radix: 16) ?? 0)
            idx = next
        }
        return out
    }

    private static func derive(_ passphrase: String) -> [UInt8] {
        let salt = bytes(fromHex: saltHex)
        let pass = Array(passphrase.utf8)
        let keyLen = 64
        var derived = [UInt8](repeating: 0, count: keyLen)
        pass.withUnsafeBytes { p in
            salt.withUnsafeBytes { s in
                _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                         p.baseAddress?.assumingMemoryBound(to: CChar.self), pass.count,
                                         s.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512), iterations,
                                         &derived, keyLen)
            }
        }
        return derived
    }

    /// Constant-time comparison against the stored hash.
    static func verify(_ attempt: String) -> Bool {
        let candidate = derive(attempt)
        let expected = bytes(fromHex: hashHex)
        guard candidate.count == expected.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<candidate.count { diff |= candidate[i] ^ expected[i] }
        return diff == 0
    }

    // Failed attempts + lockout persist in prefs so relaunching can't reset the cooldown.
    static var lockUntil: Double { Prefs.load().authLockUntil ?? 0 }

    static func registerFailure() -> Double {
        var prefs = Prefs.load()
        let count = (prefs.authFailCount ?? 0) + 1
        let now = Date().timeIntervalSince1970 * 1000
        let until: Double = count >= 3 ? now + min(5000 * pow(2, Double(count - 3)), 5 * 60 * 1000) : 0
        prefs.authFailCount = count
        prefs.authLockUntil = until
        prefs.save()
        return until
    }

    static func clearFailures() {
        var prefs = Prefs.load()
        prefs.authFailCount = 0
        prefs.authLockUntil = 0
        prefs.unlockedAt = ISO8601DateFormatter().string(from: Date())
        prefs.save()
    }
}
