import Foundation
import Security

public enum AIProvider: String, Sendable, CaseIterable { case openAI, anthropic }

public protocol AIKeyStore: AnyObject, Sendable {
    func key(for provider: AIProvider) -> String?
    func set(_ value: String, for provider: AIProvider)
}

/// Non-persistent store for tests and previews.
public final class InMemoryAIKeyStore: AIKeyStore, @unchecked Sendable {
    private var store: [AIProvider: String] = [:]
    public init() {}
    public func key(for provider: AIProvider) -> String? { store[provider] }
    public func set(_ value: String, for provider: AIProvider) {
        if value.isEmpty { store[provider] = nil } else { store[provider] = value }
    }
}

/// Keychain-backed store. One generic-password item per provider.
public final class KeychainAIKeyStore: AIKeyStore, @unchecked Sendable {
    private let service: String
    public init(service: String = "com.blearred.cuelistcompiler.keys") { self.service = service }

    public func key(for provider: AIProvider) -> String? {
        var q = baseQuery(provider)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty
        else { return nil }
        return s
    }

    public func set(_ value: String, for provider: AIProvider) {
        SecItemDelete(baseQuery(provider) as CFDictionary)
        guard !value.isEmpty else { return }
        var q = baseQuery(provider)
        q[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(q as CFDictionary, nil)
        #if !targetEnvironment(simulator)
        assert(status == errSecSuccess, "KeychainAIKeyStore.set: SecItemAdd failed (\(status))")
        #endif
    }

    private func baseQuery(_ provider: AIProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue,
         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
    }
}
