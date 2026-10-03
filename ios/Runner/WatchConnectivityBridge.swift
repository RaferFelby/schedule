//
//  WatchConnectivityBridge.swift
//  Runner
//
//  iPhone → Apple Watch 日程列表同步。
//

import Foundation
import WatchConnectivity

private enum LegacyCredentialRevocationMessage {
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

    static func isAcknowledgement(_ payload: [String: Any]) -> Bool {
        payload[actionKey] as? String == acknowledgeAction &&
            (payload[versionKey] as? NSNumber)?.int64Value == version &&
            payload[requestIDKey] as? String == requestID
    }
}

private enum LegacyCredentialRevocationAppGroupKeys {
    static let requestedVersion = "legacyCredentialRevocationVersion"
    static let requestID = "legacyCredentialRevocationRequestID"
    static let acknowledgedVersion = "legacyCredentialRevocationAckVersion"
    static let acknowledgedRequestID = "legacyCredentialRevocationAckRequestID"
}

final class WatchConnectivityBridge: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityBridge()

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Records a credential-free Watch cleanup request in App Group storage.
    /// It remains pending until the Watch returns the matching versioned ack.
    func queueLegacyCredentialRevocation() {
        guard let defaults = appGroupDefaults else { return }
        let acknowledged = Int64(
            defaults.integer(forKey: LegacyCredentialRevocationAppGroupKeys.acknowledgedVersion)
        )
        guard acknowledged < LegacyCredentialRevocationMessage.version else { return }
        defaults.set(
            LegacyCredentialRevocationMessage.version,
            forKey: LegacyCredentialRevocationAppGroupKeys.requestedVersion
        )
        defaults.set(
            LegacyCredentialRevocationMessage.requestID,
            forKey: LegacyCredentialRevocationAppGroupKeys.requestID
        )
        if WCSession.default.activationState == .activated {
            push(payload: LegacyCredentialRevocationMessage.request)
        }
    }

    /// 从 App Group 读取日程缓存并推送到手表。不会读取校园卡状态或凭据。
    func syncFromAppGroup() {
        let defaults = appGroupDefaults
        var payload: [String: Any] = [:]
        if let flowData = defaults?.data(forKey: "flowList") {
            payload = [
                "flowList": flowData,
                "flowListBase64": flowData.base64EncodedString(),
                "flowRevision": Int64(defaults?.integer(forKey: "flowRevision") ?? 0),
            ]
        }
        if hasPendingCredentialRevocation(defaults: defaults) {
            payload.merge(LegacyCredentialRevocationMessage.request) { _, new in new }
        }
        if !payload.isEmpty {
            push(payload: payload)
        }
    }

    /// 同步日程 JSON（与 App Group 中 flowList 一致）。
    func syncFlowList(_ data: Data, revision: Int64 = 0) {
        push(payload: [
            "flowList": data,
            "flowListBase64": data.base64EncodedString(),
            "flowRevision": revision,
        ])
    }

    private func push(payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pending.merge(payload) { _, new in new }
            return
        }

        var context = session.applicationContext
        for (key, value) in payload {
            context[key] = value
        }
        if let flowData = payload["flowList"] as? Data {
            context["flowListBase64"] = flowData.base64EncodedString()
        }
        try? session.updateApplicationContext(context)

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(payload)
        }
    }

    private var pending: [String: Any] = [:]

    private var appGroupDefaults: UserDefaults? {
        #if DEBUG
        return UserDefaults(suiteName: "group.top.celechron.celechron.debug")
        #else
        return UserDefaults(suiteName: "group.top.celechron.celechron")
        #endif
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated, !pending.isEmpty else { return }
        let copy = pending
        pending.removeAll()
        push(payload: copy)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// Compatibility response for old watch versions. No credentials are read,
    /// no campus-card request is made, and no payment data is returned.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if acceptRevocationAcknowledgement(message) {
            replyHandler(["ok": true])
            return
        }
        replyHandler([
            "error": "featureDisabled",
            "retryable": false,
        ])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        _ = acceptRevocationAcknowledgement(userInfo)
    }

    private func hasPendingCredentialRevocation(defaults: UserDefaults?) -> Bool {
        guard let defaults else { return false }
        let requested = Int64(
            defaults.integer(forKey: LegacyCredentialRevocationAppGroupKeys.requestedVersion)
        )
        let acknowledged = Int64(
            defaults.integer(forKey: LegacyCredentialRevocationAppGroupKeys.acknowledgedVersion)
        )
        return requested >= LegacyCredentialRevocationMessage.version &&
            acknowledged < LegacyCredentialRevocationMessage.version &&
            defaults.string(forKey: LegacyCredentialRevocationAppGroupKeys.requestID) ==
                LegacyCredentialRevocationMessage.requestID
    }

    @discardableResult
    private func acceptRevocationAcknowledgement(_ payload: [String: Any]) -> Bool {
        guard LegacyCredentialRevocationMessage.isAcknowledgement(payload),
              let defaults = appGroupDefaults,
              defaults.string(forKey: LegacyCredentialRevocationAppGroupKeys.requestID) ==
                LegacyCredentialRevocationMessage.requestID
        else { return false }

        defaults.set(
            LegacyCredentialRevocationMessage.version,
            forKey: LegacyCredentialRevocationAppGroupKeys.acknowledgedVersion
        )
        defaults.set(
            LegacyCredentialRevocationMessage.requestID,
            forKey: LegacyCredentialRevocationAppGroupKeys.acknowledgedRequestID
        )
        defaults.removeObject(forKey: LegacyCredentialRevocationAppGroupKeys.requestedVersion)
        defaults.removeObject(forKey: LegacyCredentialRevocationAppGroupKeys.requestID)
        return true
    }
    #endif
}
