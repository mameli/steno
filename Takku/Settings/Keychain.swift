import Foundation
import Security

/// The Profiles' API keys, in the macOS Keychain (never in files or UserDefaults).
enum Keychain {
    private static let service = "app.takku.takku"

    static func apiKey(for profile: UUID) -> String? {
        var query = baseQuery(profile)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saves the key, or deletes it if empty. The previous key stays until the new one is
    /// saved: if saving fails, both are not lost.
    static func setAPIKey(_ key: String, for profile: UUID) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deleteAPIKey(for: profile)
            return
        }
        let data = Data(trimmed.utf8)
        var status = SecItemUpdate(baseQuery(profile) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery(profile)
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "Takku: Profile API key"
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func deleteAPIKey(for profile: UUID) {
        SecItemDelete(baseQuery(profile) as CFDictionary)
    }

    /// Copies a key saved under another service (Steno's), unless Takku already has one. macOS
    /// asks the user once whether Takku may read it: the item belongs to Steno.
    static func copyAPIKey(for profile: UUID, fromService oldService: String) {
        guard apiKey(for: profile) == nil else { return }
        var query = baseQuery(profile, service: oldService)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8)
        else { return }
        try? setAPIKey(key, for: profile)
    }

    private static func baseQuery(_ profile: UUID, service: String = service) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profile.uuidString,
        ]
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? String(localized: "code \(status)")
        return String(localized: "Keychain: \(message)")
    }
}
