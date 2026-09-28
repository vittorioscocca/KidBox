//
//  ProTrialBanner.swift
//  KidBox
//
//  Banner in Home durante la prova Pro: quanti giorni restano e un tocco per
//  vedere i piani. La prova la concede il server (functions/proTrial.js).
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
