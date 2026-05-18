//
//  TravelDestinationSearchField.swift
//  KidBox
//

import Combine
import MapKit
import SwiftUI

@MainActor
final class TravelPlaceSearchVM: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query: String = "" { didSet { updateCompleter() } }
    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var isSearching = false

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
    }

    private func updateCompleter() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            suggestions = []
            isSearching = false
            completer.cancel()
        } else {
            isSearching = true
            completer.queryFragment = trimmed
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            suggestions = completer.results
            isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            suggestions = []
            isSearching = false
        }
    }
}

struct TravelDestinationSearchField: View {
    @Binding var destinationName: String
    @Binding var destinationRegion: String
    var onSelectionChanged: () -> Void = {}

    @StateObject private var searchVM = TravelPlaceSearchVM()
    @FocusState private var isFocused: Bool
    @State private var showSuggestions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Es. Procida, Barcellona…", text: $searchVM.query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .onChange(of: searchVM.query) { _, newValue in
                        destinationName = newValue
                        destinationRegion = ""
                        showSuggestions = isFocused && !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        onSelectionChanged()
                    }
                    .onChange(of: isFocused) { _, focused in
                        showSuggestions = focused && !searchVM.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    .onAppear {
                        searchVM.query = destinationName
                    }

                if searchVM.isSearching {
                    ProgressView()
                        .scaleEffect(0.75)
                } else if !searchVM.query.isEmpty {
                    Button {
                        searchVM.query = ""
                        destinationName = ""
                        destinationRegion = ""
                        showSuggestions = false
                        onSelectionChanged()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if showSuggestions, !searchVM.suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(searchVM.suggestions.prefix(6), id: \.self) { result in
                        Button {
                            select(result)
                        } label: {
                            TravelPlaceSuggestionRow(result: result)
                        }
                        .buttonStyle(.plain)

                        if result != searchVM.suggestions.prefix(6).last {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            } else if !destinationName.isEmpty, !destinationRegion.isEmpty {
                selectedPreview
            }
        }
    }

    private var selectedPreview: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(destinationName).font(.headline)
                Text(destinationRegion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func select(_ result: MKLocalSearchCompletion) {
        destinationName = result.title
        destinationRegion = result.subtitle
        searchVM.query = result.title
        showSuggestions = false
        isFocused = false
        onSelectionChanged()
    }
}

private struct TravelPlaceSuggestionRow: View {
    let result: MKLocalSearchCompletion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
