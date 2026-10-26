import Foundation
import Security

/// Shared secret the extension must present. Stored in ~/Library/Application Support/33rpm/token.
enum PairingToken {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("33rpm", isDirectory: true)
    }

    private static var file: URL { directory.appendingPathComponent("token") }

    static func loadOrCreate() -> String {
        if let existing = try? String(contentsOf: file, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), existing.count >= 32 {
            return existing
        }
        return regenerate()
    }

    @discardableResult
    static func regenerate() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: Data(token.utf8),
                                       attributes: [.posixPermissions: 0o600])
        return token
    }

    /// Compares without short-circuiting so timing doesn't leak how much of the token matched.
    static func matches(_ candidate: String, _ expected: String) -> Bool {
        let a = Array(candidate.utf8), b = Array(expected.utf8)
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }
}
