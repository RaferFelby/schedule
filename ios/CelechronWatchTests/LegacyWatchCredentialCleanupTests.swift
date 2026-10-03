import Foundation
import Security

@main
private enum LegacyWatchCredentialCleanupTests {
    private static var assertionCount = 0
    private static var failureCount = 0

    static func main() {
        testCredentialDeleteIsIdempotent()
        testLegacyCredentialRevocationIsVersionedAndIdempotent()

        if failureCount == 0 {
            print("✅ Watch credential cleanup: \(assertionCount) assertions passed")
        } else {
            print("❌ Watch credential cleanup: \(failureCount) of \(assertionCount) assertions failed")
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func testCredentialDeleteIsIdempotent() {
        var statuses = [errSecSuccess, errSecItemNotFound, errSecInteractionNotAllowed]
        var deleteCount = 0
        let cleanup = LegacyWatchCredentialCleanup { _ in
            deleteCount += 1
            return statuses.removeFirst()
        }

        expect(cleanup.delete(), "deleting an existing credential succeeds")
        expect(cleanup.delete(), "missing credential is an idempotent success")
        expect(!cleanup.delete(), "Keychain deletion errors remain retryable")
        expect(deleteCount == 3, "each cleanup call reaches Keychain")
    }

    private static func testLegacyCredentialRevocationIsVersionedAndIdempotent() {
        let request = LegacyCredentialRevocationMessage.request
        let encoded = try? JSONSerialization.data(withJSONObject: request)
        let serialized = encoded.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        expect(LegacyCredentialRevocationMessage.isRequest(request), "versioned request is recognized")
        expect(LegacyCredentialRevocationMessage.isAcknowledgement(
            LegacyCredentialRevocationMessage.acknowledgement
        ), "versioned acknowledgement is recognized")
        expect(request.count == 3, "request contains only action, version, and request ID")
        expect(
            !serialized.contains("password") && !serialized.contains("account") && !serialized.contains("auth"),
            "request contains no credential fields"
        )

        var persistedVersion: Int64 = 0
        var deleteCount = 0
        let failed = WatchLegacyCredentialRevocation.process(
            request,
            processedVersion: 0,
            deleteCredential: { deleteCount += 1; return false },
            persistVersion: { persistedVersion = $0 }
        )
        expect(!failed && persistedVersion == 0, "failed deletion is not acknowledged or persisted")

        let retried = WatchLegacyCredentialRevocation.process(
            request,
            processedVersion: persistedVersion,
            deleteCredential: { deleteCount += 1; return true },
            persistVersion: { persistedVersion = $0 }
        )
        expect(retried && persistedVersion == LegacyCredentialRevocationMessage.version,
               "successful retry records the request version")

        let duplicate = WatchLegacyCredentialRevocation.process(
            request,
            processedVersion: persistedVersion,
            deleteCredential: { deleteCount += 1; return false },
            persistVersion: { _ in }
        )
        expect(duplicate && deleteCount == 2, "duplicate request is acknowledged without deleting again")
        expect(!WatchLegacyCredentialRevocation.process(
            ["action": "revokeLegacyCredentials", "credentialRevocationVersion": 99],
            processedVersion: 0,
            deleteCredential: { deleteCount += 1; return true },
            persistVersion: { _ in }
        ), "unrecognized version or request ID is ignored")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertionCount += 1
        if !condition() {
            failureCount += 1
            print("FAIL: \(message)")
        }
    }
}
