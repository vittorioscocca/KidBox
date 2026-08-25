//
//  KidBoxMediaPickerSheet.swift
//  KidBox
//
//  Selettore dei media già presenti in KidBox, per allegarli in chat.
//

import SwiftUI
import SwiftData

/// Griglia dei media della libreria KidBox, con selezione multipla.
///
/// Serve a condividere in chat una foto già caricata in KidBox senza doverla
/// riesportare a mano sul rullino. Legge dalla stessa sorgente della sezione
/// Foto e Video, quindi l'elenco è già sincronizzato.
struct KidBoxMediaPickerSheet: View {

    /// Tetto allineato al resto degli allegati chat.
    private static let maxSelection = 10

    let familyId: String
    let onConfirm: ([KBFamilyPhoto]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \KBFamilyPhoto.takenAt, order: .reverse) private var allPhotos: [KBFamilyPhoto]
    @State private var selectedIds: [String] = []

    private var photos: [KBFamilyPhoto] {
        allPhotos.filter { $0.familyId == familyId && !$0.isDeleted }
    }

    /// Tre colonne a spaziatura minima, come la griglia di Foto di sistema.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        NavigationStack {
            Group {
                if photos.isEmpty {
                    ContentUnavailableView(
                        "Nessun media in KidBox",
                        systemImage: "photo.on.rectangle",
                        description: Text("Non ci sono ancora foto o video in KidBox.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(photos, id: \.id) { photo in
                                cell(for: photo)
                            }
                        }
                        .padding(2)
                    }
                }
            }
            .navigationTitle("Scegli da KidBox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selectedIds.isEmpty ? "Invia" : "Invia (\(selectedIds.count))") {
                        let picked = selectedIds.compactMap { id in
                            photos.first { $0.id == id }
                        }
                        onConfirm(picked)
                    }
                    .disabled(selectedIds.isEmpty)
                }
            }
        }
    }

    private func cell(for photo: KBFamilyPhoto) -> some View {
        let isSelected = selectedIds.contains(photo.id)
        // `Color.clear` + aspectRatio fissa la cella quadrata PRIMA di disegnarci
        // dentro l'immagine: senza, `scaledToFill` faceva debordare le foto sulle
        // celle vicine e la griglia risultava sfalsata.
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                thumbnail(for: photo)
                    .scaledToFill()
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if photo.mimeType.hasPrefix("video/") {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            .overlay {
                // Velo + spunta sulla selezione, come nella libreria Foto.
                if isSelected {
                    Color.black.opacity(0.28)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white, Color.accentColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isSelected {
                    selectedIds.removeAll { $0 == photo.id }
                } else if selectedIds.count < Self.maxSelection {
                    // Oltre il tetto il tocco non fa nulla: meglio di un errore
                    // dopo la conferma.
                    selectedIds.append(photo.id)
                }
            }
    }

    @ViewBuilder
    private func thumbnail(for photo: KBFamilyPhoto) -> some View {
        // La miniatura salvata in locale evita di scaricare gli originali solo
        // per scorrere la griglia: servono soltanto al momento dell'invio.
        if let base64 = photo.thumbnailBase64,
           let data = Data(base64Encoded: base64),
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
        } else if let localPath = photo.localPath,
                  let image = UIImage(contentsOfFile: localPath) {
            Image(uiImage: image)
                .resizable()
        } else {
            Rectangle()
                .fill(.quaternary)
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }
}
