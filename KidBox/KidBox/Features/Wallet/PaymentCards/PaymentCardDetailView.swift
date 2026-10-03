//
//  PaymentCardDetailView.swift
//  KidBox
//
//  Created by vscocca on 03/10/26.
//
//  Dettaglio di una carta di pagamento. Il numero intero e il PIN si vedono
//  o si copiano solo dopo Face ID / codice del telefono, come le password, e torna
//  nascosto appena l'app va in background (lo snapshot del selettore app
//  non deve mostrarlo). Copie negli appunti: solo locali e per 60 secondi.
//

import SwiftUI
import SwiftData
import UIKit
import LocalAuthentication
import FirebaseAuth

struct PaymentCardDetailView: View {
    let familyId: String
    let cardId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var cards: [KBPaymentCard]

    @State private var isUnlocked = false
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false

    @State private var frontImage: UIImage?
    @State private var backImage: UIImage?
    @State private var loadingSides: Set<LoyaltyCardPhotoSide> = []
    @State private var busySides: Set<LoyaltyCardPhotoSide> = []
    @State private var scanningSide: LoyaltyCardPhotoSide?
    @State private var fullscreenSide: LoyaltyCardPhotoSide?
    @State private var photoErrorMessage: String?

    private let photoStore = PaymentCardPhotoStore()

