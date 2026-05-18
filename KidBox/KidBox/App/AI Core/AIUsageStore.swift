//
//  AIUsageStore.swift
//  KidBox
//
//  Contatore conmotione famiglia (ai_usage) aggiornato dopo ogni chiamata AI.
//

import Foundation
import Combine

extension Notification.Name {
    static let aiUsageDidChange = Notification.Name("kb.aiUsageDidChange")
}

@MainActor
final class AIUsageStore: ObservableObject {

    static let shared = AIUsageStore()

    @Published private(set) var usageToday: Int = 0
    @Published private(set) var dailyLimit: Int = 0

    private init() {}

    func apply(usageToday: Int, dailyLimit: Int) {
        self.usageToday = usageToday
        self.dailyLimit = dailyLimit
        NotificationCenter.default.post(
            name: .aiUsageDidChange,
            object: nil,
            userInfo: [
                "usageToday": usageToday,
                "dailyLimit": dailyLimit,
            ]
        )
    }
}
