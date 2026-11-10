import Foundation
import Security

enum SecretStore {
    static func set(_ value: String, for key: String) {
        let account = "ipa109.\(key)"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func get(_ key: String) -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: "ipa109.\(key)",
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }
}

struct UserConfig {
    var geminiKey: String { SecretStore.get("gemini") }
    var githubToken: String { SecretStore.get("github") }
    var githubOwner: String { UserDefaults.standard.string(forKey: "githubOwner") ?? "" }
    var githubRepo: String { UserDefaults.standard.string(forKey: "githubRepo") ?? "" }
    var githubBranch: String { UserDefaults.standard.string(forKey: "githubBranch") ?? "main" }
}
