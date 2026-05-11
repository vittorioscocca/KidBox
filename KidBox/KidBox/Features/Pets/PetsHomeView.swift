//
//  PetsHomeView.swift
//  KidBox
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct PetsHomeView: View {
    let familyId: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query private var pets: [KBPet]
    @Query private var petEvents: [KBPetEvent]

    @State private var showAddSheet = false

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
        colorScheme == .dark ? .white : (Color(hex: "#1A1A1A") ?? .primary)
    }

    init(familyId: String) {
        self.familyId = familyId
        let fid = familyId
        _pets = Query(
            filter: #Predicate<KBPet> { $0.familyId == fid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBPet.name, order: .forward)]
        )
        _petEvents = Query(
            filter: #Predicate<KBPetEvent> { $0.familyId == fid && $0.isDeleted == false },
            sort: [SortDescriptor(\KBPetEvent.date, order: .reverse)]
        )
    }

    var body: some View {
        Group {
            if pets.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(pets, id: \.id) { pet in
                        petRow(pet)
                            .listRowBackground(cardBackground)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("Animali")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                }
                .tint(accentOrange)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            PetFormView(familyId: familyId, existingPet: nil)
        }
        .onAppear {
            SyncCenter.shared.startPetsRealtime(familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.startPetEventsRealtime(familyId: familyId, modelContext: modelContext)
        }
        .onDisappear {
            SyncCenter.shared.stopPetsRealtime()
            SyncCenter.shared.stopPetEventsRealtime()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 52))
                .foregroundStyle(accentOrange)
            Text("Nessun animale ancora")
                .font(.custom("Nunito", size: 18).weight(.semibold))
                .foregroundStyle(titleInk)
            Button {
                showAddSheet = true
            } label: {
                Text("Aggiungi animale")
                    .font(.custom("Nunito", size: 16).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(accentOrange, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func petRow(_ pet: KBPet) -> some View {
        Button {
            coordinator.navigate(to: .petDetail(familyId: familyId, petId: pet.id))
        } label: {
            HStack(spacing: 14) {
                Text(KidBoxPetSpecies.emoji(for: pet.species))
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pet.name)
                        .font(.custom("Nunito", size: 16).weight(.semibold))
                        .foregroundStyle(titleInk)
                    if let breed = pet.breed?.trimmingCharacters(in: .whitespacesAndNewlines), !breed.isEmpty {
                        Text(breed)
                            .font(.custom("Nunito", size: 14))
                            .foregroundStyle(.secondary)
                    }
                    if let next = nextUpcomingDate(for: pet.id) {
                        Text("Prossimo: \(Self.shortDate(next))")
                            .font(.custom("Nunito", size: 12))
                            .foregroundStyle(accentOrange)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func nextUpcomingDate(for petId: String) -> Date? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        var candidates: [Date] = []
        for e in petEvents where e.petId == petId {
            if let nd = e.nextDueDate, cal.startOfDay(for: nd) >= start {
                candidates.append(nd)
            }
            let day = cal.startOfDay(for: e.date)
            if day >= start {
                candidates.append(e.date)
            }
        }
        return candidates.min()
    }

    private static let shortDF: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    private static func shortDate(_ d: Date) -> String { shortDF.string(from: d) }
}

enum KidBoxPetSpecies {
    static func emoji(for raw: String) -> String {
        switch raw.lowercased() {
        case "cane": return "🐕"
        case "gatto": return "🐈"
        case "coniglio": return "🐇"
        case "criceto": return "🐹"
        case "uccello": return "🐦"
        default: return "🐾"
        }
    }
}
