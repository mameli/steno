import Foundation
import Security

/// Le chiavi API dei Profili, nel Portachiavi di macOS (mai su file o in UserDefaults).
enum Keychain {
    private static let service = "dev.mameli.steno"

    static func apiKey(for profile: UUID) -> String? {
        var query = baseQuery(profile)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Salva la chiave, o la cancella se è vuota. La chiave precedente resta finché la nuova
    /// non è salvata: se il salvataggio fallisce non si perdono entrambe.
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
            item[kSecAttrLabel as String] = "Steno: chiave API del Profilo"
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func deleteAPIKey(for profile: UUID) {
        SecItemDelete(baseQuery(profile) as CFDictionary)
    }

    private static func baseQuery(_ profile: UUID) -> [String: Any] {
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
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "codice \(status)"
        return "Portachiavi: \(message)"
    }
}
