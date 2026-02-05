import Foundation
import Security

enum KeychainManager {
    private static let service = "com.ruban.notchi"
    private static let sessionKeyAccount = "claude-session-key"
    private static let orgIdAccount = "claude-org-id"
    private static let cookieAccount = "claude-cookie"

    static func save(sessionKey: String) -> Bool {
        save(value: sessionKey, account: sessionKeyAccount)
    }

    static func save(organizationId: String) -> Bool {
        save(value: organizationId, account: orgIdAccount)
    }

    static func save(cookie: String) -> Bool {
        save(value: cookie, account: cookieAccount)
    }

    static func getSessionKey() -> String? {
        get(account: sessionKeyAccount)
    }

    static func getOrganizationId() -> String? {
        get(account: orgIdAccount)
    }

    static func getCookie() -> String? {
        get(account: cookieAccount)
    }

    static func deleteCredentials() {
        delete(account: sessionKeyAccount)
        delete(account: orgIdAccount)
        delete(account: cookieAccount)
    }

    static var hasCredentials: Bool {
        getSessionKey() != nil && getOrganizationId() != nil
    }

    private static func save(value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
