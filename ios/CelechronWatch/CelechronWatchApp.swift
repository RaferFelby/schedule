//
//  CelechronWatchApp.swift
//  CelechronWatch
//
//  手表端宿主 App：首页入口 + 日程/校园卡停用深链 + 地点导航
//

import SwiftUI
import WatchKit
import WatchConnectivity
import WidgetKit

@main
struct CelechronWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var appDelegate
    @State private var path = NavigationPath()

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                WatchHomeView()
                    .navigationDestination(for: WatchDeepLink.Destination.self) { dest in
                        switch dest {
                        case .flow:
                            WatchFlowPage()
                        case .ecard:
                            WatchECardDisabledPage()
                        }
                    }
            }
            .onOpenURL { url in
                if let dest = WatchDeepLink.destination(from: url) {
                    // 重置栈后推入目标页，避免多层叠加
                    path = NavigationPath()
                    path.append(dest)
                }
            }
        }
    }
}

// MARK: - Home

struct WatchHomeView: View {
    var body: some View {
        // 单屏布局：Logo 与系统时间同行；入口用系统图标，不展示具体余额/课程
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: WatchDeepLink.Destination.flow) {
                HomeCard(icon: "calendar", title: "日程")
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开今日日程列表")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // 与系统时间同行：约 26pt，避免过小模糊或过大挤占
                AppLogoView()
                    .frame(width: 26, height: 26)
                    .accessibilityLabel("Celechron")
            }
        }
    }
}

private struct AppLogoView: View {
    var body: some View {
        // 优先 Asset Catalog（正确 @1x/@2x/@3x），避免误用松散 PNG 的错误点密度
        Image("AppLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .clipShape(Circle())
    }
}

/// 首页入口：系统 SF Symbol + 标题，不展示具体业务数据
private struct HomeCard: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .frame(width: 28)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .contentShape(Rectangle())
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Flow Page

struct WatchFlowPage: View {
    @State private var flows: [Flow] = []
    @State private var remainingToday = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            List {
                if flows.isEmpty {
                    Section {
                        VStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                                .symbolRenderingMode(.hierarchical)
                            Text("今日无事可做")
                                .font(.headline)
                            Text("好好休息")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(flows) { flow in
                            FlowCard(date: context.date, flow: flow)
                                .listRowInsets(EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2))
                                .listRowBackground(Color.clear)
                        }
                    } header: {
                        if remainingToday > 0 {
                            Text("今日还有 \(remainingToday) 项")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.automatic)
        }
        .navigationTitle("日程")
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: WatchDataSync.didUpdateNotification)) { _ in
            reload()
        }
    }

    private func reload() {
        let data = WidgetAppGroup.defaults?.data(forKey: WidgetAppGroup.flowListKey) ?? Data()
        let flowList = (try? JSONDecoder().decode([PeriodDto?].self, from: data)) ?? []
        let now = Date()
        let nowTs = now.timeIntervalSince1970

        var ongoing: [Flow] = []
        var upcoming: [Flow] = []
        for dto in flowList.compactMap({ $0 }) {
            guard let flow = Flow(from: dto) else { continue }
            let end = TimeInterval(dto.endTime)
            let start = TimeInterval(dto.startTime)
            if end <= nowTs { continue }
            if start <= nowTs {
                ongoing.append(flow)
            } else if start - nowTs <= 172_800 {
                upcoming.append(flow)
            }
        }
        ongoing.sort { $0.endTime < $1.endTime }
        upcoming.sort { $0.startTime < $1.startTime }
        flows = ongoing + upcoming

        remainingToday = upcoming.filter {
            Calendar.current.isDate($0.startTime, inSameDayAs: now)
        }.count
    }
}

/// 单条日程卡片：色条 + 标题/地点(可点导航) + 倒计时
private struct FlowCard: View {
    let date: Date
    let flow: Flow
    @Environment(\.openURL) private var openURL

