//
//  OnboardingChecklistCard.swift
//  KidBox
//
//  La card "Per iniziare" in cima alla Home: cinque passi, una barra di
//  avanzamento, e righe che si spuntano da sole quando il passo è fatto.
//
//  Le scelte visive non sono decorative:
//
//  - **La barra e il "N su 5"** esistono perché una lista di cose da fare senza
//    un traguardo visibile è solo una lista di cose da fare. Vedere il secondo
//    segmento riempirsi è ciò che porta al terzo.
//  - **Le righe fatte restano**, barrate e in grigio, invece di sparire. Sono la
//    metà del valore della card: la parte già percorsa.
//  - **La chiusura è sempre disponibile.** Un suggerimento che non si può
//    togliere smette di essere un suggerimento.
//

import SwiftUI

struct OnboardingChecklistCard: View {

    @ObservedObject var model: OnboardingChecklistModel
    let onSelect: (OnboardingStepID) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var progress: Double {
        guard model.totalCount > 0 else { return 0 }
        return Double(model.completedCount) / Double(model.totalCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            progressBar

            VStack(spacing: 0) {
                ForEach(model.rows) { row in
                    OnboardingChecklistRow(row: row) {
                        onSelect(row.step)
                    }
                }
            }

            if model.isCelebrating {
                Text("Ci sei. KidBox adesso lavora per la tua famiglia.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(KBTheme.cardBackground(colorScheme))
        )
        .shadow(color: KBTheme.shadow(colorScheme), radius: 8, x: 0, y: 2)
        .animation(.snappy(duration: 0.28), value: model.completedCount)
    }

    /// Esplicita per non lasciare a Swift la scelta fra l'overload localizzato di
    /// `Text` e quello che stampa la stringa così com'è.
    private var headerTitle: LocalizedStringKey {
        model.isCelebrating ? "Tutto fatto 🎉" : "Per iniziare"
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(headerTitle)
                .font(.headline)

            Spacer(minLength: 8)

            Text("\(model.completedCount) su \(model.totalCount)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                withAnimation(.snappy(duration: 0.25)) { model.dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Nascondi i primi passi")
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(Color.primary)
                    .frame(width: max(0, geo.size.width * progress))
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Avanzamento")
        .accessibilityValue("\(model.completedCount) di \(model.totalCount) completati")
    }
}

// MARK: - Riga

private struct OnboardingChecklistRow: View {

    let row: OnboardingChecklistItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                checkmark

                Text(row.step.title)
                    .font(.subheadline)
                    .foregroundStyle(row.isComplete ? Color.secondary : Color.primary)
                    .strikethrough(row.isComplete, color: .secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if !row.isComplete {
                    Image(systemName: row.step.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(row.step.tint)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Un passo chiuso non è più un pulsante: toccarlo non deve rimandare
        // l'utente dove è già stato.
        .disabled(row.isComplete)
        .accessibilityLabel(row.step.title)
        .accessibilityAddTraits(row.isComplete ? .isStaticText : .isButton)
    }

    @ViewBuilder
    private var checkmark: some View {
        if row.isComplete {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.primary)
                .transition(.scale.combined(with: .opacity))
        } else {
            Circle()
                .strokeBorder(Color.secondary.opacity(0.45), lineWidth: 1.5)
                .frame(width: 20, height: 20)
        }
    }
}
