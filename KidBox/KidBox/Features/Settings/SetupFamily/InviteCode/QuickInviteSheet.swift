//
//  QuickInviteSheet.swift
//  KidBox
//
//  L'invito in versione corta, aperto dal "+" sulla foto di famiglia.
//
//  Non è una seconda implementazione dell'invito: usa lo stesso
//  `InviteCodeViewModel` della schermata «Invita genitore», quindi la stessa
//  creazione cifrata e lo stesso link. Qui cambia solo quanto si legge — chi
//  tocca il "+" dalla Home vuole mandare un invito, non studiare come funziona.
//  Le spiegazioni lunghe, la revoca e il resto restano nella schermata piena.
//
//  Con `firstContent` valorizzato è lo stesso foglio nella sua seconda veste:
//  aperto da `RootHostView` subito dopo il primo contenuto creato in una
//  famiglia con un solo membro (vedi `FirstContentInvitePrompt`). Cambiano il
//  testo — che nomina la cosa appena aggiunta — e i due eventi analytics che
//  dicono se l'occasione è stata colta.
//

import SwiftUI
import SwiftData

struct QuickInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var vm: InviteCodeViewModel
    /// Il foglio si allarga da solo quando compare il QR: a metà schermo un
    /// codice grande abbastanza da inquadrare non ci starebbe.
    @State private var detent: PresentationDetent = .medium
    /// Tipo del contenuto appena creato, quando il foglio è l'invito
    /// contestuale; `nil` per il "+" sulla foto di famiglia.
    private let firstContent: String?
    private static let promptTrigger = "first_content"

    init(modelContext: ModelContext, coordinator: AppCoordinator, firstContent: String? = nil) {
        _vm = StateObject(wrappedValue: InviteCodeViewModel(
            remote: InviteRemoteStore(),
            modelContext: modelContext,
            coordinator: coordinator
        ))
        self.firstContent = firstContent
    }

    private var title: String {
        firstContent == nil
            ? String(localized: "Invita un familiare")
            : String(localized: "Per ora lo vedi solo tu")
    }

    private var subtitle: String {
        guard let firstContent else {
            return String(localized: "Chi apre il link entra nella famiglia e riceve la chiave di cifratura.")
        }
        let subject = FirstContentInvitePrompt.subject(for: firstContent)
        return String(localized: "Invita l'altro genitore o chi vuoi: chi entra con il link vede \(subject) e tutto quello che aggiungerete, in tempo reale.")
    }

    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    var body: some View {
        VStack(spacing: 16) {
            // L'illustrazione serve prima, quando il foglio deve solo spiegarsi.
            // Creato l'invito il soggetto è il QR, e lo spazio va a lui.
            if vm.qrPayload == nil {
                Image("HomePromoInvite")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let payload = vm.qrPayload {
                ready(payload: payload)
            } else {
                generate
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            Button(firstContent == nil ? "Chiudi" : "Non ora") { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: vm.qrPayload) { _, payload in
            if payload != nil { detent = .large }
        }
        .onAppear {
            guard let firstContent else { return }
            AppAnalytics.invitePromptShown(trigger: Self.promptTrigger, contentType: firstContent)
        }
        // Chiuso in qualunque modo (bottone, trascinamento) senza aver creato
        // l'invito: è un «Non ora», e va contato come tale.
        .onDisappear {
            guard let firstContent, vm.qrPayload == nil else { return }
            AppAnalytics.invitePromptDismissed(trigger: Self.promptTrigger, contentType: firstContent)
        }
    }

    private var generate: some View {
        VStack(spacing: 10) {
            Button {
                KBLog.navigation.kbDebug("QuickInvite: tap generate (busy=\(vm.isBusy))")
                if let firstContent {
                    AppAnalytics.invitePromptAccepted(trigger: Self.promptTrigger, contentType: firstContent)
                }
                Task { await vm.generateInviteCode() }
            } label: {
                HStack(spacing: 8) {
                    if vm.isBusy {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "person.badge.plus")
                    }
                    Text(vm.isBusy ? "Creazione invito…" : "Crea invito")
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(KBTheme.bubbleTint, in: Capsule())
            }
            .disabled(vm.isBusy)

            Text("Vale 24 ore e una volta sola.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func ready(payload: String) -> some View {
        VStack(spacing: 12) {
            // Il QR resta anche qui: da vicino è la via che non fa passare la
            // chiave da nessuna chat.
            // 220 è il tetto di `QRCodeView`: chiedere di più non lo ingrandirebbe.
            QRCodeView(payload: payload)
                .frame(maxWidth: 220, maxHeight: 220)

            HStack(spacing: 10) {
                ShareLink(
                    item: vm.shareText,
                    subject: Text(InviteCodeViewModel.shareSubject)
                ) {
                    Label("Invia link", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(KBTheme.bubbleTint, in: Capsule())
                }
                // `ShareLink` non dice quando viene toccato: il gesto in
                // parallelo è l'unico modo di contarlo. Prima di questo,
                // `invite_shared` su iOS scattava solo nel wizard.
                .simultaneousGesture(TapGesture().onEnded {
                    AppAnalytics.inviteShared(channel: "share_sheet")
                })

                Button {
                    vm.copyToClipboard()
                    AppAnalytics.inviteShared(channel: "copy")
                } label: {
                    Label("Copia", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KBTheme.bubbleTint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(KBTheme.bubbleTint.opacity(0.12), in: Capsule())
                }
            }

            // Il segreto viaggia dentro il link: chi lo riceve entra, e il link
            // resta nella conversazione. Detto corto, ma detto.
            Text("Il link contiene la chiave: vale 24 ore e una volta sola.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
