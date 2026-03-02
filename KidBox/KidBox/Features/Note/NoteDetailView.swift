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
    @Environment(\.dismiss) private var dismiss
    
    @State private var note: KBNote?
    @State private var titleText: String = ""
    @State private var bodyHTML: String = ""   // ✅ HTML
    @State private var isDirty = false
    
    @State private var isSharePresented = false
    @State private var shareText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            TextField("Titolo", text: $titleText)
                .font(.title2.weight(.bold))
                .padding(.horizontal)
                .padding(.top)
                .onChange(of: titleText) { _, _ in isDirty = true }
            
            RichTextView(html: $bodyHTML, placeholder: "Scrivi qui…")
                .padding(.horizontal, 8)
                .onChange(of: bodyHTML) { _, _ in isDirty = true }
        }
        .navigationTitle("Nota")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadOrCreate() }
        .onDisappear { if isDirty { save() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        let title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let bodyPlain = bodyHTML.htmlToPlainText().trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        var out = ""
                        if !title.isEmpty { out += "\(title)\n\n" }
                        out += bodyPlain
                        
                        shareText = out
                        isSharePresented = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                              bodyHTML.htmlToPlainText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button {
                        save()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark").font(.headline)
                    }
                    .disabled(!isDirty)
                }
            }
        }
        .sheet(isPresented: $isSharePresented) {
            ShareSheet(items: [shareText]).ignoresSafeArea()
        }
    }
    
    private func loadOrCreate() {
        let nid = noteId
        let desc = FetchDescriptor<KBNote>(predicate: #Predicate { $0.id == nid })
        
        if let existing = try? modelContext.fetch(desc).first {
            note = existing
            titleText = existing.title
            bodyHTML = existing.body
            isDirty = false
            return
        }
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        
        let n = KBNote(
            id: noteId,
            familyId: familyId,
            title: "",
            body: "", // HTML
            createdBy: uid,
            createdByName: "",
            updatedBy: uid,
            updatedByName: "",
            createdAt: .now,
            updatedAt: .now,
            isDeleted: false
        )
        n.syncState = .synced
        n.lastSyncError = nil
        
        modelContext.insert(n)
        try? modelContext.save()
        
        note = n
        titleText = ""
        bodyHTML = ""
        isDirty = false
    }
    
    private func save() {
        guard let note, isDirty else { return }
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        
        note.title = titleText
        note.body = bodyHTML
        note.updatedAt = .now
        note.updatedBy = uid
        note.updatedByName = ""
        note.syncState = .pendingUpsert
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

private extension String {
    func htmlToPlainText() -> String {
        if !self.contains("<") { return self }
        guard let data = self.data(using: .utf8) else { return self }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attr = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attr.string
        }
        return self
    }
}
