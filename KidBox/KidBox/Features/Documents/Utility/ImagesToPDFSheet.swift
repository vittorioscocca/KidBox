//
//  ImagesToPDFSheet.swift
//  KidBox
//

import SwiftUI
internal import os

/// Foglio di conferma per «Trasforma in PDF»: nome del file e, quando le
/// immagini sono più d'una, l'ordine delle pagine.
///
/// Con una sola immagine la lista riordinabile non ha senso e viene omessa:
/// resta solo il nome, che è l'unica cosa da decidere.
struct ImagesToPDFSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onConvert: ([KBDocument], String) async -> Void

    @State private var orderedDocs: [KBDocument]
    @State private var pdfTitle: String = ""
    @State private var isConverting = false

    init(docs: [KBDocument], onConvert: @escaping ([KBDocument], String) async -> Void) {
        _orderedDocs = State(initialValue: docs)
        self.onConvert = onConvert
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Nome del PDF") {
                    TextField("Es. Ricevuta", text: $pdfTitle)
                        .textInputAutocapitalization(.sentences)
                }

                if orderedDocs.count > 1 {
                    Section {
                        ForEach(Array(orderedDocs.enumerated()), id: \.element.id) { index, doc in
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Color.orange, in: Circle())

                                Text(doc.title.isEmpty ? doc.fileName : doc.title)
                                    .font(.subheadline)
                                    .lineLimit(1)

                                Spacer()

                                Image(systemName: "photo.fill")
                                    .foregroundStyle(.orange.opacity(0.8))
                                    .font(.title3)
                            }
                            .padding(.vertical, 2)
                        }
                        .onMove { from, to in
                            orderedDocs.move(fromOffsets: from, toOffset: to)
                        }
                    } header: {
                        HStack {
                            Text("Ordine pagine (\(orderedDocs.count) immagini)")
                            Spacer()
                            Label("Trascina per riordinare", systemImage: "line.3.horizontal")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Trasforma in PDF")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(orderedDocs.count > 1 ? .active : .inactive))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
                        .disabled(isConverting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await startConversion() }
                    } label: {
                        if isConverting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                        } else {
                            Text("Crea").bold()
                        }
                    }
                    .disabled(isConverting || finalTitle.isEmpty)
                }
            }
            .interactiveDismissDisabled(isConverting)
        }
        .onAppear { pdfTitle = suggestedTitle }
    }

    // MARK: - Helpers

    /// Da una sola immagine si eredita il suo nome; da più immagini il nome non
    /// può venire da una in particolare, quindi si dichiara quante sono.
    private var suggestedTitle: String {
        guard let first = orderedDocs.first else { return "Documento" }
        let base = first.title.isEmpty ? first.fileName : first.title
        let nameNoExt = (base as NSString).deletingPathExtension
        return orderedDocs.count == 1 ? nameNoExt : "\(nameNoExt) (+\(orderedDocs.count - 1))"
    }

    private var finalTitle: String {
        pdfTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func startConversion() async {
        guard !finalTitle.isEmpty else { return }
        isConverting = true
        defer { isConverting = false }

        KBLog.data.kbInfo("ImagesToPDFSheet startConversion count=\(orderedDocs.count) title=\(finalTitle)")
        await onConvert(orderedDocs, finalTitle)
        dismiss()
    }
}
