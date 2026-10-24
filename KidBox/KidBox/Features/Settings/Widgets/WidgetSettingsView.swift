//
//  WidgetSettingsView.swift
//  KidBox
//
//  I widget della Home (Dashboard e Meteo): la voce Impostazioni > Widget, il
//  foglio che si apre dal consiglio in Home e il consiglio stesso.
//
//  Il consiglio compare sotto la foto di famiglia finché nessun widget è
//  acceso. La prima volta subito; poi a un avvio a freddo solo se dall'ultima
//  volta sono passati tre giorni, a meno che l'utente non abbia scelto «Non
//  visualizzare più». La decisione si prende una volta per processo: tornare
//  in Home o rientrare dal background non lo fa ricomparire.
//

import SwiftUI

// MARK: - Consiglio: quando mostrarlo

@MainActor
enum KBHomeWidgetHint {
    static let neverKey = "kb_widgetHint_never"
    static let lastShownKey = "kb_widgetHint_lastShown"
    private static let interval: TimeInterval = 3 * 24 * 3600

    /// Decisa alla prima richiesta di questo processo, poi fissa.
    private static var allowedThisLaunch: Bool?
    private static var recordedThisLaunch = false

    static var isAllowed: Bool {
        if let allowedThisLaunch { return allowedThisLaunch }
        let d = UserDefaults.standard
        let allowed: Bool
        if d.bool(forKey: neverKey) {
            allowed = false
        } else if let last = d.object(forKey: lastShownKey) as? Date {
            allowed = Date().timeIntervalSince(last) >= interval
        } else {
            allowed = true
        }
        allowedThisLaunch = allowed
        return allowed
    }

    /// Da chiamare quando il consiglio arriva davvero a schermo: è da lì che
    /// partono i tre giorni, non dall'avvio in cui era nascosto dalla checklist.
    static func markShown() {
        guard !recordedThisLaunch else { return }
        recordedThisLaunch = true
        UserDefaults.standard.set(Date(), forKey: lastShownKey)
    }

    static func neverAgain() {
        UserDefaults.standard.set(true, forKey: neverKey)
        allowedThisLaunch = false
    }
}

// MARK: - Impostazioni > Widget

struct WidgetSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(KBHomeDashboardPreference.key) private var showHomeDashboard = false
    @AppStorage(KBHomeWeatherPreference.key) private var showHomeWeather = false

    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    private var cardBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.18, green: 0.18, blue: 0.18)
        : Color(.systemBackground)
    }

    var body: some View {
        List {
            Section {
                toggleRow(isOn: $showHomeDashboard, symbol: "square.grid.2x2.fill",
                          title: "Visualizza Dashboard in home page")
                toggleRow(isOn: $showHomeWeather, symbol: "cloud.sun.fill",
                          title: "Visualizza le previsioni del tempo in home page")
            } footer: {
                Text("I widget compaiono in Home sotto la foto di famiglia.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .navigationTitle("Widget")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggleRow(isOn: Binding<Bool>, symbol: String, title: LocalizedStringKey) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(KBTheme.bubbleTint)
                    .frame(width: 28)
                Text(title)
                    .foregroundStyle(.primary)
            }
        }
        .tint(KBTheme.bubbleTint)
        .listRowBackground(cardBackground)
    }

    /// Riga riassuntiva per l'elenco delle Impostazioni.
    static func summary(dashboard: Bool, weather: Bool) -> String {
        var parts: [String] = []
        if dashboard { parts.append(String(localized: "Dashboard")) }
        if weather { parts.append(String(localized: "Meteo")) }
        return parts.isEmpty ? String(localized: "Nessuno") : parts.joined(separator: ", ")
    }
}

// MARK: - Foglio dal consiglio in Home

struct HomeWidgetPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(KBHomeDashboardPreference.key) private var showHomeDashboard = false
    @AppStorage(KBHomeWeatherPreference.key) private var showHomeWeather = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    option(symbol: "cloud.sun.fill",
                           title: "Meteo",
                           subtitle: "Le previsioni del tempo dove ti trovi",
                           isOn: $showHomeWeather)
                    option(symbol: "square.grid.2x2.fill",
                           title: "Dashboard",
                           subtitle: "Scadenze, spese e novità della famiglia in un colpo d'occhio",
                           isOn: $showHomeDashboard)
                } footer: {
                    Text("Puoi disattivarli in qualsiasi momento da Impostazioni → Widget.")
                }

                Section {
                    Button(role: .destructive) {
                        KBHomeWidgetHint.neverAgain()
                        dismiss()
                    } label: {
                        Text("Non visualizzare più questo consiglio")
                    }
                }
            }
            .navigationTitle("Aggiungi widget alla Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func option(symbol: String, title: LocalizedStringKey, subtitle: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .symbolRenderingMode(.multicolor)
                .font(.title2)
                .foregroundStyle(KBTheme.bubbleTint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isOn.wrappedValue {
                Label("Aggiunto", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(.green)
                    .accessibilityLabel(Text("Aggiunto"))
            } else {
                Button("Aggiungi") {
                    withAnimation { isOn.wrappedValue = true }
                }
                .buttonStyle(.borderedProminent)
                .tint(KBTheme.bubbleTint)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Consiglio in Home

/// Pillola sotto la foto di famiglia: bordo tratteggiato che scorre e freccia
/// che rimbalza, così si nota senza essere un banner che urla.
struct HomeWidgetHintBanner: View {
    let onTap: () -> Void

    @State private var dashPhase: CGFloat = 0
    @State private var bounce = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(KBTheme.bubbleTint)
                    .offset(y: bounce ? 3 : -3)
                Text("Aggiungi widget alla Home")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(KBTheme.bubbleTint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(KBTheme.bubbleTint.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(KBTheme.bubbleTint,
                                  style: StrokeStyle(lineWidth: 1.5, dash: [8, 6], dashPhase: dashPhase))
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            KBHomeWidgetHint.markShown()
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                dashPhase = -28
            }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                bounce = true
            }
        }
    }
}
