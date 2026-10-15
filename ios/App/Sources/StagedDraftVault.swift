import Foundation
import CryptoKit
import Security
import GitPilotCore

/// RC3 device-only staged-draft recovery: AES-256-GCM, file protection,
/// excluded from backup and account-scoped after decryption.
enum StagedDraftVault {
    enum VaultError: LocalizedError {
        case lostKey, invalidCiphertext, tooLarge
        var errorDescription: String? {
            switch self {
            case .lostKey: return "Draft encryption key is unavailable. Clear drafts before restarting."
            case .invalidCiphertext: return "Local drafts cannot be decrypted. Clear them before restarting."
            case .tooLarge: return "Local encrypted draft exceeds the storage limit."
            }
        }
    }

    private static let maxBytes = 6_000_000
    private static let associatedData = Data("gitpilot-staged-drafts-v1".utf8)
    private static var keyQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.gitpilot.local-drafts",
         kSecAttrAccount as String: "aes-gcm-key-v1"]
    }
    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GitPilot", isDirectory: true)
            .appendingPathComponent("staged-drafts-v1.enc")
    }

    private static func key(create: Bool) throws -> SymmetricKey? {
        var query = keyQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let bytes = result as? Data, bytes.count == 32 {
            return SymmetricKey(data: bytes)
        }
        if status != errSecItemNotFound { throw VaultError.lostKey }
        guard create else { return nil }
        let generated = SymmetricKey(size: .bits256)
        let bytes = generated.withUnsafeBytes { Data($0) }
        var item = keyQuery
        item[kSecValueData as String] = bytes
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw VaultError.lostKey }
        return generated
    }

    static func load(for login: String) throws -> [StagedFileEdit] {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let ciphertext = try Data(contentsOf: url)
        guard ciphertext.count <= maxBytes else { throw VaultError.tooLarge }
        guard let key = try key(create: false) else { throw VaultError.lostKey }
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            let plaintext = try AES.GCM.open(box, using: key, authenticating: associatedData)
            let envelope = try JSONDecoder().decode(StagedDraftEnvelope.self, from: plaintext)
            try envelope.validate(for: login)
            return envelope.edits
        } catch let validation as StagedDraftEnvelope.ValidationError {
            throw validation
        } catch {
            throw VaultError.invalidCiphertext
        }
    }

    static func save(for login: String, edits: [StagedFileEdit]) throws {
        if edits.isEmpty { try erase(); return }
        let envelope = try StagedDraftEnvelope(accountLogin: login, edits: edits)
        let plaintext = try JSONEncoder().encode(envelope)
        guard plaintext.count <= maxBytes else { throw VaultError.tooLarge }
        guard let key = try key(create: true) else { throw VaultError.lostKey }
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: associatedData)
        guard let ciphertext = box.combined, ciphertext.count <= maxBytes else { throw VaultError.tooLarge }
        let url = fileURL
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var backup = URLResourceValues()
        backup.isExcludedFromBackup = true
        var folder = directory
        try folder.setResourceValues(backup)
        try ciphertext.write(to: url, options: [.atomic, .completeFileProtection])
    }

    static func erase() throws {
        // Destroy the key before unlinking. An orphaned ciphertext is unreadable.
        let status = SecItemDelete(keyQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.lostKey
        }
        let url = fileURL
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
