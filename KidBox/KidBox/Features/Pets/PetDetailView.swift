//
//  PetDetailView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct PetDetailView: View {
    let familyId: String
    let petId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var pets: [KBPet]
    @Query private var events: [KBPetEvent]
    @Query private var petTreatments: [KBTreatment]

    @State private var showEditPet = false
    @State private var showAddEvent = false
    @State private var showAddTreatment = false
    @State private var showDeletePet = false

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

    private var titleInk: Color {
        colorScheme == .dark ? .primary : (Color(hex: "#1A1A1A") ?? .primary)
    }

    private var pet: KBPet? { pets.first }

    private var petEvents: [KBPetEvent] { events }

    init(familyId: String, petId: String) {
        self.familyId = familyId
        self.petId = petId
        let fid = familyId
        let pid = petId
        _pets = Query(filter: #Predicate<KBPet> { $0.id == pid && $0.familyId == fid })
        _events = Query(
            filter: #Predicate<KBPetEvent> { $0.familyId == fid && $0.petId == pid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBPetEvent.date, order: .reverse)]
        )
        _petTreatments = Query(
            filter: #Predicate<KBTreatment> { $0.familyId == fid && $0.petId == pid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBTreatment.updatedAt, order: .reverse)]
        )
    }

    var body: some View {
        Group {
            if let p = pet {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerCard(p)
                        curesSection()
                        sectionTitle("Storico eventi")
                        if petEvents.isEmpty {
                            Text("Nessun evento registrato")
                                .font(.custom("Nunito", size: 15))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(petEvents, id: \.id) { ev in
                                    eventRow(ev)
                                    Divider()
                                }
                            }
                            .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("Animale domestico non trovato", systemImage: "pawprint")
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle(pet?.name ?? "Animale domestico")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                if pet != nil {
                    Menu {
                        Button {
                            showAddTreatment = true
                        } label: {
                            Label("Nuova cura", systemImage: "pills.fill")
                        }
                        Button {
                            showAddEvent = true
                        } label: {
                            Label("Nuovo evento", systemImage: "calendar.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(accentOrange)
                    Button {
                        showEditPet = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    Menu {
                        Button(role: .destructive) {
                            showDeletePet = true
                        } label: {
                            Label("Elimina animale", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditPet) {
            if let p = pet {
                PetFormView(familyId: familyId, existingPet: p)
            }
        }
        .sheet(isPresented: $showAddEvent) {
            PetEventFormView(familyId: familyId, petId: petId, existingEvent: nil)
        }
        .sheet(isPresented: $showAddTreatment) {
            if let p = pet {
                PediatricTreatmentEditView(
                    familyId: familyId,
                    childId: "",
                    childName: p.name,
                    treatmentId: nil,
                    initialPetId: petId
                )
            }
        }
        .alert("Eliminare questo animale?", isPresented: $showDeletePet) {
            Button("Annulla", role: .cancel) {}
            Button("Elimina", role: .destructive) {
                deletePet()
            }
        } message: {
            Text("Verrà rimosso per tutta la famiglia. Gli eventi collegati verranno eliminati.")
        }
        .onAppear {
            SyncCenter.shared.startPetsRealtime(familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.startPetEventsRealtime(familyId: familyId, modelContext: modelContext)
        }
    }

    @ViewBuilder
    private func headerCard(_ p: KBPet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(KidBoxPetSpecies.emoji(for: p.species))
                    .font(.system(size: 44))
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.name)
                        .font(.custom("Nunito", size: 22).weight(.bold))
                        .foregroundStyle(titleInk)
                    if let b = p.breed?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty {
                        Text(b)
                            .font(.custom("Nunito", size: 15))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let birth = p.birthDate {
                let years = Calendar.current.dateComponents([.year], from: birth, to: Date()).year ?? 0
                labeled("Data di nascita", "\(PetDetailView.shortDate(birth)) (\(years) anni)")
            }
            if let chip = p.chipCode?.trimmingCharacters(in: .whitespacesAndNewlines), !chip.isEmpty {
                labeled("Microchip", chip)
            }
            if let col = p.color?.trimmingCharacters(in: .whitespacesAndNewlines), !col.isEmpty {
                labeled("Colore", col)
            }
            if let n = p.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                Text(n)
                    .font(.custom("Nunito", size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func curesSection() -> some View {
        sectionTitle("Cure")
        if petTreatments.isEmpty {
            Text("Aggiungi farmaci, orari delle dosi, allegati e promemoria — come nella sezione Salute.")
                .font(.custom("Nunito", size: 15))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        } else {
            VStack(spacing: 0) {
                ForEach(petTreatments, id: \.id) { t in
                    NavigationLink {
                        TreatmentDetailView(treatment: t)
                    } label: {
                        petTreatmentRow(t)
                    }
                    Divider()
                }
            }
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    @ViewBuilder
    private func petTreatmentRow(_ t: KBTreatment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "pills.fill")
                .foregroundStyle(accentOrange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(t.drugName)
                        .font(.custom("Nunito", size: 16).weight(.semibold))
                        .foregroundStyle(titleInk)
                    if t.reminderEnabled, t.isActive {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(accentOrange)
                    }
                }
                Text("\(t.dosageValue, specifier: "%.0f") \(t.dosageUnit) · \(t.frequencyDisplayLabel)")
                    .font(.custom("Nunito", size: 13))
                    .foregroundStyle(.secondary)
                if !t.scheduleTimes.isEmpty {
                    Text("Orari: \(t.scheduleTimes.joined(separator: ", "))")
                        .font(.custom("Nunito", size: 12))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    private func labeled(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(v)
                .font(.custom("Nunito", size: 15))
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .font(.custom("Nunito", size: 13).weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func eventRow(_ ev: KBPetEvent) -> some View {
        Button {
            coordinator.navigate(to: .petEventDetail(familyId: familyId, petId: petId, eventId: ev.id))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: KidBoxPetEventType.symbol(for: ev.eventTypeRaw))
                    .foregroundStyle(accentOrange)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 6) {
                    Text(ev.title)
                        .font(.custom("Nunito", size: 16).weight(.semibold))
                        .foregroundStyle(titleInk)
                    Text(PetDetailView.shortDateTime(ev.date))
                        .font(.custom("Nunito", size: 13))
                        .foregroundStyle(.secondary)
                    if let nd = ev.nextDueDate {
                        Text("Prossima: \(PetDetailView.shortDate(nd))")
                            .font(.custom("Nunito", size: 12).weight(.medium))
                            .foregroundStyle(accentOrange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(accentOrange.opacity(colorScheme == .dark ? 0.28 : 0.15), in: Capsule())
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
        .buttonStyle(.plain)
    }

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    private static let dtf: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private static func shortDate(_ d: Date) -> String { df.string(from: d) }
    private static func shortDateTime(_ d: Date) -> String { dtf.string(from: d) }

    private func deletePet() {
        guard let p = pet else { return }
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let pid = p.id
        let fid = familyId
        let treatDesc = FetchDescriptor<KBTreatment>(
            predicate: #Predicate<KBTreatment> { $0.petId == pid && $0.familyId == fid && $0.isDeleted == false }
        )
        if let trs = try? modelContext.fetch(treatDesc) {
            for t in trs {
                TreatmentNotificationManager.cancel(treatmentId: t.id)
                t.isDeleted = true
                t.updatedAt = now
                t.updatedBy = uid
                t.syncState = .pendingDelete
                SyncCenter.shared.enqueueTreatmentDelete(treatmentId: t.id, familyId: familyId, modelContext: modelContext)
            }
        }
        for ev in events where ev.petId == p.id && !ev.isDeleted {
            ev.isDeleted = true
            ev.updatedAt = now
            ev.updatedBy = uid
            ev.syncState = .pendingDelete
            SyncCenter.shared.enqueuePetEventDelete(eventId: ev.id, familyId: familyId, modelContext: modelContext)
        }
        p.isDeleted = true
        p.updatedAt = now
        p.updatedBy = uid
        p.syncState = .pendingDelete
        try? modelContext.save()
        SyncCenter.shared.enqueuePetDelete(petId: p.id, familyId: familyId, modelContext: modelContext)
        SyncCenter.shared.flushGlobal(modelContext: modelContext)
        coordinator.path.removeLast()
    }
}

enum KidBoxPetEventType {
    static func symbol(for raw: String) -> String {
        switch raw {
        case "vaccine": return "syringe"
        case "vet_visit": return "stethoscope"
        case "medication": return "pills"
        case "grooming": return "scissors"
        default: return "calendar"
        }
    }

    static func localized(_ raw: String) -> String {
        switch raw {
        case "vaccine": return "Vaccino"
        case "vet_visit": return "Visita veterinaria"
        case "medication": return "Farmaco"
        case "grooming": return "Toelettatura"
        default: return "Altro"
        }
    }
}
