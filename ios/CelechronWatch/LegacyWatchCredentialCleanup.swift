// Removes a credential left by older Watch app versions.

import Foundation
import Security

final class LegacyWatchCredentialCleanup {
    static let shared = LegacyWatchCredentialCleanup()

    private let service = "top.celechron.celechron.watch.ecard"
    private let account = "ecardCredential"
    private let lock = NSLock()
    private let deleteItem: ([CFString: Any]) -> OSStatus

    init(
        deleteItem: @escaping ([CFString: Any]) -> OSStatus = {
            SecItemDelete($0 as CFDictionary)
        }
    ) {
        self.deleteItem = deleteItem
    }

    /// Treats an absent item as success so startup cleanup can safely retry.
    @discardableResult
    func delete() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let status = deleteItem([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: false,
        ])
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// Versioned Watch-only credential cleanup. Payloads contain no account data.
enum LegacyCredentialRevocationMessage {
    static let actionKey = "action"
    static let versionKey = "credentialRevocationVersion"
    static let requestIDKey = "credentialRevocationRequestID"
    static let acknowledgeAction = "acknowledgeLegacyCredentialRevocation"
    static let requestAction = "revokeLegacyCredentials"
    static let version: Int64 = 1
    static let requestID = "legacy-credential-cleanup-v1"

    static var request: [String: Any] {
        [actionKey: requestAction, versionKey: version, requestIDKey: requestID]
    }

    static func isRequest(_ payload: [String: Any]) -> Bool {
        payload[actionKey] as? String == requestAction &&
            (payload[versionKey] as? NSNumber)?.int64Value == version &&
            payload[requestIDKey] as? String == requestID
    }

    static var acknowledgement: [String: Any] {
        [actionKey: acknowledgeAction, versionKey: version, requestIDKey: requestID]
    }

    static func isAcknowledgement(_ payload: [String: Any]) -> Bool {
        payload[actionKey] as? String == acknowledgeAction &&
            (payload[versionKey] as? NSNumber)?.int64Value == version &&
            payload[requestIDKey] as? String == requestID
    }
}

/// Testable idempotent boundary between a versioned phone request and the Watch keychain.
enum WatchLegacyCredentialRevocation {
    static func process(
        _ payload: [String: Any],
        processedVersion: Int64,
        deleteCredential: () -> Bool,
        persistVersion: (Int64) -> Void
    ) -> Bool {
        guard LegacyCredentialRevocationMessage.isRequest(payload) else { return false }
        if processedVersion < LegacyCredentialRevocationMessage.version {
            guard deleteCredential() else { return false }
            persistVersion(LegacyCredentialRevocationMessage.version)
        }
        return true
    }
}