    init(familyId: String, cardId: String) {
        self.familyId = familyId
        self.cardId = cardId
        _cards = Query(filter: #Predicate<KBPaymentCard> { $0.id == cardId && $0.isDeleted == false })
    }

    private var card: KBPaymentCard? { cards.first }
    private var currentUid: String? { Auth.auth().currentUser?.uid }

    var body: some View {
        Group {
            if let card {
                if card.isVisible(to: currentUid) {
                    detailScroll(card, plain: PaymentCardPlain(card: card, userId: currentUid))
                } else {
                    ContentUnavailableView(
                        "Carta non disponibile",
                        systemImage: "eye.slash",
                        description: Text("Non hai accesso a questa carta.")
                    )
                }
            } else {
                ContentUnavailableView(
                    "Carta non trovata",
                    systemImage: "creditcard.trianglebadge.exclamationmark",
                    description: Text("Potrebbe essere stata eliminata o non ancora sincronizzata.")
                )
            }
        }
        .navigationTitle("Carta di pagamento")
        .navigationBarTitleDisplayMode(.inline)
        .familyKeyMissingGate(familyId: familyId)
        .toolbar {
            if let card, card.isVisible(to: currentUid) {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showEditSheet = true
                        } label: {
                            Label("Modifica", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Elimina", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog(
            "Eliminare questa carta?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) {
                if let card { deleteCard(card) }
            }
            Button("Annulla", role: .cancel) {}
        }
        .sheet(isPresented: $showEditSheet) {
            if let card {
                PaymentCardFormView(familyId: familyId, card: card) { _ in }
            }
        }
        .fullScreenCover(item: $scanningSide) { side in
            WalletDocumentScannerView(
                onFinish: { pages in
                    scanningSide = nil
                    handleScanned(pages: pages, requestedSide: side)
                },
                onCancel: { scanningSide = nil }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $fullscreenSide) { side in
            WalletDocumentImagesFullscreenView(
                images: [image(for: side)].compactMap { $0 },
                tint: Color.loyaltyCardColor(hex: card?.colorHex ?? PaymentCardPalette.defaultHex)
            )
        }
        .task(id: photoLoadKey) {
            await loadPhotos()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { isUnlocked = false }
        }
        .onAppear {
            guard let card, card.isVisible(to: currentUid) else { return }
            let origin = coordinator.consumeRetrievalOrigin()
            Task {
                await KBAnalytics.shared.logRetrieval(
                    feature: .wallet,
                    uploaderUid: card.createdBy,
                    createdAt: card.createdAt,
                    entryPoint: origin
                )
            }
            if card.createdBy != currentUid {
                AppAnalytics.contentSharedRead(type: "payment_card")
            }
        }
    }

    // MARK: - Contenuto

    @ViewBuilder
    private func detailScroll(_ card: KBPaymentCard, plain: PaymentCardPlain) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PaymentCardTileView(plain: plain, colorHex: card.colorHex, height: 210)

                if plain.isUnreadable {
                    Label("Non riesco a decifrare questa carta su questo dispositivo.", systemImage: "lock.trianglebadge.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else {
                    fieldsCard(plain)
                }

                photosSection(card)

                if !plain.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nota")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(plain.notes)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(PaymentCardPanel(colorScheme: colorScheme))
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Elimina carta", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
                .padding(.top, 4)
            }
            .padding(16)
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
    }

    @ViewBuilder
    private func fieldsCard(_ plain: PaymentCardPlain) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !plain.cardNumber.isEmpty {
                fieldRow(
                    title: "Numero carta",
                    value: isUnlocked ? PaymentCardFormat.grouped(plain.cardNumber) : PaymentCardFormat.masked(plain.cardNumber),
                    monospaced: true
                ) {
                    HStack(spacing: 14) {
                        Button {
                            if isUnlocked { isUnlocked = false } else { Task { await unlock() } }
                        } label: {
                            Image(systemName: isUnlocked ? "eye.slash" : "eye")
                        }
                        .accessibilityLabel(isUnlocked ? Text("Nascondi") : Text("Mostra"))
                        Button {
                            Task {
                                if !isUnlocked { await unlock() }
                                if isUnlocked { copy(plain.cardNumber, banner: NSLocalizedString("Numero copiato per 60 secondi.", comment: "Payment card: number copied")) }
                            }
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .accessibilityLabel(Text("Copia"))
                    }
                }
            }

            if !plain.pin.isEmpty {
                fieldRow(
                    title: "PIN",
                    value: isUnlocked ? plain.pin : String(repeating: "•", count: 4),
                    monospaced: true
                ) {
                    HStack(spacing: 14) {
                        Button {
                            if isUnlocked { isUnlocked = false } else { Task { await unlock() } }
                        } label: {
                            Image(systemName: isUnlocked ? "eye.slash" : "eye")
                        }
                        .accessibilityLabel(isUnlocked ? Text("Nascondi") : Text("Mostra"))
                        Button {
                            Task {
                                if !isUnlocked { await unlock() }
                                if isUnlocked { copy(plain.pin, banner: NSLocalizedString("PIN copiato per 60 secondi.", comment: "Payment card: PIN copied")) }
                            }
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .accessibilityLabel(Text("Copia"))
                    }
                }
            }

            if !plain.holderName.isEmpty {
                fieldRow(title: "Intestatario", value: plain.holderName, monospaced: false) {
                    copyButton(plain.holderName, banner: NSLocalizedString("Intestatario copiato.", comment: "Payment card: holder copied"))
                }
            }

            if !plain.expiry.isEmpty {
                fieldRow(title: "Scadenza", value: plain.expiry, monospaced: true) {
                    if PaymentCardFormat.isExpired(plain.expiry) {
                        Text("Scaduta")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.red)
                    }
                }
            }

            if !plain.iban.isEmpty {
                fieldRow(title: "IBAN", value: PaymentCardFormat.ibanGrouped(plain.iban), monospaced: true) {
                    copyButton(plain.iban, banner: NSLocalizedString("IBAN copiato.", comment: "Payment card: IBAN copied"))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PaymentCardPanel(colorScheme: colorScheme))
    }

    private func fieldRow<Trailing: View>(
        title: LocalizedStringKey,
        value: String,
        monospaced: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(monospaced ? .system(.body, design: .monospaced) : .body)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            trailing()
                .foregroundStyle(KBTheme.tint)
        }
    }

    private func copyButton(_ value: String, banner: String) -> some View {
        Button {
            copy(value, banner: banner)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .accessibilityLabel(Text("Copia"))
    }

    private func copy(_ value: String, banner: String) {
        KBClipboard.copy(value, expiresIn: 60, localOnly: true)
        coordinator.globalBannerMessage = banner
    }

    @MainActor
    private func unlock() async {
        let context = LAContext()
        var err: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            coordinator.globalBannerMessage = NSLocalizedString("Sblocco non disponibile: imposta un codice o Face ID.", comment: "")
            return
        }
        do {
            isUnlocked = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: NSLocalizedString("Mostra il numero e il PIN della carta.", comment: "Face ID reason for payment card number and PIN")
            )
        } catch {
            coordinator.globalBannerMessage = NSLocalizedString("Sblocco annullato.", comment: "")
        }
    }

    // MARK: - Foto fronte/retro

    @ViewBuilder
    private func photosSection(_ card: KBPaymentCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Foto della carta")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                photoSlot(card, side: .front)
                photoSlot(card, side: .back)
            }

            if let photoErrorMessage {
                Text(photoErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PaymentCardPanel(colorScheme: colorScheme))
    }

    @ViewBuilder
    private func photoSlot(_ card: KBPaymentCard, side: LoyaltyCardPhotoSide) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            (side == .front ? Text("Fronte") : Text("Retro"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack {
                if let img = image(for: side) {
                    Button {
                        fullscreenSide = side
                    } label: {
                        // Il contenitore detta la misura, non l'immagine: vedi
                        // la stessa nota in LoyaltyCardDetailView.
                        Color.clear
                            .frame(height: 96)
                            .frame(maxWidth: .infinity)
                            .overlay {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        photoErrorMessage = nil
                        scanningSide = side
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "camera")
                                .font(.title2)
                            Text("Aggiungi")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .frame(height: 96)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(KBTheme.separator(colorScheme).opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                }

                if loadingSides.contains(side) || busySides.contains(side) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.black.opacity(0.25))
                        .frame(height: 96)
                        .overlay(ProgressView().tint(.white))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(KBTheme.separator(colorScheme).opacity(0.3), lineWidth: 0.5)
            )

            if image(for: side) != nil, !busySides.contains(side), !loadingSides.contains(side) {
                Button(role: .destructive) {
                    Task { await removePhoto(card, side: side) }
                } label: {
                    Label("Elimina foto", systemImage: "trash")
                        .font(.caption)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .disabled(busySides.contains(side))
    }

    private func image(for side: LoyaltyCardPhotoSide) -> UIImage? {
        side == .front ? frontImage : backImage
    }

    private func setImage(_ image: UIImage?, for side: LoyaltyCardPhotoSide) {
        if side == .front { frontImage = image } else { backImage = image }
    }

    private func storagePath(_ card: KBPaymentCard, side: LoyaltyCardPhotoSide) -> String? {
        let raw = side == .front ? card.frontPhotoStoragePath : card.backPhotoStoragePath
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    private var photoLoadKey: String {
        guard let card else { return "" }
        return "\(card.id)|\(card.frontPhotoStoragePath ?? "")|\(card.backPhotoStoragePath ?? "")"
    }

    private func loadPhotos() async {
        guard let card, card.isVisible(to: currentUid) else { return }
        for side in LoyaltyCardPhotoSide.allCases {
            guard let path = storagePath(card, side: side) else {
                setImage(nil, for: side)
                continue
            }
            guard image(for: side) == nil else { continue }
            loadingSides.insert(side)
            do {
                setImage(try await photoStore.download(familyId: card.familyId, storagePath: path), for: side)
            } catch {
                KBLog.ui.kbError("[PaymentCardDetail] photo load failed side=\(side.rawValue) err=\(error.localizedDescription)")
            }
            loadingSides.remove(side)
        }
    }

    /// Lo scanner è multi-pagina: partendo dal fronte, la seconda pagina
    /// riempie il retro se è ancora vuoto.
    private func handleScanned(pages: [UIImage], requestedSide: LoyaltyCardPhotoSide) {
        guard let card, let first = pages.first else { return }
        Task {
            await storePhoto(card, side: requestedSide, image: first)
            if requestedSide == .front, pages.count > 1, storagePath(card, side: .back) == nil {
                await storePhoto(card, side: .back, image: pages[1])
            }
        }
    }

    private func storePhoto(_ card: KBPaymentCard, side: LoyaltyCardPhotoSide, image: UIImage) async {
        busySides.insert(side)
        photoErrorMessage = nil
        defer { busySides.remove(side) }
        do {
            let (path, url) = try await photoStore.upload(
                familyId: card.familyId, cardId: card.id, side: side, image: image)
            if side == .front {
                card.frontPhotoStoragePath = path
                card.frontPhotoStorageURL = url
            } else {
                card.backPhotoStoragePath = path
                card.backPhotoStorageURL = url
            }
            setImage(image, for: side)
            touchAndSync(card)
        } catch {
            let format = NSLocalizedString("Impossibile salvare la foto: %@", comment: "Loyalty card photo upload error, %@ = underlying error description")
            photoErrorMessage = String(format: format, error.localizedDescription)
        }
    }

    private func removePhoto(_ card: KBPaymentCard, side: LoyaltyCardPhotoSide) async {
        busySides.insert(side)
        photoErrorMessage = nil
        defer { busySides.remove(side) }

        if let path = storagePath(card, side: side) {
            do {
                try await photoStore.delete(storagePath: path)
            } catch {
                KBLog.sync.kbError("[PaymentCardDetail] photo delete failed (ignored) side=\(side.rawValue) err=\(error.localizedDescription)")
            }
        }
        if side == .front {
            card.frontPhotoStoragePath = nil
            card.frontPhotoStorageURL = nil
        } else {
            card.backPhotoStoragePath = nil
            card.backPhotoStorageURL = nil
        }
        setImage(nil, for: side)
        touchAndSync(card)
    }

    private func touchAndSync(_ card: KBPaymentCard) {
        if let uid = currentUid {
            card.updatedBy = uid
            card.updatedByName = Auth.auth().currentUser?.displayName ?? ""
        }
        card.updatedAt = .now
        card.syncState = .pendingUpsert
        try? modelContext.save()
        SyncCenter.shared.enqueuePaymentCardUpsert(cardId: card.id, familyId: card.familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }

    private func deleteCard(_ card: KBPaymentCard) {
        card.isDeleted = true
        card.updatedAt = .now
        card.syncState = .pendingDelete
        try? modelContext.save()
        SyncCenter.shared.enqueuePaymentCardDelete(cardId: card.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        coordinator.globalBannerMessage = NSLocalizedString("Carta eliminata.", comment: "Banner after deleting a payment card")
        dismiss()
    }
}

/// Riquadro dei blocchi del dettaglio, come nelle carte fedeltà.
private struct PaymentCardPanel: ViewModifier {
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        content
            .background(KBTheme.cardBackground(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(KBTheme.separator(colorScheme).opacity(0.3), lineWidth: 0.5)
            )
    }
}
