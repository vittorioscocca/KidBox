//
//  GroceryQuickAdd.swift
//  KidBox
//
//  Inserimento veloce nella lista della spesa, come i to-do: il «+» apre una
//  scheda in cima col nome a fuoco, una nota e la quantità. «Invio» salva e
//  apre la successiva (si detta la spesa una voce dopo l'altra); la «i» salva
//  e apre la scheda completa (`GroceryEditView`). La categoria la sceglie
//  l'app dopo il salvataggio, come dalla scheda.
//

import SwiftUI
import SwiftData

struct GroceryQuickDraft: Equatable {
    /// Id della voce che nascerà: con Handoff la stessa bozza salvata su due
    /// dispositivi resta una voce sola.
    var id = UUID().uuidString
    var name = ""
    var notes = ""
    var quantity = 1

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isEmpty: Bool { trimmedName.isEmpty }
}

enum GroceryQuickAdd {

    @MainActor
    @discardableResult
    static func create(_ draft: GroceryQuickDraft, familyId: String, modelContext: ModelContext) -> String? {
        guard !draft.isEmpty else { return nil }
        let draftId = draft.id
        if ((try? modelContext.fetchCount(FetchDescriptor<KBGroceryItem>(
            predicate: #Predicate { $0.id == draftId }
        ))) ?? 0) > 0 { return draftId }
        let uid = KBUid.current ?? "local"
        let now = Date()
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let fid = familyId
        let isFirst = ((try? modelContext.fetchCount(FetchDescriptor<KBGroceryItem>(
            predicate: #Predicate { $0.familyId == fid && $0.isDeleted == false }
        ))) ?? 0) == 0

        let item = KBGroceryItem(
            id: draftId,
            familyId: familyId,
            name: draft.trimmedName,
            category: nil,
            notes: notes.isEmpty ? nil : notes,
            // 1 resta `nil`, come dalla scheda.
            quantity: draft.quantity > 1 ? draft.quantity : nil,
            createdAt: now,
            updatedAt: now,
            updatedBy: uid,
            createdBy: uid
        )
        item.syncState = .pendingUpsert
        modelContext.insert(item)
        try? modelContext.save()
        SyncCenter.shared.enqueueGroceryUpsert(itemId: item.id, familyId: familyId, modelContext: modelContext)
        GroceryCategoryClassifier.assignMissing(
            to: [(id: item.id, name: item.name)], familyId: familyId, modelContext: modelContext)
        AppAnalytics.contentCreated(type: "grocery")
        if isFirst { AppAnalytics.featureFirstUse(feature: "grocery") }
        Task { await SyncCenter.shared.flushGrocery(modelContext: modelContext) }
        return item.id
    }
}

extension GroceryQuickDraft {
    var handoff: KBHandoffDraft {
        KBHandoffDraft(kind: .grocery, fields: [
            "id": id, "name": name, "notes": notes,
            "quantity": quantity > 1 ? String(quantity) : nil,
        ])
    }

    init(handoff d: KBHandoffDraft) {
        self.init()
        if let v = d.fields["id"] { id = v }
        name = d.fields["name"] ?? ""
        notes = d.fields["notes"] ?? ""
        quantity = d.fields["quantity"].flatMap(Int.init).map { min(99, max(1, $0)) } ?? 1
    }
}

enum GroceryQuickField: Hashable { case name, notes }

struct GroceryQuickAddCard: View {
    @Binding var draft: GroceryQuickDraft
    var focus: FocusState<GroceryQuickField?>.Binding
    let background: Color
    let onSubmit: () -> Void
    let onInfo: () -> Void

    @State private var chipsShown = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                TextField("", text: $draft.name)
                    .font(.system(size: 17, weight: .semibold))
                    .autocorrectionDisabled()
                    .focused(focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit(onSubmit)

                TextField("Aggiungi nota", text: $draft.notes, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1...3)
                    .focused(focus, equals: .notes)

                HStack(spacing: 8) {
                    quantityChip.chipEntrance(chipsShown, index: 0)
                }
                .padding(.top, 2)
            }

            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dettagli")
        }
        .padding(14)
        .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.green.opacity(0.35), lineWidth: 1)
        )
        .onAppear {
            focus.wrappedValue = .name
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75).delay(0.1)) { chipsShown = true }
        }
    }

    /// Meno e più dentro la capsula; da 2 in su si colora.
    private var quantityChip: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { draft.quantity = max(1, draft.quantity - 1) }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 34, height: 36)
                    .contentShape(Rectangle())
            }
            .disabled(draft.quantity <= 1)

            Text("×\(draft.quantity)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(draft.quantity)))
                .frame(minWidth: 28)

            Button {
                withAnimation(.snappy) { draft.quantity = min(99, draft.quantity + 1) }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 34, height: 36)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(draft.quantity > 1 ? Color.green : Color.primary)
        .background(Capsule().fill(draft.quantity > 1 ? Color.green.opacity(0.15) : Color(.tertiarySystemFill)))
        .sensoryFeedback(.selection, trigger: draft.quantity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quantità")
        .accessibilityValue("\(draft.quantity)")
    }
}
