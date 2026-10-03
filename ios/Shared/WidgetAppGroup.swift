//
//  WidgetAppGroup.swift
//  Shared app-group identifiers for the iOS widget extension.
//

import Foundation

enum WidgetAppGroup {
    static var suiteName: String {
        #if DEBUG
        return "group.top.celechron.celechron.debug"
        #else
        return "group.top.celechron.celechron"
        #endif
    }

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static let ecardBalanceKey = "ecardBalance"
    static let ecardUpdateTimeKey = "ecardUpdateTime"
    static let ecardLoggedInKey = "ecardLoggedIn"
}
