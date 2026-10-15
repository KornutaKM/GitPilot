import Foundation
import Security
import GitPilotCore

/// Migrated RC3 Keychain storage. Credentials are never written to UserDefaults
/// or application snapshots. ThisDeviceOnly prevents backup/device-transfer leaks.
enum OAuthTokenStore {
    private static var selector: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.gitpilot.github.oauth",
         kSecAttrAccount as String: "github-user-credentials"]
    }

    enum StoreError: LocalizedError {
        case invalidCredentials
        case keychainFailure(OSStatus)
        var errorDescription: String? {
            switch self {
            case .invalidCredentials: return "Stored GitHub session is invalid. Sign in again."
            case .keychainFailure: return "Secure iOS credential storage is unavailable."
            }
        }
    }

    static func read() throws -> OAuthCredentials? {
        var query = selector
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw StoreError.keychainFailure(status)
        }
        guard let credential = try? JSONDecoder().decode(OAuthCredentials.self, from: data),
              !credential.accessToken.isEmpty, credential.accessToken.utf8.count <= 4096 else {
            try remove()
            throw StoreError.invalidCredentials
        }
        return credential
    }

    static func save(_ credentials: OAuthCredentials) throws {
        guard !credentials.accessToken.isEmpty,
              credentials.accessToken.utf8.count <= 4096,
              credentials.refreshToken == nil || !(credentials.refreshToken?.isEmpty ?? true) else {
            throw StoreError.invalidCredentials
        }
        let data = try JSONEncoder().encode(credentials)
        let status = SecItemUpdate(selector as CFDictionary,
            [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw StoreError.keychainFailure(status) }
        var item = selector
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw StoreError.keychainFailure(added) }
    }

    static func remove() throws {
        let status = SecItemDelete(selector as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychainFailure(status)
        }
    }
}
