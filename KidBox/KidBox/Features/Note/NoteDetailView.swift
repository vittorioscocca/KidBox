//
//  NoteDetailView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct NoteDetailView: View {
    let familyId: String
    let noteId: String
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    
    @State private var titleText: String = ""
    @State private var bodyHTML:  String = ""
    @State private var isDirty           = false
    @State private var note: KBNote?     = nil
    @State private var bodyFocusTrigger: UUID? = nil
    
    @State private var isSharePresented = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // ── Titolo ────────────────────────────────────────────────────
            NoteTitleTextField(text: $titleText, placeholder: "Titolo") {
                bodyFocusTrigger = UUID()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .fixedSize(horizontal: false, vertical: true)   // ← altezza stretta al contenuto
            .onChange(of: titleText) { isDirty = true }
            
            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 6)
            
            // ── Corpo ─────────────────────────────────────────────────────
            RichTextView(html: $bodyHTML, placeholder: "Scrivi qui…")
                .onChange(of: bodyHTML) { isDirty = true }
        }
        .navigationTitle("Nota")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadOrCreate() }
        .onDisappear { saveIfNeeded() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        isSharePresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                              bodyHTML.htmlToPlainText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button {
                        saveIfNeeded()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark").font(.headline)
                    }
                    .disabled(!isDirty)
                }
            }
        }
        .sheet(isPresented: $isSharePresented) {
            let title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
            let body  = bodyHTML.htmlToPlainText().trimmingCharacters(in: .whitespacesAndNewlines)
            let text  = [title, body].filter { !$0.isEmpty }.joined(separator: "\n\n")
            ShareSheet(items: [text]).ignoresSafeArea()
        }
    }
    
    // MARK: - Load / Create
    
    private func loadOrCreate() {
        let nid  = noteId
        let desc = FetchDescriptor<KBNote>(predicate: #Predicate { $0.id == nid })
        
        if let existing = try? modelContext.fetch(desc).first {
            note      = existing
            titleText = existing.title
            bodyHTML  = existing.body
            isDirty   = false
            return
        }
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let n = KBNote(
            id: noteId, familyId: familyId,
            title: "", body: "",
            createdBy: uid, createdByName: "",
            updatedBy: uid, updatedByName: "",
            createdAt: .now, updatedAt: .now,
            isDeleted: false
        )
        n.syncState     = .synced
        n.lastSyncError = nil
        modelContext.insert(n)
        try? modelContext.save()
        
        note      = n
        titleText = ""
        bodyHTML  = ""
        isDirty   = false
    }
    
    // MARK: - Save
    
    private func saveIfNeeded() {
        guard let note, isDirty else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        note.title         = titleText
        note.body          = bodyHTML
        note.updatedAt     = .now
        note.updatedBy     = uid
        note.updatedByName = ""
        note.syncState     = .pendingUpsert
        note.lastSyncError = nil
        try? modelContext.save()
        SyncCenter.shared.enqueueNoteUpsert(noteId: note.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        isDirty = false
    }
}

// MARK: - ShareSheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - String extension

private extension String {
    func htmlToPlainText() -> String {
        guard self.contains("<"), let data = self.data(using: .utf8) else { return self }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        return (try? NSAttributedString(data: data, options: options,
                                        documentAttributes: nil))?.string ?? self
    }
}
