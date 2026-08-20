//
//  LoyaltyCardDetailView.swift
//  KidBox
//
//  Created by vscocca on 20/08/26.
//
//  Dettaglio di una carta fedeltà: barcode grande (riusa `WalletBarcodeView`),
//  eventuale nota, menu "..." con azioni elimina/modifica. Ispirato allo
//  stile di `WalletTicketDetailView`, senza il tab "Negozi e offerte".
//

import SwiftUI
import SwiftData
import UIKit
import FirebaseAuth

struct LoyaltyCardDetailView: View {
    let familyId: String
    let cardId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var cards: [KBLoyaltyCard]

    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false

    // MARK: - Foto fronte/retro
    @State private var frontImage: UIImage?
    @State private var backImage: UIImage?
    @State private var loadingSides: Set<LoyaltyCardPhotoSide> = []
    @State private var busySides: Set<LoyaltyCardPhotoSide> = []
    /// Lato in acquisizione: valorizzato ⇒ scanner VisionKit presentato.
    @State private var scanningSide: LoyaltyCardPhotoSide?
    /// Lato aperto a schermo intero.
    @State private var fullscreenSide: LoyaltyCardPhotoSide?
    @State private var photoErrorMessage: String?

    private let photoStore = LoyaltyCardPhotoStore()

