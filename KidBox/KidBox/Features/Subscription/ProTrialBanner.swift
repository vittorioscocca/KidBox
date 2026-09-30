//
//  ProTrialBanner.swift
//  KidBox
//
//  Banner in Home durante la prova Pro: quanti giorni restano e un tocco per
//  vedere i piani. Sotto, la card con il pulsante che la attiva. La prova la
//  concede il server (functions/proTrial.js).
//

import SwiftUI

struct ProTrialBanner: View {
    let daysLeft: Int
    let onTap: () -> Void

    private let tint = Color(red: 0.35, green: 0.6, blue: 0.85)

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "star.circle.fill")
                    .font(.title2)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text("Spazio in più, pianificatori e assistente AI sono sbloccati. Nessuna carta richiesta.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private var title: String {
        daysLeft == 1
            ? NSLocalizedString("Pro incluso: ultimo giorno", comment: "Home banner, last day of Pro trial")
            : String(format: NSLocalizedString("Pro incluso: ancora %d giorni", comment: "Home banner during Pro trial (%d = days left)"), daysLeft)
    }
}

/// Offerta della prova Pro, in Spazio e nel paywall. Compare solo se il server
/// dice che la prova spetta (`KBSubscriptionManager.showsTrialCard`): la prova
/// non parte più da sola.
/// - al proprietario: pulsante «Prova Pro per N giorni»;
/// - agli altri membri, se il proprietario può ancora attivarla: «Chiedi di
///   attivarla», che gli manda una push.
/// Il titolo cambia con l'origine (`triggerFeature`): chi arriva dai messaggi
/// AI finiti o da un pianificatore bloccato legge la cosa che voleva fare.
struct ProTrialOfferCard: View {
    let triggerFeature: String

    @EnvironmentObject private var subscriptionManager: KBSubscriptionManager

    private let tint = Color(red: 0.35, green: 0.6, blue: 0.85)

    /// Da dove arriva l'utente, per il titolo della card.
    private enum Origin {
        case aiLimit, mealPlan, fitnessPlan, travel, other

        init(_ trigger: String) {
            switch trigger {
            case "ai_lock", "ai_chat_lock": self = .aiLimit
            case "meal_plan_lock":          self = .mealPlan
            case "fitness_plan_lock":       self = .fitnessPlan
            case "travel_lock":             self = .travel
            default:
                self = trigger.hasPrefix("ai_upgrade_") ? .aiLimit : .other
            }
        }
    }

    var body: some View {
        if let days = subscriptionManager.trialOfferDays {
            card(days: days, isOwner: true)
        } else if let days = subscriptionManager.trialAskOwnerDays {
            card(days: days, isOwner: false)
        }
    }

    private func card(days: Int, isOwner: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "star.circle.fill")
                    .font(.title2)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title(days: days))
                        .font(.subheadline.bold())
                    Text(isOwner ? ownerBody(days: days) : memberBody(days: days))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if isOwner {
                actionButton(
                    label: String(format: NSLocalizedString("Prova Pro per %d giorni", comment: "Button that starts the Pro trial (%d = trial days)"), days),
                    busy: subscriptionManager.isStartingTrial
                ) {
                    Task { await subscriptionManager.startTrial(triggerFeature: triggerFeature) }
                }
            } else if subscriptionManager.trialOwnerAsked {
                Label(NSLocalizedString("Richiesta inviata", comment: "Pro trial request already sent to the family owner"), systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                actionButton(
                    label: NSLocalizedString("Chiedi di attivarla", comment: "Button: ask the family owner to start the Pro trial"),
                    busy: subscriptionManager.isAskingOwner
                ) {
                    Task { await subscriptionManager.askOwnerForTrial() }
                }
            }
        }
        .padding(14)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .alert("Prova Pro", isPresented: .init(
            get: { subscriptionManager.trialStartError != nil },
            set: { if !$0 { subscriptionManager.clearTrialStartError() } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(subscriptionManager.trialStartError ?? "")
        }
        .alert("Prova Pro", isPresented: .init(
            get: { subscriptionManager.trialAskOwnerMessage != nil },
            set: { if !$0 { subscriptionManager.clearTrialAskOwnerMessage() } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(subscriptionManager.trialAskOwnerMessage ?? "")
        }
    }

    private func actionButton(label: String, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if busy {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Text(label)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func title(days: Int) -> String {
        switch Origin(triggerFeature) {
        case .aiLimit:
            return NSLocalizedString("Hai usato i messaggi AI gratuiti", comment: "Pro trial card title when the free AI messages are used up")
        case .mealPlan:
            return NSLocalizedString("Il piano alimentare è incluso nella prova Pro", comment: "Pro trial card title from the meal plan lock")
        case .fitnessPlan:
            return NSLocalizedString("Il piano fitness è incluso nella prova Pro", comment: "Pro trial card title from the fitness plan lock")
        case .travel:
            return NSLocalizedString("Gli itinerari di viaggio sono inclusi nella prova Pro", comment: "Pro trial card title from the travel plan lock")
        case .other:
            return String(format: NSLocalizedString("Prova Pro gratis per %d giorni", comment: "Pro trial offer title (%d = trial days)"), days)
        }
    }

    private func ownerBody(days: Int) -> String {
        switch Origin(triggerFeature) {
        case .aiLimit:
            return String(format: NSLocalizedString("Attiva la prova Pro: altri %1$d messaggi e tutto il Pro per %2$d giorni, senza carta e senza rinnovo.", comment: "Pro trial card body after the free AI messages (%1$d = AI messages in the trial, %2$d = trial days)"), subscriptionManager.trialAILimit, days)
        case .mealPlan, .fitnessPlan, .travel:
            return String(format: NSLocalizedString("Attivala ora: %d giorni di Pro per tutta la famiglia, senza carta e senza rinnovo. Dopo torni al Free e i tuoi dati restano.", comment: "Pro trial card body from a Pro-only planner (%d = trial days)"), days)
        case .other:
            return String(format: NSLocalizedString("Spazio in più, pianificatori e assistente AI per tutta la famiglia. Senza carta e senza rinnovo: dopo %d giorni torni al Free e i tuoi dati restano.", comment: "Pro trial offer description (%d = trial days)"), days)
        }
    }

    private func memberBody(days: Int) -> String {
        String(format: NSLocalizedString("La prova gratuita la attiva chi ha creato la famiglia: %d giorni di Pro per tutti, senza carta. Puoi chiederlo con un tocco, riceverà una notifica.", comment: "Pro trial card body for a member who is not the family owner (%d = trial days)"), days)
    }
}
