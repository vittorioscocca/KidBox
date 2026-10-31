//
//  OnboardingFirstContentCard.swift
//  KidBox
//
//  Ultima pagina del wizard «crea»: il primo contenuto vero, prima della Home.
//
//  Perché esiste (31/10/2026, 96 famiglie nate dal 21/09): 59 non avevano mai
//  messo niente, e 48 di queste non riaprivano l'app dopo il primo giorno.
//  Nessuna era mai arrivata a un secondo membro. La checklist «Per iniziare»
//  la vedevano ma non la seguivano. Tutto si decideva nella prima sessione,
//  quindi la prima cosa utile deve nascere qui. Scommessa 13 del registro.
//
//  Tre gesti, ognuno chiuso in questa schermata: un impegno (titolo e data),
//  la spesa (una riga, separata da virgole), un documento (che invece apre
//  Documenti, perché il caricamento ha già il suo flusso con la cifratura).
//  «Lo faccio dopo» resta sempre visibile: niente contenuti d'esempio, deve
//  essere una cosa dell'utente o niente.
//

import SwiftUI

enum OnboardingFirstContentChoice: String, CaseIterable, Identifiable {
    case event, grocery, document
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .event:    return "Un impegno"
        case .grocery:  return "La spesa"
        case .document: return "Un documento"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .event:    return "Una visita, lo sport, un compleanno"
        case .grocery:  return "Le prime cose da comprare"
        case .document: return "Carta d'identità, tessera sanitaria, una ricevuta"
        }
    }

    var systemImage: String {
        switch self {
        case .event:    return "calendar.badge.plus"
        case .grocery:  return "cart.fill"
        case .document: return "doc.text.fill"
        }
    }

    var tint: Color {
        switch self {
        case .event:    return .purple
        case .grocery:  return .green
        case .document: return .orange
        }
    }
}

struct OnboardingFirstContentCard: View {

    let cardBackground: Color
    let accentColor:    Color
    let iconColor:      Color
    /// Salvano in locale e mettono in coda la sincronizzazione; `false` se non
    /// c'è niente da salvare (titolo vuoto, nessun articolo).
    let onSaveEvent:    (_ title: String, _ start: Date) -> Bool
    let onSaveGrocery:  (_ names: [String]) -> Bool
    let onOpenDocuments: () -> Void
    let onSkip:         () -> Void
    /// Dopo la conferma «Fatto»: il wizard chiude e va in Home.
    let onFinished:     () -> Void

    @State private var selected: OnboardingFirstContentChoice? = nil
    @State private var eventTitle = ""
    @State private var eventDate  = OnboardingFirstContentCard.defaultEventDate()
    @State private var groceryText = ""
    @State private var savedChoice: OnboardingFirstContentChoice? = nil
    @FocusState private var focused: Bool

    /// Domani alle 17: un orario plausibile per la prima cosa della settimana,
    /// che l'utente sposta con un tocco.
    private static func defaultEventDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private var groceryNames: [String] {
        groceryText
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 20) {
            if let savedChoice {
                doneView(savedChoice)
            } else {
                header
                VStack(spacing: 12) {
                    ForEach(OnboardingFirstContentChoice.allCases) { choice in
                        choiceRow(choice)
                    }
                }
                Button(action: onSkip) {
                    Text("Lo faccio dopo →")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selected)
        .animation(.easeInOut(duration: 0.25), value: savedChoice)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(iconColor.opacity(0.15)).frame(width: 72, height: 72)
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(LinearGradient(
                        colors: [iconColor, accentColor],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            }
            Text("Cosa mettiamo per primo?")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("Una cosa vera di questa settimana: chi inviterai la troverà già qui.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Scelte

    private func choiceRow(_ choice: OnboardingFirstContentChoice) -> some View {
        let isOpen = selected == choice
        return VStack(alignment: .leading, spacing: 14) {
            Button {
                selected = isOpen ? nil : choice
                focused = selected != nil && selected != .document
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: choice.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(choice.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(choice.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(choice.subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                editor(for: choice)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isOpen ? choice.tint.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    @ViewBuilder
    private func editor(for choice: OnboardingFirstContentChoice) -> some View {
        switch choice {
        case .event:
            VStack(alignment: .leading, spacing: 12) {
                TextField("Es. Pediatra di Marco", text: $eventTitle)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .focused($focused)
                DatePicker("Quando", selection: $eventDate, displayedComponents: [.date, .hourAndMinute])
                    .font(.system(size: 15))
                primaryButton("Aggiungi al calendario", tint: choice.tint,
                              disabled: eventTitle.trimmingCharacters(in: .whitespaces).isEmpty) {
                    if onSaveEvent(eventTitle.trimmingCharacters(in: .whitespacesAndNewlines), eventDate) {
                        confirm(choice)
                    }
                }
            }
        case .grocery:
            VStack(alignment: .leading, spacing: 12) {
                TextField("Es. latte, pane, uova", text: $groceryText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .focused($focused)
                primaryButton("Aggiungi alla spesa", tint: choice.tint, disabled: groceryNames.isEmpty) {
                    if onSaveGrocery(groceryNames) {
                        confirm(choice)
                    }
                }
            }
        case .document:
            VStack(alignment: .leading, spacing: 12) {
                Text("Si apre Documenti: scegli un file, una foto o scansiona un foglio. Resta cifrato, lo vede solo la tua famiglia.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                primaryButton("Apri Documenti", tint: choice.tint, disabled: false, action: onOpenDocuments)
            }
        }
    }

    private func primaryButton(
        _ title: LocalizedStringKey,
        tint: Color,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(tint.opacity(disabled ? 0.35 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Fatto

    private func confirm(_ choice: OnboardingFirstContentChoice) {
        focused = false
        savedChoice = choice
        // Il tempo di leggere dove l'ha messo, poi la Home.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { onFinished() }
    }

    private func doneView(_ choice: OnboardingFirstContentChoice) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(choice.tint)
            Text("Fatto!")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(choice == .event
                 ? LocalizedStringKey("Lo trovi nel calendario.")
                 : LocalizedStringKey("Lo trovi nella lista della spesa."))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
    }
}