    private var hasBegun: Bool {
        date.compare(flow.startTime) != .orderedAscending
    }

    private var minutesLeft: Int {
        let reference = hasBegun ? flow.endTime : flow.startTime
        return max(0, Int(ceil(date.distance(to: reference) / 60)))
    }

    private var countdownText: String {
        let m = minutesLeft
        if m >= 60 {
            return String(format: "%d:%02d", m / 60, m % 60)
        }
        return "\(m) 分"
    }

    private var statusLabel: String {
        hasBegun ? "后结束" : "后开始"
    }

    private var accent: Color {
        hasBegun ? .blue : .orange
    }

    private var progress: Double {
        guard hasBegun else { return 0 }
        let total = flow.endTime.timeIntervalSince(flow.startTime)
        guard total > 0 else { return 0 }
        let done = date.timeIntervalSince(flow.startTime)
        return min(1, max(0, done / total))
    }

    private var timeRangeText: String {
        "\(flow.startTime.HHmm24())–\(flow.endTime.HHmm24())"
    }

    private var locationText: String {
        flow.location ?? "无地点"
    }

    private var canNavigate: Bool {
        WatchDeepLink.mapsURL(for: locationText) != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 4)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(flow.name ?? "未命名日程")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                // 地点：可点击跳转 Apple 地图步行导航（热区 ≥ 44pt）
                Button {
                    if let url = WatchDeepLink.mapsURL(for: locationText) {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: canNavigate ? "location.fill" : "location")
                            .font(.caption2)
                        Text(locationText)
                            .font(.caption2)
                            .lineLimit(1)
                        if canNavigate {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.system(size: 9))
                        }
                    }
                    .foregroundStyle(canNavigate ? Color.accentColor : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canNavigate)
                .accessibilityLabel(canNavigate ? "导航至\(locationText)" : locationText)
                .accessibilityHint(canNavigate ? "在地图中打开步行路线" : "")

                Text(timeRangeText)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(countdownText)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(accent)
                        .monospacedDigit()
                    Text(statusLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if hasBegun {
                    ProgressView(value: progress)
                        .tint(accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(flow.name ?? "未命名日程")，\(countdownText)\(statusLabel)，\(timeRangeText)")
    }
}

// MARK: - Legacy ECard Deep Link

/// Old complication and app links land here without opening the retired pay flow.
struct WatchECardDisabledPage: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "creditcard")
                .font(.title2)
            Text("校园卡功能已停用")
                .font(.headline)
            Text("请使用学校官方渠道完成支付。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
        .navigationTitle("校园卡")
    }
}

// MARK: - App Delegate / WatchConnectivity

final class WatchAppDelegate: NSObject, WKApplicationDelegate, WCSessionDelegate {
    func applicationDidFinishLaunching() {
        clearLegacyECardCredential()
        clearLegacyECardCache()
        activateSession()
        WidgetCenter.shared.reloadTimelines(ofKind: "ECardWidget")
        #if DEBUG
        removeLegacyPreviewDataIfNeeded()
        #endif
    }

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func clearLegacyECardCache() {
        guard let defaults = WidgetAppGroup.defaults else { return }
        defaults.removeObject(forKey: WidgetAppGroup.ecardBalanceKey)
        defaults.removeObject(forKey: WidgetAppGroup.ecardUpdateTimeKey)
        defaults.removeObject(forKey: WidgetAppGroup.ecardLoggedInKey)
    }

    private func clearLegacyECardCredential() {
        guard !LegacyWatchCredentialCleanup.shared.delete() else { return }
        NSLog("[Celechron] Legacy campus-card credential cleanup failed; will retry on next launch.")
    }

