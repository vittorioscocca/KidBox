//
//  AddEditExpenseView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// Wrapper Identifiable per URL — evita ambiguità di tipo nel ForEach
private struct IdentifiableURL: Identifiable {
    let id: String   // absoluteString
    let url: URL
    init(_ url: URL) { self.id = url.absoluteString; self.url = url }
}

// MARK: - Add / Edit Expense Sheet

struct AddEditExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var vm: ExpensesViewModel
    
    let expense: KBExpense?
    private var isEditing: Bool { expense != nil }
    
    // Form fields
    @State private var title: String               = ""
    @State private var amountString: String        = ""
    @State private var date: Date                  = Date()
    @State private var selectedCategoryId: String? = nil
    @State private var notes: String               = ""
    
    // Allegati pending (solo nuova spesa, prima del salvataggio)
    @State private var pendingURLs: [URL]          = []
    
    // Sorgente picker
    @State private var showSourcePicker            = false
    @State private var showImporter                = false
    @State private var showGallery                 = false
    @State private var showCamera                  = false
    @State private var showKidBoxPicker            = false
    
    // Validation
    @State private var showValidationError         = false
    @State private var validationMessage           = ""
    
    private var amount: Double {
        Double(amountString.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    
    private var cardBg: Color {
        colorScheme == .dark
        ? Color(red: 0.18, green: 0.18, blue: 0.18)
        : .white
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                backgroundColor.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        
                        AmountInputCard(amountString: $amountString, cardBg: cardBg)
                        
                        // Descrizione + Data
                        VStack(spacing: 0) {
                            FormFieldRow(label: "Descrizione", systemImage: "text.cursor") {
                                TextField("Es. Supermercato", text: $title)
                                    .multilineTextAlignment(.trailing)
                            }
                            Divider().padding(.leading, 46)
                            FormFieldRow(label: "Data", systemImage: "calendar") {
                                DatePicker("", selection: $date, displayedComponents: .date)
                                    .labelsHidden()
                            }
                        }
                        .padding(.vertical, 4)
                        .background(cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                        
                        // Categoria
                        CategorySelectorCard(
                            categories: vm.categories,
                            selectedId: $selectedCategoryId,
                            cardBg: cardBg
                        )
                        
                        // Note
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "note.text")
                                    .foregroundStyle(.secondary)
                                Text("Note")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            
                            TextField("Aggiungi una nota...", text: $notes, axis: .vertical)
                                .lineLimit(3...6)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 14)
                        }
                        .background(cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                        
                        // Allegati:
                        // - Nuova spesa → picker URL locali (caricati al salvataggio)
                        // - Modifica    → allegati già caricati via ExpenseAttachmentsSection
                        if let exp = expense {
                            ExpenseAttachmentsSection(expense: exp)
                        } else {
                            PendingAttachmentsCard(
                                attachmentURLs: pendingURLs.map { IdentifiableURL($0) },
                                cardBg: cardBg,
                                onAddTapped: { showSourcePicker = true },
                                onRemove: { url in pendingURLs.removeAll { $0 == url } }
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(isEditing ? "Modifica spesa" : "Nuova spesa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Salva" : "Aggiungi") { save() }
                        .fontWeight(.semibold)
                }
            }
            .alert("Errore", isPresented: $showValidationError) {
                Button("OK") {}
            } message: {
                Text(validationMessage)
            }
            // ── Source picker sheet (stesso pattern di VisitAttachmentsSection) ──
            .sheet(isPresented: $showSourcePicker) {
                AttachmentSourcePickerSheet(
                    tint: Color.accentColor,
                    onCamera: {
                        showSourcePicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showCamera = true }
                    },
                    onGallery: {
                        showSourcePicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showGallery = true }
                    },
                    onDocument: {
                        showSourcePicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showImporter = true }
                    },
                    onKidBoxDocument: {
                        showSourcePicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showKidBoxPicker = true }
                    }
                )
            }
            .sheet(isPresented: $showKidBoxPicker) {
                KidBoxDocumentPickerSheet(familyId: vm.familyId) { url in
                    pendingURLs.append(url)
                }
            }
            // ── Galleria ──────────────────────────────────────────────────────────
            .sheet(isPresented: $showGallery) {
                ImagePickerView(sourceType: .photoLibrary) { image in
                    if let data = image.jpegData(compressionQuality: 0.85) {
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString + ".jpg")
                        try? data.write(to: url)
                        pendingURLs.append(url)
                    }
                }
            }
            // ── Fotocamera ────────────────────────────────────────────────────────
            .sheet(isPresented: $showCamera) {
                ImagePickerView(sourceType: .camera) { image in
                    if let data = image.jpegData(compressionQuality: 0.85) {
                        let url = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString + ".jpg")
                        try? data.write(to: url)
                        pendingURLs.append(url)
                    }
                }
            }
            // ── File importer ─────────────────────────────────────────────────────
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                guard let urls = try? result.get() else { return }
                pendingURLs.append(contentsOf: urls)
            }
        }
        .onAppear { populate() }
    }
    
    // MARK: - Populate
    
    private func populate() {
        guard let e = expense else {
            if selectedCategoryId == nil, let filter = vm.selectedCategoryFilter {
                selectedCategoryId = filter
            }
            return
        }
        title              = e.title
        amountString       = String(format: "%.2f", e.amount)
            .replacingOccurrences(of: ".", with: ",")
        date               = e.date
        selectedCategoryId = e.categoryId
        notes              = e.notes ?? ""
    }
    
    // MARK: - Save
    
    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else {
            validationMessage = "Inserisci una descrizione per la spesa."
            showValidationError = true
            return
        }
        guard amount > 0 else {
            validationMessage = "Inserisci un importo valido."
            showValidationError = true
            return
        }
        
        let notesVal = notes.trimmingCharacters(in: .whitespaces).isEmpty
        ? nil
        : notes.trimmingCharacters(in: .whitespaces)
        
        if let e = expense {
            vm.updateExpense(e, title: trimmedTitle, amount: amount,
                             date: date, categoryId: selectedCategoryId, notes: notesVal)
        } else {
            let newExpense = vm.addExpenseReturning(
                title: trimmedTitle,
                amount: amount,
                date: date,
                categoryId: selectedCategoryId,
                notes: notesVal,
                createdByUid: nil
            )
            // Avvia upload degli allegati pending tramite KBEventBus
            if !pendingURLs.isEmpty {
                KBEventBus.shared.emit(KBAppEvent.expenseAttachmentPending(
                    urls: pendingURLs,
                    expenseId: newExpense.id,
                    expenseTitle: newExpense.title,
                    familyId: newExpense.familyId
                ))
            }
        }
        dismiss()
    }
}

