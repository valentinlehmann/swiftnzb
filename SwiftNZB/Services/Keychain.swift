//
//  Keychain.swift
//  SwiftNZB
//
//  Thin wrapper over the Security framework for the two things worth storing there: server
//  passwords and the free-download counter. Entries are marked synchronizable so they ride along
//  with iCloud Keychain (matching the iCloud-KVS sync of the non-secret account metadata in
//  ServerStore).
//
//  The `service` parameter keeps the two uses in separate namespaces, so a counter key can never
//  collide with a server account's UUID.
//

import Foundation
import Security

enum Keychain {
    static let serverPasswordService = "de.valentinlehmann.swiftnzb.serverpassword"
    static let entitlementService = "de.valentinlehmann.swiftnzb.entitlement"

    static func setPassword(_ password: String, for account: String,
                            service: String = serverPasswordService) {
        let data = Data(password.utf8)
        // Replace any existing item — from the same service, or the add below fails as a duplicate.
        deletePassword(for: account, service: service)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func password(for account: String,
                         service: String = serverPasswordService) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(for account: String,
                               service: String = serverPasswordService) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
