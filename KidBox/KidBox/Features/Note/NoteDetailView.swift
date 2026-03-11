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
    
    // ✅ @Query osserva automaticamente i cambiamenti da SyncCenter (listener realtime)
    @Query private var queriedNotes: [KBNote]
    
    // Stato locale — fonte di verità mentre la nota è aperta
    @State private var titleText: String   = ""
    @State private var bodyHTML:  String   = ""
    @State private var isDirty            = false
    @State private var note: KBNote?      = nil
    @State private var bodyFocusTrigger: UUID? = nil
    @State private var isSharePresented   = false
    
    // ✅ Versione remota ricevuta mentre editing è attivo:
    //    tenuta da parte e applicata solo quando si esce senza salvare.
    @State private var pendingRemoteTitle: String? = nil
    @State private var pendingRemoteBody:  String? = nil
    
    init(familyId: String, noteId: String) {
        self.familyId = familyId
        self.noteId   = noteId
        let nid = noteId
        _queriedNotes = Query(filter: #Predicate<KBNote> { $0.id == nid && $0.familyId == familyId })
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // ── Titolo ────────────────────────────────────────────────────
            NoteTitleTextField(text: $titleText, placeholder: "Titolo") {
                bodyFocusTrigger = UUID()
            }
            .padding(.top, 12)
            .padding(.leading, 8)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: titleText) { isDirty = true }
            
            // ── Corpo ─────────────────────────────────────────────────────
            RichTextView(html: $bodyHTML, placeholder: "Scrivi qui…",
                         focusTrigger: bodyFocusTrigger)
            .padding(.top, 12)
            .onChange(of: bodyHTML) { isDirty = true }
        }
        .padding(.horizontal, 16)
        .navigationTitle("Nota")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear  {
            loadOrCreate()
            Task { @MainActor in
                BadgeManager.shared.clearNotes()
                BadgeManager.shared.refreshAppBadge()
                await CountersService.shared.reset(familyId: familyId, field: .notes)
            }
        }
        .onDisappear { handleDisappear() }
        
        // ✅ Ascolta aggiornamenti da SwiftData (es. listener realtime che aggiorna la nota)
        //    MA li applica all'UI solo se non stiamo editando (isDirty = false).
        .onChange(of: noteRemoteVersion) { _, _ in
            guard let n = queriedNotes.first else { return }
            if isDirty {
                // Editing in corso: salva la versione remota per dopo, non sovrascrivere
                pendingRemoteTitle = n.title
                pendingRemoteBody  = n.body
            } else {
                // Nessuna modifica locale: aggiorna l'UI con il remoto
                titleText = n.title
                bodyHTML  = n.body
                note      = n
            }
        }
        
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button { isSharePresented = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                              bodyHTML.htmlToPlainText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button { saveAndDismiss() } label: {
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
    
    // MARK: - Computed: versione remota della nota per onChange
    
    /// Proxy per rilevare aggiornamenti remoti: cambia ogni volta che SwiftData aggiorna la nota.
    private var noteRemoteVersion: Date {
        queriedNotes.first?.updatedAt ?? .distantPast
    }
    
    // MARK: - Load / Create
    
    private func loadOrCreate() {
        if let existing = queriedNotes.first {
            note      = existing
            titleText = existing.title
            bodyHTML  = existing.body
            isDirty   = false
            return
        }
        
        // Crea nuova nota
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
    
    // MARK: - Disappear
    
    private func handleDisappear() {
        if isDirty {
            // L'utente ha modificato: salva le modifiche locali
            commitSave()
        }
        // Non applicare il pendingRemote: se l'utente ha salvato,
        // il sync aggiornerà Firestore con la versione corretta.
        // Se non ha salvato (back senza salvare), le modifiche vengono scartate
        // e la prossima apertura rilegge da SwiftData (che ha già il remoto).
    }
    
    private func saveAndDismiss() {
        commitSave()
        dismiss()
    }
    
    // MARK: - Save
    
    private func commitSave() {
        guard let note else { return }
        guard isDirty else { return }
        
        let uid = Auth.auth().currentUser?.uid ?? "local"
        
        note.title         = titleText
        note.body          = bodyHTML
        note.updatedAt     = .now
        note.updatedBy     = uid
        note.updatedByName = ""
        note.syncState     = .pendingUpsert
        note.lastSyncError = nil
        
        try? modelContext.save()
        
        SyncCenter.shared.enqueueNoteUpsert(
            noteId: note.id, familyId: familyId, modelContext: modelContext
        )
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        
        isDirty            = false
        pendingRemoteTitle = nil
        pendingRemoteBody  = nil
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
