//
//  ClinicalRecordSectionDetailSheet.swift
//  KidBox
//

import SwiftUI

struct ClinicalRecordSectionDetailSheet: View {

    let section: ClinicalRecordSection
    let area: ClinicalRecordReportArea?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let status = section.overallStatus ?? area?.overallStatus {
                        statusBadge(status)
                    }

                    if let narrative = area?.analisiNarrativa, !narrative.isEmpty {
                        contentCard(
                            title: refertoSynthesisTitle(for: section.id),
                            text: narrative
                        )
                    } else if let trend = area?.trendNarrative, !trend.isEmpty {
                        trendCard(title: "Andamento nel tempo", text: trend, tint: section.tintColor)
                    }

                    if let params = area?.parameters, !params.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Parametri monitorati")
                                .font(.headline)
                            ForEach(params) { param in
                                ClinicalRecordParameterSparkline(parameter: param, tint: section.tintColor)
                            }
                        }
                    }

                    if let area, !area.narrative.isEmpty {
                        contentCard(title: timelineTitle(for: section.id), text: area.narrative)
                    } else if !section.highlights.isEmpty {
                        contentCard(
                            title: "Dettaglio",
                            text: section.highlights.map { "• \($0)" }.joined(separator: "\n")
                        )
                    }

                    Text("Le informazioni sono estratte dai referti in archivio. Non sostituiscono il parere del medico curante.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding(16)
            }
            .background(KBTheme.background(colorScheme).ignoresSafeArea())
            .navigationTitle(section.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }

    private func refertoSynthesisTitle(for sectionId: String) -> LocalizedStringKey {
        switch sectionId {
        case ClinicalRecordTopicBuilder.TopicId.cardiology.rawValue,
             ClinicalRecordTopicBuilder.TopicId.urology.rawValue:
            return "Sintesi dai referti"
        default:
            return "Sintesi andamento"
        }
    }

    private func timelineTitle(for sectionId: String) -> LocalizedStringKey {
        switch sectionId {
        case ClinicalRecordTopicBuilder.TopicId.cardiology.rawValue,
             ClinicalRecordTopicBuilder.TopicId.urology.rawValue:
            return "Referti nel tempo"
        default:
            return "Cronologia visite ed esami"
        }
    }

    private func statusBadge(_ status: ClinicalOverallStatus) -> some View {
        HStack(spacing: 8) {
            Text(status.emoji)
            Text(status.badgeLabel)
                .font(.subheadline.bold())
        }
        .foregroundStyle(statusColor(status))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(statusColor(status).opacity(0.12))
        )
    }

    private func statusColor(_ status: ClinicalOverallStatus) -> Color {
        switch status {
        case .stabile: return Color(red: 0.18, green: 0.62, blue: 0.42)
        case .migliorato: return Color(red: 0.17, green: 0.49, blue: 0.72)
        case .peggiorato, .attenzione: return Color(red: 0.84, green: 0.23, blue: 0.23)
        case .daMonitorare: return Color(red: 0.83, green: 0.53, blue: 0.04)
        }
    }

    private var cardBg: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(KBTheme.cardBackground(colorScheme))
    }

    private func trendCard(title: LocalizedStringKey, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline.bold())
                .foregroundStyle(tint)
            Text(ClinicalRecordTextSanitizer.sanitize(text))
                .font(.subheadline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.opacity(0.08)))
    }

    private func contentCard(title: LocalizedStringKey, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(ClinicalRecordTextSanitizer.sanitize(text))
                .font(.subheadline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg)
    }
}