    init(familyId: String, cardId: String) {
        self.familyId = familyId
        self.cardId = cardId
        _cards = Query(filter: #Predicate<KBLoyaltyCard> { $0.id == cardId && $0.isDeleted == false })
    }

    private var card: KBLoyaltyCard? { cards.first }

    private var currentUid: String? {
        Auth.auth().currentUser?.uid
    }

    var body: some View {
        Group {
            if let card {
                if card.isVisible(to: currentUid) {
                    detailScroll(card)
                } else {
                    ContentUnavailableView(
                        "Carta non disponibile",
                        systemImage: "eye.slash",
                        description: Text("Non hai accesso a questa carta fedeltà.")
                    )
                }
            } else {
                missingCardPlaceholder
            }
        }
        .navigationTitle("Carta fedeltà")
        .navigationBarTitleDisplayMode(.inline)
        // Schermo al massimo finché la carta è aperta: i lettori alla cassa
        // faticano ad agganciare un codice su schermo poco luminoso.
        // Sospeso mentre sheet/fullscreen coprono il codice: quelle
        // presentazioni non generano `onDisappear` su questa view.
        .maxScreenBrightnessWhileVisible(isActive: !showEditSheet && fullscreenSide == nil)
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
            "Eliminare questa carta fedeltà?",
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
                LoyaltyCardEditSheet(card: card)
            }
        }
        // Scanner VisionKit riusato dai documenti d'identità: rilevamento
        // bordi + correzione prospettica, perfetto per una tessera fisica.
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
                tint: Color.loyaltyCardColor(hex: card?.primaryColorHex ?? "#5856D6")
            )
        }
        .task(id: photoLoadKey) {
            await loadPhotos()
        }
        // Aprire il dettaglio è il recupero vero, come per WalletTicketDetailView:
        // è per questo che la carta è stata caricata. Non produce scritture,
        // quindi il server non lo vede.
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
                AppAnalytics.contentSharedRead(type: "loyalty_card")
            }
        }
    }

    private var missingCardPlaceholder: some View {
        ContentUnavailableView(
            "Carta non trovata",
            systemImage: "creditcard.trianglebadge.exclamationmark",
            description: Text("Potrebbe essere stata eliminata o non ancora sincronizzata.")
        )
    }

    @ViewBuilder
    private func detailScroll(_ card: KBLoyaltyCard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LoyaltyCardTileView(card: card, height: 190)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Codice carta")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    WalletBarcodeView(
                        text: card.cardNumber,
                        format: card.barcodeFormat,
                        maxWidth: .infinity,
                        stretchOneDimensionalToWidth: true
                    )
                    .frame(maxWidth: .infinity)

                    // Numero carta in chiaro sotto il codice, come su Android:
                    // serve quando il lettore alla cassa non riesce a leggere il
                    // barcode e l'addetto deve digitarlo a mano.
                    if !card.cardNumber.isEmpty {
                        Text(card.cardNumber)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
                .background(KBTheme.cardBackground(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(KBTheme.separator(colorScheme).opacity(0.3), lineWidth: 0.5)
                )

                photosSection(card)

                if let note = card.note, !note.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nota")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(note)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(KBTheme.cardBackground(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(KBTheme.separator(colorScheme).opacity(0.3), lineWidth: 0.5)
                    )
                }

                destructiveBlock(for: card)
            }
            .padding(16)
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
    }

    // MARK: - Sezione foto fronte/retro

    /// Due slot (FRONTE / RETRO) con la foto della tessera fisica: se manca,
    /// un bottone fotocamera che apre lo scanner; se c'è, la miniatura
    /// tappabile (schermo intero) con menu sostituisci/elimina.
    @ViewBuilder
    private func photosSection(_ card: KBLoyaltyCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Foto della tessera")
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
        .background(KBTheme.cardBackground(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(KBTheme.separator(colorScheme).opacity(0.3), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func photoSlot(_ card: KBLoyaltyCard, side: LoyaltyCardPhotoSide) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sideTitle(side))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack {
                if let img = image(for: side) {
                    Button {
                        fullscreenSide = side
                    } label: {
                        // È il contenitore a dettare la misura, non l'immagine:
                        // con `scaledToFill` + sola altezza fissa, una foto
                        // orizzontale propone una larghezza naturale enorme e
                        // `clipShape` ritaglia il disegno ma NON la misura,
                        // allargando l'intera schermata fuori dallo schermo.
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

            // Azione esplicita invece che dietro un menu "…" sulla miniatura:
            // lì era di fatto invisibile (icona piccola sopra una foto, su un
            // riquadro da 96pt). Per sostituire una foto si elimina e si
            // riacquisisce: lo slot vuoto torna a proporre "Aggiungi".
            if image(for: side) != nil, !busySides.contains(side), !loadingSides.contains(side) {
                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        Task { await removePhoto(card, side: side) }
                    } label: {
                        Label("Elimina foto", systemImage: "trash")
                            .font(.caption)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)

                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .disabled(busySides.contains(side))
    }

    private func sideTitle(_ side: LoyaltyCardPhotoSide) -> LocalizedStringKey {
        side == .front ? "Fronte" : "Retro"
    }

    private func image(for side: LoyaltyCardPhotoSide) -> UIImage? {
        side == .front ? frontImage : backImage
    }

    private func setImage(_ image: UIImage?, for side: LoyaltyCardPhotoSide) {
        if side == .front { frontImage = image } else { backImage = image }
    }

    private func storagePath(_ card: KBLoyaltyCard, side: LoyaltyCardPhotoSide) -> String? {
        let raw = side == .front ? card.frontPhotoStoragePath : card.backPhotoStoragePath
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    /// Cambia quando cambia una delle due foto: fa ripartire il `.task` di
    /// caricamento anche dopo un aggiornamento arrivato dalla sync.
    private var photoLoadKey: String {
        guard let card else { return "" }
        return "\(card.id)|\(card.frontPhotoStoragePath ?? "")|\(card.backPhotoStoragePath ?? "")"
    }

    // MARK: - Foto: caricamento

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
                let img = try await photoStore.download(
                    familyId: card.familyId, cardId: card.id, side: side, storagePath: path)
                setImage(img, for: side)
            } catch {
                KBLog.ui.kbError("[LoyaltyCardDetail] photo load failed side=\(side.rawValue) err=\(error.localizedDescription)")
            }
            loadingSides.remove(side)
        }
    }

    // MARK: - Foto: acquisizione

    /// Lo scanner VisionKit è multi-pagina: se l'utente acquisisce fronte e
    /// retro in un'unica sessione partendo dal fronte, la seconda pagina
    /// riempie automaticamente il retro se ancora vuoto.
    private func handleScanned(pages: [UIImage], requestedSide: LoyaltyCardPhotoSide) {
        guard let card, let first = pages.first else { return }
        Task {
            await storePhoto(card, side: requestedSide, image: first)
            if requestedSide == .front, pages.count > 1, storagePath(card, side: .back) == nil {
                await storePhoto(card, side: .back, image: pages[1])
            }
        }
    }

    private func storePhoto(_ card: KBLoyaltyCard, side: LoyaltyCardPhotoSide, image: UIImage) async {
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

    private func removePhoto(_ card: KBLoyaltyCard, side: LoyaltyCardPhotoSide) async {
        busySides.insert(side)
        photoErrorMessage = nil
        defer { busySides.remove(side) }

        let path = storagePath(card, side: side)
        // Cleanup best-effort: se lo Storage non risponde, la foto resta
        // comunque staccata dalla carta e non viene più mostrata.
        do {
            try await photoStore.delete(familyId: card.familyId, cardId: card.id, side: side, storagePath: path)
        } catch {
            KBLog.sync.kbError("[LoyaltyCardDetail] photo delete failed (ignored) side=\(side.rawValue) err=\(error.localizedDescription)")
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

    private func touchAndSync(_ card: KBLoyaltyCard) {
        if let uid = Auth.auth().currentUser?.uid {
            card.updatedBy = uid
            card.updatedByName = Auth.auth().currentUser?.displayName ?? ""
        }
        card.updatedAt = .now
        card.syncState = .pendingUpsert
        try? modelContext.save()
        SyncCenter.shared.enqueueLoyaltyCardUpsert(
            cardId: card.id,
            familyId: card.familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
    }

    @ViewBuilder
    private func destructiveBlock(for card: KBLoyaltyCard) -> some View {
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

    private func deleteCard(_ card: KBLoyaltyCard) {
        card.isDeleted = true
        card.updatedAt = .now
        card.syncState = .pendingDelete
        try? modelContext.save()
        SyncCenter.shared.enqueueLoyaltyCardDelete(
            cardId: card.id,
            familyId: familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        dismiss()
    }
}

/// Sheet di modifica rapida: numero carta + nota (il brand/colore restano
/// fissi dopo la creazione — per cambiare negozio si crea una nuova carta).
private struct LoyaltyCardEditSheet: View {
    let card: KBLoyaltyCard

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var cardNumber: String
    @State private var note: String

    init(card: KBLoyaltyCard) {
        self.card = card
        _cardNumber = State(initialValue: card.cardNumber)
        _note = State(initialValue: card.note ?? "")
    }

    private var canSave: Bool {
        !cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Numero carta") {
                    TextField("Numero carta", text: $cardNumber)
                        .autocorrectionDisabled()
                }
                Section("Descrizione (opzionale)") {
                    TextField("Es. tessera intestata a...", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(card.brandName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        card.cardNumber = cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        card.note = trimmedNote.isEmpty ? nil : trimmedNote
        if let uid = Auth.auth().currentUser?.uid {
            card.updatedBy = uid
            card.updatedByName = Auth.auth().currentUser?.displayName ?? ""
        }
        card.updatedAt = .now
        card.syncState = .pendingUpsert
        try? modelContext.save()
        SyncCenter.shared.enqueueLoyaltyCardUpsert(
            cardId: card.id,
            familyId: card.familyId,
            modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        dismiss()
    }
}
