//
//  AlexaSettingsView.swift
//  KidBox
//

import SwiftUI

/// Collegamento della lista della spesa agli Echo di casa.
struct AlexaSettingsView: View {

    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var viewModel = AlexaSettingsViewModel()
    @Environment(\.colorScheme) private var colorScheme

    @State private var showUnlinkConfirm = false

    // MARK: - Dynamic theme (same as LoginView)

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
            statusSection

            // Chi ha già collegato in famiglia va detto sempre, anche a chi ha
            // il proprio collegamento: è l'unico posto da cui si capisce quanti
            // account Amazon sono agganciati alla lista.
            if !viewModel.otherLinks.isEmpty {
                familyLinksSection
            }

            // Il codice non sparisce col collegamento dell'account: se la voce
            // non è ancora associata, serve ancora — ed è proprio il caso del
            // secondo membro di casa, che l'account ce l'ha già per riflesso.
            if case .linked = viewModel.linkState {
                if !viewModel.voiceLinked { voiceSection }
                phrasesSection
                unlinkSection
            } else {
                // Prima del codice viene la skill: senza, il codice si detta a
                // vuoto e non c'è modo di capire perché. È il primo passo, e
                // fino a ieri non era scritto da nessuna parte.
                skillSetupSection
                pairingSection
            }