    #if DEBUG
    private func removeLegacyPreviewDataIfNeeded() {
        let defaults = WidgetAppGroup.defaults
        let migrationKey = "removedRuntimePreviewDataV1"
        guard defaults?.bool(forKey: migrationKey) != true else { return }

        // Earlier Debug builds wrote sample schedules into persistent App Group
        // storage. Clear that known synthetic flow once during the upgrade.
        if let data = defaults?.data(forKey: WidgetAppGroup.flowListKey),
           let periods = try? JSONDecoder().decode([PeriodDto?].self, from: data),
           periods.compactMap({ $0?.uid }).contains(where: { $0.hasPrefix("preview-") })
        {
            defaults?.removeObject(forKey: WidgetAppGroup.flowListKey)
        }
        defaults?.set(true, forKey: migrationKey)
        WidgetCenter.shared.reloadAllTimelines()
        WatchDataSync.notifyUpdated()
    }
    #endif

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if activationState == .activated {
            applyApplicationContext(session.receivedApplicationContext)
            DispatchQueue.main.async {
                WatchDataSync.notifyUpdated()
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            WatchDataSync.notifyUpdated()
        }
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        applyApplicationContext(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        applyApplicationContext(userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleMessage(message, replyHandler: nil)
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        handleMessage(message, replyHandler: replyHandler)
    }

    private func handleMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?
    ) {
        if LegacyCredentialRevocationMessage.isRequest(message) {
            guard let acknowledgement = processLegacyCredentialRevocation(message) else {
                replyHandler?(["error": "credentialCleanupFailed", "retryable": true])
                return
            }
            replyHandler?(acknowledgement)
            return
        }
        if message["action"] != nil {
            replyHandler?(["error": "featureDisabled", "retryable": false])
            return
        }
        applyApplicationContext(message)
        replyHandler?(["ok": true])
    }

    private func applyApplicationContext(_ context: [String: Any]) {
        guard !context.isEmpty else { return }
        _ = processLegacyCredentialRevocation(context)
        guard context["flowList"] != nil || context["flowListBase64"] != nil else {
            return
        }
        let defaults = WidgetAppGroup.defaults

        let incomingRevision = (context["flowRevision"] as? NSNumber)?.int64Value ?? 0
        let currentRevision = Int64(defaults?.integer(forKey: WidgetAppGroup.flowRevisionKey) ?? 0)
        guard incomingRevision >= currentRevision else { return }

        if let flowData = context["flowList"] as? Data {
            defaults?.set(flowData, forKey: WidgetAppGroup.flowListKey)
        } else if let flowBase64 = context["flowListBase64"] as? String,
                  let flowData = Data(base64Encoded: flowBase64)
        {
            defaults?.set(flowData, forKey: WidgetAppGroup.flowListKey)
        }
        if context["flowList"] != nil || context["flowListBase64"] != nil {
            defaults?.set(incomingRevision, forKey: WidgetAppGroup.flowRevisionKey)
        }

        WidgetCenter.shared.reloadAllTimelines()
        DispatchQueue.main.async {
            WatchDataSync.notifyUpdated()
        }
    }

    private func processLegacyCredentialRevocation(
        _ payload: [String: Any]
    ) -> [String: Any]? {
        guard LegacyCredentialRevocationMessage.isRequest(payload) else { return nil }
        let defaults = UserDefaults.standard
        let processedVersionKey = "legacyCredentialRevocationProcessedVersion"
        let processedVersion = Int64(defaults.integer(forKey: processedVersionKey))
        let processed = WatchLegacyCredentialRevocation.process(
            payload,
            processedVersion: processedVersion,
            deleteCredential: { LegacyWatchCredentialCleanup.shared.delete() },
            persistVersion: { defaults.set($0, forKey: processedVersionKey) }
        )
        guard processed else {
            NSLog("[Celechron] Watch credential revocation failed; awaiting retry.")
            return nil
        }
        let acknowledgement = LegacyCredentialRevocationMessage.acknowledgement
        WCSession.default.transferUserInfo(acknowledgement)
        return acknowledgement
    }
}
