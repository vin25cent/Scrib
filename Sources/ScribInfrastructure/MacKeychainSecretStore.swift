#if os(macOS)
import Foundation
import Security
import ScribApplication
import ScribDomain

public actor MacKeychainSecretStore: AISecretStoring {
    private let service: String

    public init(service: String = "com.vin25cent.scrib.api-keys") {
        self.service = service
    }

    public func hasSecret(for provider: AIProviderID) throws -> Bool {
        try readSecret(for: provider) != nil
    }

    public func readSecret(for provider: AIProviderID) throws -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw keychainError(status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func saveSecret(_ secret: String, for provider: AIProviderID) throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            throw NSError(
                domain: "Scrib.AISecret",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "La clé API est vide."]
            )
        }
        let query = baseQuery(provider)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw keychainError(updateStatus) }

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw keychainError(addStatus) }
    }

    public func deleteSecret(for provider: AIProviderID) throws {
        let status = SecItemDelete(baseQuery(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status)
        }
    }

    private func baseQuery(_ provider: AIProviderID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecAttrSynchronizable as String: false
        ]
    }

    private func keychainError(_ status: OSStatus) -> NSError {
        NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "Erreur du Trousseau macOS"]
        )
    }
}
#endif