            if let errorText = viewModel.errorText {
                Section {
                    // `errorText` è una String, e `Text(String)` non passa dal
                    // catalogo: senza questo wrapping gli errori resterebbero in
                    // italiano anche con l'app in inglese.
                    Text(LocalizedStringKey(errorText))
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .listRowBackground(cardBackground)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .navigationTitle("Alexa")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.load(familyId: coordinator.activeFamilyId) }
        .onDisappear { viewModel.stop() }
        .confirmationDialog(
            "Scollegare Alexa?",
            isPresented: $showUnlinkConfirm,
            titleVisibility: .visible
        ) {
            Button("Scollega", role: .destructive) { viewModel.unlink() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Gli Echo di casa non potranno più aggiungere articoli alla lista finché non ricolleghi.")
        }
    }

    // MARK: - Stato

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .foregroundStyle(KBTheme.bubbleTint)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .foregroundStyle(.primary)
                    Text(statusSubtitle)
                        .alexaHint()
                }

                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                }
            }
            .listRowBackground(cardBackground)
        } footer: {
            Text("Detta la lista della spesa agli Echo di casa: gli articoli finiscono nella stessa lista che vedi in KidBox, e gli altri membri li ricevono subito.")
                .alexaHint()
        }
    }

    private var statusIcon: String {
        if case .linked = viewModel.linkState { return "checkmark.circle.fill" }
        if !viewModel.otherLinks.isEmpty { return "person.2.fill" }
        return "link.circle"
    }

    // `LocalizedStringKey` e non `String`: `Text(String)` usa l'inizializzatore
    // non localizzato e queste righe resterebbero in italiano ovunque.
    private var statusTitle: LocalizedStringKey {
        switch viewModel.linkState {
        case .linked: return "Alexa collegata"
        // "Non collegata" sarebbe falso se un altro membro l'ha già agganciata:
        // la lista è già raggiungibile dagli Echo di casa.
        case .notLinked: return viewModel.otherLinks.isEmpty
            ? "Alexa non collegata"
            : "Alexa collegata in famiglia"
        case .unknown: return "Alexa"
        }
    }

    private var statusSubtitle: LocalizedStringKey {
        switch viewModel.linkState {
        case .linked:
            return viewModel.voiceLinked
                ? "Riconosce la tua voce"
                : "Quello che detti risulta di chi ha collegato"
        case .notLinked:
            return viewModel.otherLinks.isEmpty
                ? "Serve un codice da dettare una volta sola"
                : "Ma non da questo account"
        case .unknown:
            return "Controllo in corso…"
        }
    }

    // MARK: - Collegamenti degli altri membri

    private var familyLinksSection: some View {
        Section {
            ForEach(viewModel.otherLinks) { link in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(link.displayName)
                            .foregroundStyle(.primary)
                        // Account e voce non sono la stessa cosa: il primo dà
                        // accesso alla lista, la seconda solo l'attribuzione.
                        Text(link.kind == .voice ? "Voce riconosciuta" : "Account collegato")
                            .alexaHint()
                    }
                }
                .listRowBackground(cardBackground)
            }
        } header: {
            Text("Già collegata in famiglia")
        } footer: {
            // La distinzione conta: il collegamento è per account Amazon, non
            // per famiglia. Senza questa riga il secondo membro non capisce se
            // deve collegare anche lui o se è già a posto.
            Text("Se gli Echo di casa sono sullo stesso account Amazon, funzionano già e non devi fare altro. Collega anche il tuo solo se hai un account Amazon separato: così quello che detti risulta aggiunto da te.")
                .alexaHint()
        }
    }

    // MARK: - Attivazione della skill

    private var skillSetupSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(KBTheme.bubbleTint)
                    .frame(width: 22)
                Text("Apri l'app Alexa, cerca «KidBox» fra le skill e attivala")
                    .foregroundStyle(.primary)
            }
            .listRowBackground(cardBackground)
        } header: {
            Text("1. Attiva la skill")
        } footer: {
            Text("Senza la skill attiva sul tuo account Amazon, gli Echo non sanno cosa sia «mio box» e il codice qui sotto non ha nessuno a cui arrivare. Si fa una volta sola.")
                .alexaHint()
        }
    }

    // MARK: - Accoppiamento

    private var pairingSection: some View {
        Section {
            if let code = viewModel.pairingCode {
                codeBlock(code)
            } else {
                Button {
                    viewModel.generateCode(familyId: coordinator.activeFamilyId)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "number.circle.fill")
                            .foregroundStyle(KBTheme.bubbleTint)
                            .frame(width: 22)
                        Text("Genera codice di collegamento")
                            .foregroundStyle(.primary)
                        if viewModel.isGenerating {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isGenerating)
                .listRowBackground(cardBackground)
            }
        } header: {
            // Numerato: questa sezione compare solo a collegamento assente,
            // subito dopo il passo 1, e l'ordine fra i due conta.
            Text("2. Collega l'account")
        } footer: {
            Text("Il codice vale 10 minuti e si usa una volta sola. Non serve fare login nella skill: sei già autenticato qui, e il codice porta la tua identità su Alexa.")
                .alexaHint()
        }
    }

    /// Il codice a schermo con la frase da dire. Uguale per l'account e per la
    /// voce: la formula pronunciata è la stessa, cambia solo cosa viene legato.
    @ViewBuilder
    private func codeBlock(_ code: String) -> some View {
        VStack(spacing: 10) {
            Text(code)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .kerning(2)
                .foregroundStyle(.primary)
                // Le cifre lette una per una: con il codice tutto attaccato
                // VoiceOver dice "quattrocentoottantaduemila…".
                .accessibilityLabel(code.compactMap { $0.isNumber ? String($0) : nil }.joined(separator: " "))

            Text("Di' ad Alexa:")
                .alexaHint()

            Text("«Alexa, chiedi a mio box di collegarsi con \(code)»")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            Text("Scade fra \(viewModel.secondsLeft / 60):\(String(format: "%02d", viewModel.secondsLeft % 60))")
                .monospacedDigit()
                .alexaHint()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .listRowBackground(cardBackground)
    }

    // MARK: - Voce

    private var voiceSection: some View {
        Section {
            if let code = viewModel.pairingCode {
                codeBlock(code)
            } else {
                Button {
                    viewModel.generateCode(familyId: coordinator.activeFamilyId)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .foregroundStyle(KBTheme.bubbleTint)
                            .frame(width: 22)
                        Text("Fai riconoscere la tua voce")
                            .foregroundStyle(.primary)
                        if viewModel.isGenerating {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isGenerating)
                .listRowBackground(cardBackground)
            }
        } header: {
            Text("La tua voce")
        } footer: {
            // Nessun allarme: chi non ha un profilo vocale non ha niente di
            // rotto, semplicemente i suoi articoli restano attribuiti a chi ha
            // collegato l'account.
            Text("Alexa distingue le voci di casa. Detta una volta il tuo codice e da lì in poi quello che dici risulterà aggiunto da te, anche dall'Echo di un altro. Se non hai un profilo vocale su Alexa, tutto funziona lo stesso: gli articoli restano attribuiti a chi ha collegato l'account.")
                .alexaHint()
        }
    }

    // MARK: - Frasi

    private var phrasesSection: some View {
        Section {
            ForEach(Self.phrases, id: \.self) { phrase in
                HStack(spacing: 12) {
                    Image(systemName: "quote.bubble")
                        .foregroundStyle(KBTheme.bubbleTint)
                        .frame(width: 22)
                    Text(phrase)
                        .font(.callout)
                        .foregroundStyle(.primary)
                }
                .listRowBackground(cardBackground)
            }
        } header: {
            Text("Cosa puoi dire")
        }
    }

    private static let phrases = [
        "«Alexa, chiedi a mio box di aggiungere il latte»",
        "«Alexa, chiedi a mio box cosa manca»",
        "«Alexa, chiedi a mio box di togliere il pane»",
        "«Alexa, apri mio box»"
    ]

    // MARK: - Scollega

    private var unlinkSection: some View {
        Section {
            Button(role: .destructive) {
                showUnlinkConfirm = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 22)
                    Text("Scollega Alexa")
                }
            }
            .disabled(viewModel.isLoading)
            .listRowBackground(cardBackground)
        }
    }
}

// Un unico stile per tutto il testo esplicativo della schermata.
//
// Prima ogni riga ripeteva `.font(.caption)` e `.foregroundStyle(.secondary)`:
// undici punti di grigio chiaro dentro un footer di List, che SwiftUI attenua
// già di suo. I due effetti si sommavano e il risultato era illeggibile.
// `.footnote` sono due punti in più ed è la taglia che usa Impostazioni di
// sistema per lo stesso ruolo. Definirlo qui, e non riga per riga, è ciò che
// impedisce allo stile di divergere di nuovo alla prossima aggiunta.
private extension View {
    func alexaHint() -> some View {
        font(.footnote).foregroundStyle(.secondary)
    }
}
