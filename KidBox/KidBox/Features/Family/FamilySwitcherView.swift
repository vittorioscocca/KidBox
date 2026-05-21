//
//  FamilySwitcherView.swift
//  KidBox
//

import SwiftUI
import SwiftData

struct FamilySwitcherView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]

    @State private var showCreateSheet = false
    @State private var newFamilyName = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(families) { family in
                        FamilyRowView(
                            family: family,
                            isActive: coordinator.activeFamilyId == family.id
                        ) {
                            let service = MultiFamilyService(
                                modelContext: modelContext,
                                coordinator: coordinator
                            )
                            service.switchToFamily(family.id)
                            dismiss()
                        }
                    }
                }

                Section {
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("Crea nuova famiglia", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Le tue famiglie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                createFamilySheet
            }
            .alert(
                "Errore",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var createFamilySheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome famiglia (es. Famiglia Rossi)", text: $newFamilyName)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    Text("I documenti, le note e i profili saranno separati dalle altre famiglie.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        createFamily()
                    } label: {
                        HStack {
                            Spacer()
                            if isCreating {
                                ProgressView()
                            } else {
                                Text("Crea famiglia")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(
                        newFamilyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isCreating
                    )
                }
            }
            .navigationTitle("Nuova famiglia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        showCreateSheet = false
                        newFamilyName = ""
                    }
                    .disabled(isCreating)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func createFamily() {
        let trimmed = newFamilyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isCreating = true
        let service = MultiFamilyService(modelContext: modelContext, coordinator: coordinator)
        Task {
            do {
                let familyId = try await service.createEmptyFamily(name: trimmed)
                service.switchToFamily(familyId)
                showCreateSheet = false
                newFamilyName = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }
}

// MARK: - FamilyRowView

private struct FamilyRowView: View {
    let family: KBFamily
    let isActive: Bool
    let onTap: () -> Void

    private var heroURL: URL? {
        guard let raw = family.heroPhotoURL, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    @ViewBuilder
    private var familyAvatar: some View {
        ZStack {
            if let heroURL {
                AsyncImage(url: heroURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderAvatar
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholderAvatar
                    }
                }
            } else {
                placeholderAvatar
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    private var placeholderAvatar: some View {
        ZStack {
            Circle()
                .fill(Color(.secondarySystemFill))
            Image(systemName: "house.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                familyAvatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(family.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if isActive {
                        Text("Famiglia attiva")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
