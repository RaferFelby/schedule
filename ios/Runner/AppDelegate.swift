import Flutter
import UIKit
import WidgetKit
import flutter_local_notifications

extension FlutterError: Error {}
private class FlowMessengerImplementation: FlowMessenger {
    func transfer(data: FlowMessage) async throws -> Bool {
#if DEBUG
        let userDefaults = UserDefaults(suiteName: "group.top.celechron.celechron.debug")
#else
        let userDefaults = UserDefaults(suiteName: "group.top.celechron.celechron")
#endif
        let periods: [[String: Any]] = data.flowListDto.compactMap { item in
            guard let item else { return nil }
            var value: [String: Any] = [
                "uid": item.uid,
                "type": item.type.rawValue,
                "startTime": item.startTime,
                "endTime": item.endTime,
            ]
            if let name = item.name { value["name"] = name }
            if let location = item.location { value["location"] = location }
            return value
        }
        guard let encoded = try? JSONSerialization.data(withJSONObject: periods) else {
            return false
        }
        userDefaults?.set(encoded, forKey: "flowList")
        userDefaults?.set(data.revision, forKey: "flowRevision")
        WatchConnectivityBridge.shared.syncFlowList(encoded, revision: data.revision)
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: "FlowWidget")
        }
        return true
    }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    private var pdfTimetableImporter: PdfTimetableImporter?
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Notification MethodChannel
        UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
        FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
            GeneratedPluginRegistrant.register(with: registry)
        }

        // Apple Watch 数据同步
        WatchConnectivityBridge.shared.queueLegacyCredentialRevocation()
        WatchConnectivityBridge.shared.activate()
        WatchConnectivityBridge.shared.syncFromAppGroup()
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: "ECardWidget")
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

        // Flow widget MethodChannel
        FlowMessengerSetup.setUp(binaryMessenger: engineBridge.applicationRegistrar.messenger(), api: FlowMessengerImplementation())
        pdfTimetableImporter = PdfTimetableImporter(messenger: engineBridge.applicationRegistrar.messenger())

    }
}