// MARK: - Pending Attachments Card

/// Card usata solo nella creazione di una nuova spesa.
/// Gli URL selezionati rimangono locali finché l'utente non tocca "Aggiungi":
/// a quel punto vengono passati all'ExpenseAttachmentService via KBEventBus.
private struct PendingAttachmentsCard: View {
    let attachmentURLs: [IdentifiableURL]
    let cardBg: Color
    let onAddTapped: () -> Void
    let onRemove: (URL) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            HStack {
                Label("Ricevute e allegati", systemImage: "paperclip")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.accentColor)
                Spacer()
                if !attachmentURLs.isEmpty {
                    Text("\(attachmentURLs.count)/5")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text("Aggiungi foto, PDF o documenti alla spesa")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if !attachmentURLs.isEmpty {
                VStack(spacing: 6) {
                    ForEach(attachmentURLs, id: \.id) { (item: IdentifiableURL) in
                        HStack(spacing: 10) {
                            if let img = UIImage(contentsOfFile: item.url.path) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(Color.accentColor.opacity(0.1))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: fileIcon(for: item.url))
                                        .font(.system(size: 16))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            Text(item.url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                onRemove(item.url)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.accentColor.opacity(0.05))
                        )
                    }
                }
            }
            
            Button(action: onAddTapped) {
                Label("Aggiungi allegato", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.opacity(0.08))
                    )
                    .foregroundStyle(Color.accentColor)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .disabled(attachmentURLs.count >= 5)
        }
        .padding(16)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
    
    private func fileIcon(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":                        return "doc.fill"
        case "jpg", "jpeg", "png", "heic": return "photo.fill"
        case "doc", "docx":                return "doc.text.fill"
        default:                           return "paperclip"
        }
    }
}

// MARK: - Amount Input Card

private struct AmountInputCard: View {
    @Binding var amountString: String
    let cardBg: Color
    @FocusState private var focused: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Text("Importo")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            ZStack {
                TextField("0,00", text: $amountString)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .focused($focused)
                
                HStack {
                    Text("€")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .onTapGesture { focused = true }
    }
}

// MARK: - Form Field Row

private struct FormFieldRow<Content: View>: View {
    let label: String
    let systemImage: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.subheadline)
            Spacer()
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

// MARK: - Category Selector Card

private struct CategorySelectorCard: View {
    let categories: [KBExpenseCategory]
    @Binding var selectedId: String?
    let cardBg: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundStyle(.secondary)
                Text("Categoria")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    CategoryPill(name: "Nessuna", icon: "xmark.circle",
                                 colorHex: "#9E9E9E", isSelected: selectedId == nil) {
                        selectedId = nil
                    }
                    ForEach(categories) { cat in
                        CategoryPill(name: cat.name, icon: cat.icon,
                                     colorHex: cat.colorHex, isSelected: selectedId == cat.id) {
                            selectedId = cat.id
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 14)
        }
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

private struct CategoryPill: View {
    let name: String
    let icon: String
    let colorHex: String
    let isSelected: Bool
    let onTap: () -> Void
    
    private var tint: Color { Color(hex: colorHex) ?? .accentColor }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 13))
                Text(name).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? tint : tint.opacity(0.12))
            .foregroundStyle(isSelected ? .white : tint)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(tint.opacity(isSelected ? 0 : 0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
