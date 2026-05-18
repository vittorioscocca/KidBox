//
//  TravelDiscoverView.swift
//  KidBox
//

import SwiftUI

struct TravelDiscoverView: View {

    let familyId: String
    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var vm: TravelDiscoverViewModel
    @State private var showLoading = true

    private let accent = Color(red: 0.95, green: 0.38, blue: 0.10)

    init(familyId: String, userId: String) {
        self.familyId = familyId
        _vm = StateObject(wrappedValue: TravelDiscoverViewModel(familyId: familyId, userId: userId))
    }

    var body: some View {
        Group {
            if showLoading && vm.isLoading && vm.destinations.isEmpty {
                TravelPlanningLoadingView(
                    destinationName: "le destinazioni",
                    subtitle: "Sto cercando i posti giusti per te"
                )
            } else if let error = vm.errorMessage, vm.destinations.isEmpty {
                ContentUnavailableView(
                    "Suggerimenti non disponibili",
                    systemImage: "sparkles",
                    description: Text(error)
                )
            } else {
                suggestionsList
            }
        }
        .navigationTitle("Per te, questa settimana")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await vm.loadSuggestions(force: true) }
                } label: {
                    Label("Nuovi", systemImage: "arrow.clockwise")
                }
                .disabled(vm.isLoading)
            }
        }
        .task {
            await vm.loadSuggestions()
            showLoading = false
        }
    }

    private var suggestionsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(vm.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let top = vm.destinations.first(where: { $0.isTopMatch }) ?? vm.destinations.first {
                    Button {
                        openDestination(top)
                    } label: {
                        topMatchCard(top)
                    }
                    .buttonStyle(.plain)
                }

                ForEach(vm.destinations.filter { !$0.isTopMatch }) { destination in
                    Button {
                        openDestination(destination)
                    } label: {
                        compactCard(destination)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .overlay {
            if vm.isLoading && !vm.destinations.isEmpty {
                ProgressView()
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
        }
    }

    private func openDestination(_ destination: TravelDestination) {
        coordinator.navigate(to: .travelDestinationDetail(familyId: familyId, destinationId: destination.id))
    }

    private func topMatchCard(_ destination: TravelDestination) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                TravelDestinationImageView(destinationName: destination.name, height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                LinearGradient(
                    colors: [.clear, .black.opacity(0.65)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(accent).frame(width: 8, height: 8)
                            Text("MIGLIOR SCELTA")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                    Text(destination.name)
                        .font(.title.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(destination.tagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack {
                    Text("\(destination.estimatedCost) · \(destination.durationDays) giorni")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(destination.bestTime)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.green)
                }
            }
            .padding(14)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }

    private func compactCard(_ destination: TravelDestination) -> some View {
        HStack(spacing: 14) {
            TravelDestinationImageView(destinationName: destination.name, height: 88)
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(destination.name)
                    .font(.headline)
                Text(destination.region)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(destination.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(destination.estimatedCost) · \(destination.durationDays) giorni")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
