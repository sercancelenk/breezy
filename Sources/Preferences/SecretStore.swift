import Foundation
import Security

public protocol SecretStore: Sendable {
    func secret(for id: UUID) -> String?
    func setSecret(_ value: String?, for id: UUID) throws
}

public enum SecretError: Error { case keychain(OSStatus) }

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: String] = [:]

    public init() {}

    public func secret(for id: UUID) -> String? { lock.withLock { values[id] } }

    public func setSecret(_ value: String?, for id: UUID) throws {
        lock.withLock { values[id] = value }
    }
}

public struct KeychainSecretStore: SecretStore {
    private let service = "CleanerApp.ai"

    public init() {}

    private func base(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }

    public func secret(for id: UUID) -> String? {
        var q = base(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    public func setSecret(_ value: String?, for id: UUID) throws {
        SecItemDelete(base(id) as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var q = base(id)
        q[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretError.keychain(status) }
    }
}
