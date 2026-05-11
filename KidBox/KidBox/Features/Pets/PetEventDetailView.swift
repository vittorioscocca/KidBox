//
//  PetEventDetailView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct PetEventDetailView: View {
    let familyId: String
    let petId: String
    let eventId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var events: [KBPetEvent]

    @State private var showEdit = false
    @State private var showDelete = false

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(red: 0.13, green: 0.13, blue: 0.13)
            : Color(red: 0.961, green: 0.957, blue: 0.945)
    }

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.18, green: 0.18, blue: 0.18)
            : Color(.systemBackground)
    }

    private var accentOrange: Color { Color(hex: "#FF6B00") ?? .orange }

    private var event: KBPetEvent? { events.first }

    init(familyId: String, petId: String, eventId: String) {
        self.familyId = familyId
        self.petId = petId
        self.eventId = eventId
        let fid = familyId
        let eid = eventId
        _events = Query(filter: #Predicate<KBPetEvent> { $0.id == eid && $0.familyId == fid })
    }

    var body: some View {
        Group {
            if let e = event {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        row("Titolo", e.title)
                        row("Tipo", KidBoxPetEventType.localized(e.eventTypeRaw))
                        row("Data", Self.fmtDateTime.string(from: e.date))
                        if let nd = e.nextDueDate {
                            row("Prossima scadenza", Self.fmtDate.string(from: nd))
                        }
                        if let v = e.vetName, !v.isEmpty { row("Veterinario", v) }
                        if let c = e.cost {
                            row("Costo", KidBoxDecimalFormat.string(from: c) + " €")
                        }
                        if let n = e.notes, !n.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Note")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(n)
                                    .font(.custom("Nunito", size: 15))
                                    .foregroundStyle(.primary)
                            }
                        }
                        PetEventAttachmentsSection(eventId: e.id, familyId: familyId)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding()
                }
            } else {
                ContentUnavailableView("Evento non trovato", systemImage: "calendar")
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("Evento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if event != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showEdit = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let e = event {
                PetEventFormView(familyId: familyId, petId: petId, existingEvent: e)
            }
        }
        .alert("Eliminare questo evento?", isPresented: $showDelete) {
            Button("Annulla", role: .cancel) {}
            Button("Elimina", role: .destructive) {
                deleteEvent()
            }
        } message: {
            Text("L’operazione non può essere annullata.")
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Text(v)
                .font(.custom("Nunito", size: 16))
                .foregroundStyle(.primary)
        }
    }

    private static let fmtDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    private static let fmtDateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private func deleteEvent() {
        guard let e = event else { return }
        PetEventAttachmentService.shared.deleteAllForPetEvent(
            eventId: e.id,
            familyId: familyId,
            modelContext: modelContext
        )
        let uid = Auth.auth().currentUser?.uid ?? "local"
        e.isDeleted = true
        e.updatedAt = Date()
        e.updatedBy = uid
        e.syncState = .pendingDelete
        try? modelContext.save()
        SyncCenter.shared.enqueuePetEventDelete(eventId: e.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        coordinator.path.removeLast()
    }
}
