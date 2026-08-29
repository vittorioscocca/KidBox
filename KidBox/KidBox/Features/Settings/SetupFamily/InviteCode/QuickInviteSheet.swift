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

import SwiftUI
import SwiftData

struct QuickInviteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var vm: InviteCodeViewModel
    /// Il foglio si allarga da solo quando compare il QR: a metà schermo un
    /// codice grande abbastanza da inquadrare non ci starebbe.
    @State private var detent: PresentationDetent = .medium

    init(modelContext: ModelContext, coordinator: AppCoordinator) {
        _vm = StateObject(wrappedValue: InviteCodeViewModel(
            remote: InviteRemoteStore(),
            modelContext: modelContext,
            coordinator: coordinator
        ))
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
                Text("Invita un familiare")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                Text("Chi apre il link entra nella famiglia e riceve la chiave di cifratura.")
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

            Button("Chiudi") { dismiss() }
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
    }

    private var generate: some View {
        VStack(spacing: 10) {
            Button {
                KBLog.navigation.kbDebug("QuickInvite: tap generate (busy=\(vm.isBusy))")
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

                Button {
                    vm.copyToClipboard()
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
