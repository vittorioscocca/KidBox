//
//  ExpenseDetailView.swift
//  KidBox
//

import SwiftUI
import SwiftData

struct ExpenseDetailView: View {
    let familyId: String
    let expenseId: String
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator
    
    @State private var expense: KBExpense? = nil
    @State private var category: KBExpenseCategory? = nil
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var vm: ExpensesViewModel? = nil
    
    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.13, green: 0.13, blue: 0.13)
        : Color(red: 0.961, green: 0.957, blue: 0.945)
    }
    
    private var cardBg: Color {
        colorScheme == .dark
        ? Color(red: 0.18, green: 0.18, blue: 0.18)
        : Color(.systemBackground)
    }
    
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            
            if let expense {
                ScrollView {
                    VStack(spacing: 20) {
                        
                        // ── Hero amount card ──────────────────────────────
                        AmountHeroCard(
                            expense: expense,
                            category: category,
                            cardBg: cardBg
                        )
                        
                        // ── Details card ─────────────────────────────────
                        DetailsCard(expense: expense, category: category, cardBg: cardBg)
                        
                        // ── Notes card ───────────────────────────────────
                        if let notes = expense.notes, !notes.isEmpty {
                            NotesCard(notes: notes, cardBg: cardBg)
                        }
                        
                        // ── Allegati (gestiti da ExpenseAttachmentService) ───
                        ExpenseAttachmentsSection(expense: expense)
                        
                        // ── Metadata ─────────────────────────────────────
                        MetadataCard(expense: expense, cardBg: cardBg)
                        
                        // ── Delete button ─────────────────────────────────
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Elimina spesa", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.red.opacity(0.1))
                                .foregroundStyle(.red)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Spesa non trovata",
                    systemImage: "exclamationmark.triangle",
                    description: Text("La spesa potrebbe essere stata eliminata.")
                )
            }
        }
        .navigationTitle("Dettaglio spesa")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if expense != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showEdit = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
        }
        .onAppear { loadData() }
        .sheet(isPresented: $showEdit, onDismiss: { loadData() }) {
            if let vm, let expense {
                AddEditExpenseView(vm: vm, expense: expense)
            }
        }
        .confirmationDialog(
            "Elimina spesa",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) { deleteAndPop() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Questa azione non può essere annullata.")
        }
    }
    
    // MARK: - Data loading
    
    private func loadData() {
        let eid = expenseId
        let fid = familyId
        
        let expDescriptor = FetchDescriptor<KBExpense>(
            predicate: #Predicate { $0.id == eid && $0.familyId == fid && $0.isDeleted == false }
        )
        expense = try? modelContext.fetch(expDescriptor).first
        
        if let catId = expense?.categoryId {
            let cid = catId
            let catDescriptor = FetchDescriptor<KBExpenseCategory>(
                predicate: #Predicate { $0.id == cid }
            )
            category = try? modelContext.fetch(catDescriptor).first
        }
        
        vm = ExpensesViewModel(familyId: familyId, modelContext: modelContext)
    }
    
    // MARK: - Delete
    
    /// FIX: usa vm.deleteExpense invece di manipolare direttamente il modello.
    /// vm.deleteExpense gestisce isDeleted, updatedAt, enqueueExpenseDelete e
    /// flushGlobal in modo che il delete venga propagato correttamente su
    /// Firestore e ricevuto dall'altro account tramite il listener realtime.
    private func deleteAndPop() {
        guard let expense, let vm else { return }
        vm.deleteExpense(expense)
        coordinator.path.removeLast()
    }
}

// MARK: - Amount Hero Card

private struct AmountHeroCard: View {
    let expense: KBExpense
    let category: KBExpenseCategory?
    let cardBg: Color
    
    private var tint: Color {
        Color(hex: category?.colorHex ?? "#9E9E9E") ?? .accentColor
    }
    
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: category?.icon ?? "ellipsis.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(tint)
            }
            
            Text(expense.amount.formatted(.currency(code: "EUR")))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            
            if let cat = category {
                Text(cat.name)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(tint.opacity(0.12))
                    .foregroundStyle(tint)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Details Card

private struct DetailsCard: View {
    let expense: KBExpense
    let category: KBExpenseCategory?
    let cardBg: Color
    
    var body: some View {
        VStack(spacing: 0) {
            DetailRow(
                icon: "text.alignleft",
                label: "Descrizione",
                value: expense.title
            )
            Divider().padding(.leading, 46)
            DetailRow(
                icon: "calendar",
                label: "Data",
                value: expense.date.formatted(.dateTime.day().month(.wide).year())
            )
            if let cat = category {
                Divider().padding(.leading, 46)
                DetailRow(
                    icon: cat.icon,
                    label: "Categoria",
                    value: cat.name,
                    iconColor: Color(hex: cat.colorHex) ?? .accentColor
                )
            }
        }
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

private struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    var iconColor: Color = .secondary
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(iconColor)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Notes Card

private struct NotesCard: View {
    let notes: String
    let cardBg: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Note", systemImage: "note.text")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(notes)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Metadata Card

private struct MetadataCard: View {
    let expense: KBExpense
    let cardBg: Color
    
    var body: some View {
        VStack(spacing: 0) {
            DetailRow(
                icon: "clock",
                label: "Aggiunta il",
                value: expense.createdAt.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
            )
            if expense.updatedAt > expense.createdAt.addingTimeInterval(5) {
                Divider().padding(.leading, 46)
                DetailRow(
                    icon: "pencil.and.clock",
                    label: "Modificata il",
                    value: expense.updatedAt.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
                )
            }
        }
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}
