//
//  WatchECardWidget.swift
//  WatchWidgetExtensions
//
//  Retained as an upgrade-safe placeholder for existing watch-face widgets.
//

import SwiftUI
import WidgetKit

struct WatchECardEntry: TimelineEntry {
    let date: Date
}

struct WatchECardProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchECardEntry {
        WatchECardEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchECardEntry) -> Void) {
        clearLegacyCache()
        completion(WatchECardEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchECardEntry>) -> Void) {
        clearLegacyCache()
        completion(
            Timeline(
                entries: [WatchECardEntry(date: Date())],
                policy: .never
            )
        )
    }

    private func clearLegacyCache() {
        guard let defaults = WidgetAppGroup.defaults else { return }
        defaults.removeObject(forKey: WidgetAppGroup.ecardBalanceKey)
        defaults.removeObject(forKey: WidgetAppGroup.ecardUpdateTimeKey)
        defaults.removeObject(forKey: WidgetAppGroup.ecardLoggedInKey)
    }
}

struct WatchECardWidget: Widget {
    let kind: String = "ECardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchECardProvider()) { _ in
            WatchECardWidgetView()
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("校园卡已停用")
        .description("此校园卡表盘组件已停用")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner,
        ])
    }
}

struct WatchECardWidgetView: View {
    var body: some View {
        Text("校园卡已停用")
            .font(.caption)
            .multilineTextAlignment(.center)
            .accessibilityLabel("校园卡组件已停用")
    }
}

#Preview("校园卡已停用", as: .accessoryCircular) {
    WatchECardWidget()
} timeline: {
    WatchECardEntry(date: Date())
}
