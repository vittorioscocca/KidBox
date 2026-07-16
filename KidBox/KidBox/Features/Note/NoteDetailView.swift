//
//  NoteDetailView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth
import UIKit

struct NoteDetailView: View {

    @EnvironmentObject private var coordinator: AppCoordinator
    let familyId: String
    let noteId: String
    /// Porta il focus sul corpo all’apertura (es. nota viaggio appena creata).
    var focusBodyOnAppear: Bool = false
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.colorScheme)  private var colorScheme
    
    // MARK: - Dynamic theme (same as LoginView)
    
    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    
    // ✅ @Query osserva automaticamente i cambiamenti da SyncCenter (listener realtime)
    @Query private var queriedNotes: [KBNote]
    @Query private var members: [KBFamilyMember]
    
    // Stato locale — fonte di verità mentre la nota è aperta
    @State private var titleText: String   = ""
    @State private var bodyHTML:  String   = ""
    @State private var isDirty            = false
    @State private var note: KBNote?      = nil
    @State private var bodyFocusTrigger: UUID? = nil
    @State private var shareItem: ShareItem?
    @State private var isViewActive       = false
    @State private var isVisibilitySheetPresented = false
    @State private var showVisibilityLockedAlert = false
    @State private var selectedVisibilityScope = KBVisibilityScope.family
    @State private var selectedVisibilityMemberIds: Set<String> = []

    /// Store per il bridge RichTextView ↔ toolbar Mac Catalyst
    @StateObject private var richTextStore = NoteRichTextStore()
    
    // ✅ Versione remota ricevuta mentre editing è attivo:
    //    tenuta da parte e applicata solo quando si esce senza salvare.
    @State private var pendingRemoteTitle: String? = nil
    @State private var pendingRemoteBody:  String? = nil
    
    init(familyId: String, noteId: String, focusBodyOnAppear: Bool = false) {
        self.familyId = familyId
        self.noteId   = noteId
        self.focusBodyOnAppear = focusBodyOnAppear
        let nid = noteId
        _queriedNotes = Query(filter: #Predicate<KBNote> { $0.id == nid && $0.familyId == familyId })
        let fid = familyId
        _members = Query(
            filter: #Predicate<KBFamilyMember> { $0.familyId == fid && !$0.isDeleted },
            sort: \.displayName
        )
    }
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 0) {
                visibilityChip
                    .padding(.top, 10)
                    .padding(.leading, 8)
                
                // ── Titolo ────────────────────────────────────────────────────
                NoteTitleTextField(text: $titleText, placeholder: "Titolo") {
                    bodyFocusTrigger = UUID()
                }
                .padding(.top, 12)
                .padding(.leading, 8)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: titleText) { isDirty = true }
                
                // ── Corpo ─────────────────────────────────────────────────────
                // ✅ La UITextView gestisce lo scroll internamente tramite contentInset.
                //    ignoresSafeArea(.keyboard) impedisce a SwiftUI di shrinkare il frame
                //    quando compare la tastiera — altrimenti la tv perde altezza e non scrolla.
                RichTextView(html: $bodyHTML, placeholder: "Scrivi qui…",
                             focusTrigger: bodyFocusTrigger,
                             store: richTextStore)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 12)
                .ignoresSafeArea(.keyboard)
                .onChange(of: bodyHTML) { isDirty = true }
            }
            .padding(.horizontal, 16)
        }
        .navigationTitle("Nota")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard let n = note else { return }
            let origin = coordinator.consumeRetrievalOrigin()
            Task {
                await KBAnalytics.shared.logRetrieval(
                    feature: .note,
                    uploaderUid: n.createdBy,
                    createdAt: n.createdAt,
                    entryPoint: origin
                )
            }
        }
        #if targetEnvironment(macCatalyst)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MacNoteFormattingBar(store: richTextStore)
        }
        #endif
        .onAppear  {
            isViewActive = true
            loadOrCreate()
            if focusBodyOnAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    bodyFocusTrigger = UUID()
                }
            }
            Task { @MainActor in
                BadgeManager.shared.clearNotes()
                BadgeManager.shared.refreshAppBadge()
                await CountersService.shared.reset(familyId: familyId, field: .notes)
            }
        }
        .onDisappear {
            isViewActive = false
            handleDisappear()
        }
        
        // ✅ Ascolta aggiornamenti da SwiftData (es. listener realtime che aggiorna la nota)
        //    MA li applica all'UI solo se non stiamo editando (isDirty = false).
        .onChange(of: noteRemoteVersion) { _, _ in
            guard isViewActive else { return }
            guard let n = queriedNotes.first else { return }
            if isDirty {
                // Editing in corso: salva la versione remota per dopo, non sovrascrivere
                pendingRemoteTitle = n.title
                pendingRemoteBody  = n.body
            } else {
                // Nessuna modifica locale: aggiorna l'UI con il remoto
                titleText = n.title
                bodyHTML  = n.body.normalizedKidBoxChecklistGlyphs()
                selectedVisibilityScope = KBVisibilityScope.normalized(n.visibilityScope)
                selectedVisibilityMemberIds = Set(n.visibilityMemberIds ?? [])
                note      = n
            }
        }
        
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button { presentShareSheet() } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                    .disabled(titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                              bodyHTML.htmlToPlainText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if isDirty {
                        Button { saveAndDismiss() } label: {
                            Image(systemName: "checkmark").font(.headline)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: isDirty)
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.text])
                .ignoresSafeArea()
        }
        .sheet(isPresented: $isVisibilitySheetPresented) {
            VisibilityPickerSheet(
                selectedScope: $selectedVisibilityScope,
                selectedMemberIds: $selectedVisibilityMemberIds,
                members: selectableMembers,
                currentUid: currentUid,
                scopeSectionTitle: "Chi può vedere questa nota"
            ) { scope, memberIds in
                selectedVisibilityScope = scope
                selectedVisibilityMemberIds = memberIds
                isDirty = true
            }
        }
        .alert("Visibilità bloccata", isPresented: $showVisibilityLockedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Solo chi ha creato la nota può modificare la visibilità.")
        }
    }
    
    // MARK: - Computed: versione remota della nota per onChange
    
    /// Proxy per rilevare aggiornamenti remoti: cambia ogni volta che SwiftData aggiorna la nota.
    private var noteRemoteVersion: Date {
        queriedNotes.first?.updatedAt ?? .distantPast
    }

    private var currentUid: String? {
        Auth.auth().currentUser?.uid
    }

    private var canEditVisibility: Bool {
        guard let uid = currentUid else { return false }
        guard let n = note else { return true }
        let cid = n.createdBy.trimmingCharacters(in: .whitespacesAndNewlines)
        if cid.isEmpty { return true }
        return cid == uid
    }

    private var selectableMembers: [KBFamilyMember] {
        members.filter { $0.userId != currentUid }
    }

    @ViewBuilder
    private var visibilityChip: some View {
        Button {
            if canEditVisibility {
                isVisibilitySheetPresented = true
            } else {
                showVisibilityLockedAlert = true
            }
        } label: {
            Text(KBVisibilityScope.chipLabel(for: selectedVisibilityScope))
                .font(.custom("Nunito", size: 14))
                .foregroundStyle(Color(red: 0.102, green: 0.102, blue: 0.102))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(red: 0.949, green: 0.941, blue: 0.922))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Load / Create
    
    private func loadOrCreate() {
        if let existing = queriedNotes.first {
            note      = existing
            titleText = existing.title
            bodyHTML  = existing.body.normalizedKidBoxChecklistGlyphs()
            selectedVisibilityScope = KBVisibilityScope.normalized(existing.visibilityScope)
            selectedVisibilityMemberIds = Set(existing.visibilityMemberIds ?? [])
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
        selectedVisibilityScope = KBVisibilityScope.normalized(n.visibilityScope)
        selectedVisibilityMemberIds = Set(n.visibilityMemberIds ?? [])
        isDirty   = false
    }
    
    // MARK: - Disappear
    
    private func presentShareSheet() {
        let title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let body  = bodyHTML.htmlToPlainText().trimmingCharacters(in: .whitespacesAndNewlines)
        let text  = [title, body].filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !text.isEmpty else { return }
        // Evita di pubblicare stato durante un ciclo di update della view (es. sync in uscita).
        Task { @MainActor in
            shareItem = ShareItem(text: text)
        }
    }

    private func handleDisappear() {
        guard isDirty else { return }
        let shouldSave = true
        Task { @MainActor in
            guard shouldSave, isDirty else { return }
            commitSave()
        }
        // Non applicare il pendingRemote: se l'utente ha salvato,
        // il sync aggiornerà Firestore con la versione corretta.
        // Se non ha salvato (back senza salvare), le modifiche vengono scartate
        // e la prossima apertura rilegge da SwiftData (che ha già il remoto).
    }
    
    private func saveAndDismiss() {
        commitSave()
        hideKeyboard()
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
        note.visibilityScope = selectedVisibilityScope
        note.visibilityMemberIds = selectedVisibilityScope == KBVisibilityScope.members
        ? Array(selectedVisibilityMemberIds).sorted()
        : []
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

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

}

// MARK: - Mac Catalyst Formatting Bar

#if targetEnvironment(macCatalyst)
/// Barra di formattazione fissa in basso per Mac Catalyst (sostituisce inputAccessoryView).
private struct MacNoteFormattingBar: View {
    @ObservedObject var store: NoteRichTextStore
    @State private var showStylePanel = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                // Aa — stili testo (popover)
                Button {
                    showStylePanel.toggle()
                } label: {
                    Text("Aa")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(showStylePanel ? Color.accentColor : Color.primary.opacity(0.80))
                        .frame(width: 46, height: 36)
                        .background {
                            if showStylePanel { Capsule().fill(Color.accentColor.opacity(0.13)) }
                        }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showStylePanel, arrowEdge: .bottom) {
                    macStylePanel
                }
                .onChange(of: store.toolbarModel.isExpanded) { _, newVal in
                    if !newVal { showStylePanel = false }
                }

                sep

                // Formattazione inline
                fmtIcon("bold",          on: store.toolbarModel.isBold)          { store.execute(.bold) }
                fmtIcon("italic",        on: store.toolbarModel.isItalic)        { store.execute(.italic) }
                fmtIcon("underline",     on: store.toolbarModel.isUnderline)     { store.execute(.underline) }
                fmtIcon("strikethrough", on: store.toolbarModel.isStrikethrough) { store.execute(.strikethrough) }

                sep

                // Liste
                fmtIcon("list.bullet",
                         on: store.toolbarModel.activeList == .bullet)    { store.execute(.bullet) }
                fmtIcon("list.number",
                         on: store.toolbarModel.activeList == .number)    { store.execute(.number) }
                fmtIcon(store.toolbarModel.activeList == .checklist ? "checkmark.circle.fill" : "checkmark.circle",
                         on: store.toolbarModel.activeList == .checklist) { store.execute(.checklist) }

                sep

                // Indentazione
                fmtIcon("decrease.indent", on: false) { store.execute(.indentLess) }
                fmtIcon("increase.indent", on: false) { store.execute(.indentMore) }

                Spacer()
            }
            .frame(height: 44)
            .padding(.horizontal, 8)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Style popover content

    private var macStylePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stile testo")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .kerning(0.7)

            HStack(spacing: 8) {
                styleCard("T", "Intestazione", .bold,     22) { store.execute(.heading);    showStylePanel = false }
                styleCard("T", "Sottoint.",    .semibold, 17) { store.execute(.subheading); showStylePanel = false }
                styleCard("T", "Corpo",        .regular,  14) { store.execute(.body);       showStylePanel = false }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private func styleCard(_ preview: String, _ label: String,
                           _ weight: Font.Weight, _ size: CGFloat,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(preview).font(.system(size: size, weight: weight)).foregroundStyle(Color.primary)
                Text(label).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.055)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func fmtIcon(_ sf: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: sf)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(on ? Color.accentColor : Color.primary.opacity(0.72))
                .frame(width: 36, height: 36)
                .background {
                    if on { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor.opacity(0.13)) }
                }
        }
        .buttonStyle(.plain)
    }

    private var sep: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 0.33, height: 18)
            .padding(.horizontal, 4)
    }
}
#endif

// MARK: - Share

private struct ShareItem: Identifiable {
    let id = UUID()
    let text: String
}

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
    
    /// Allinea i marker checklist vecchi (Android ☐/☑) a quelli usati su iOS (○/◉).
    func normalizedKidBoxChecklistGlyphs() -> String {
        self
            .replacingOccurrences(of: "☐ ", with: "○ ")
            .replacingOccurrences(of: "☑ ", with: "◉ ")
    }
}
