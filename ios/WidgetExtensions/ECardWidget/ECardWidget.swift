//
//  ECardWidget.swift
//  WidgetExtensions
//
//  Retained as an upgrade-safe placeholder for existing Home Screen widgets.
//

import SwiftUI
import WidgetKit

struct ECardEntry: TimelineEntry {
    let date: Date
}

struct ECardWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ECardEntry {
        ECardEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (ECardEntry) -> Void) {
        clearLegacyCache()
        completion(ECardEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ECardEntry>) -> Void) {
        clearLegacyCache()
        let entry = ECardEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func clearLegacyCache() {
        guard let defaults = WidgetAppGroup.defaults else { return }
        defaults.removeObject(forKey: WidgetAppGroup.ecardBalanceKey)
        defaults.removeObject(forKey: WidgetAppGroup.ecardUpdateTimeKey)
        defaults.removeObject(forKey: WidgetAppGroup.ecardLoggedInKey)
    }
}

struct ECardWidget: Widget {
    let kind: String = "ECardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ECardWidgetProvider()) { _ in
            ECardWidgetView()
                .widgetBackground(Color(UIColor.tertiarySystemFill))
        }
        .supportedFamilies([.systemSmall])
    }
}

struct ECardWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "creditcard")
                Text("校园卡")
                    .font(.footnote)
                    .bold()
            }

            Spacer(minLength: 0)

            Text("校园卡组件已停用")
                .font(.headline)
                .multilineTextAlignment(.leading)
                .accessibilityLabel("校园卡组件已停用")

            Spacer(minLength: 0)
        }
        .padding()
    }
}

@available(iOS 18.0, *)
#Preview(as: .systemSmall) {
    ECardWidget()
} timeline: {
    ECardEntry(date: Date())
}
