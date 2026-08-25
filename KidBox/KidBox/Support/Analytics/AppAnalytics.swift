//
//  AppAnalytics.swift
//  KidBox
//

import Foundation
import FirebaseAnalytics

enum AppAnalytics {

    static func signupStarted(method: String) {
        Analytics.logEvent("signup_started", parameters: ["method": method])
    }

    static func signupCompleted(method: String) {
        Analytics.logEvent("signup_completed", parameters: ["method": method])
    }

    /// Tap su un provider OAuth (Google/Apple/Facebook): a differenza di
    /// `signupStarted`, questo scatta sempre, anche per un login di un utente
    /// già esistente — non si può sapere se è un nuovo account finché Firebase
    /// non risponde con `isNewUser`.
    static func loginAttempted(method: String) {
        Analytics.logEvent("login_attempted", parameters: ["method": method])
    }

    static func signupMethodSelected(method: String) {
        Analytics.logEvent("signup_method_selected", parameters: ["method": method])
    }

    static func preSignupScreenShown(screenName: String) {
        Analytics.logEvent("pre_signup_screen_shown", parameters: ["screen_name": screenName])
    }

    static func preSignupScreenDismissed(screenName: String) {
        Analytics.logEvent("pre_signup_screen_dismissed", parameters: ["screen_name": screenName])
    }

    static func onboardingStepShown(stepName: String, stepNumber: Int) {
        Analytics.logEvent("onboarding_step_shown", parameters: [
            "step_name": stepName,
            "step_number": stepNumber
        ])
    }

    static func onboardingStepCompleted(stepName: String) {
        Analytics.logEvent("onboarding_step_completed", parameters: ["step_name": stepName])
    }

    static func onboardingCompleted(totalDurationSeconds: Int) {
        Analytics.logEvent("onboarding_completed", parameters: ["total_duration_seconds": totalDurationSeconds])
    }

    static func onboardingAbandoned(lastStepSeen: String) {
        Analytics.logEvent("onboarding_abandoned", parameters: ["last_step_seen": lastStepSeen])
    }

    static func familyCreated() {
        Analytics.logEvent("family_created", parameters: nil)
    }

    static func onboardingInviteStepShown() {
        Analytics.logEvent("onboarding_invite_step_shown", parameters: nil)
    }

    static func onboardingInviteStepSkipped() {
        Analytics.logEvent("onboarding_invite_step_skipped", parameters: nil)
    }

    static func inviteGenerated() {
        Analytics.logEvent("invite_generated", parameters: nil)
    }

    static func inviteShared(channel: String) {
        Analytics.logEvent("invite_shared", parameters: ["channel": channel])
    }

    static func familyJoinAttempted() {
        Analytics.logEvent("family_join_attempted", parameters: nil)
    }

    static func familyJoined(vaultKeyAvailable: Bool) {
        Analytics.logEvent("family_joined", parameters: ["vault_key_available": vaultKeyAvailable])
    }

    static func familyJoinFailed(reason: String) {
        Analytics.logEvent("family_join_failed", parameters: ["reason": reason])
    }

    static func screenView(name: String) {
        Analytics.logEvent("screen_view", parameters: ["screen_name": name])
    }

    static func featureFirstUse(feature: String) {
        Analytics.logEvent("feature_first_use", parameters: ["feature": feature])
    }

    static func contentCreated(type: String) {
        Analytics.logEvent("content_created", parameters: ["content_type": type])
    }

    static func contentSharedRead(type: String) {
        Analytics.logEvent("content_shared_read", parameters: ["content_type": type])
    }

    static func aiPaywallShown(context: String) {
        Analytics.logEvent("ai_paywall_shown", parameters: ["context": context])
    }

    static func aiMessageSent(agentType: String, plan: String) {
        Analytics.logEvent("ai_message_sent", parameters: [
            "agent_type": agentType,
            "plan": plan
        ])
    }

    static func aiBriefingReceived() {
        Analytics.logEvent("ai_briefing_received", parameters: nil)
    }

    static func paywallShown(triggerFeature: String, planShown: String) {
        Analytics.logEvent("paywall_shown", parameters: [
            "trigger_feature": triggerFeature,
            "plan_shown": planShown
        ])
    }

    static func subscriptionStarted(plan: String, trial: Bool) {
        Analytics.logEvent("subscription_started", parameters: [
            "plan": plan,
            "trial": trial
        ])
    }

    static func appOpen(daysSinceInstall: Int, daysSinceLastOpen: Int) {
        Analytics.logEvent("app_open", parameters: [
            "days_since_install": daysSinceInstall,
            "days_since_last_open": daysSinceLastOpen
        ])
    }

    private static let installDateKey = "kb_appAnalytics_installDate"
    private static let lastOpenDateKey = "kb_appAnalytics_lastOpenDate"

    static func trackAppOpen() {
        let defaults = UserDefaults.standard
        let now = Date()
        let calendar = Calendar.current

        let installDate: Date
        if let stored = defaults.object(forKey: installDateKey) as? Date {
            installDate = stored
        } else {
            installDate = now
            defaults.set(now, forKey: installDateKey)
        }

        let lastOpenDate = defaults.object(forKey: lastOpenDateKey) as? Date ?? installDate
        defaults.set(now, forKey: lastOpenDateKey)

        let daysSinceInstall = calendar.dateComponents([.day], from: installDate, to: now).day ?? 0
        let daysSinceLastOpen = calendar.dateComponents([.day], from: lastOpenDate, to: now).day ?? 0
        appOpen(daysSinceInstall: daysSinceInstall, daysSinceLastOpen: daysSinceLastOpen)
    }
}
