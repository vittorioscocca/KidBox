//
//  Kblocationsearchfield.swift
//  KidBox
//
//  Created by vscocca on 13/03/26.
//

import SwiftUI
import MapKit
import Combine

// MARK: - ViewModel

@MainActor
final class KBLocationSearchVM: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    
    @Published var query:       String = "" { didSet { updateCompleter() } }
    @Published var suggestions: [MKLocalSearchCompletion] = []
    @Published var isSearching: Bool = false
    
    private let completer = MKLocalSearchCompleter()
    
    override init() {
        super.init()
        completer.delegate     = self
        completer.resultTypes  = [.address, .pointOfInterest]
        // Limita ai risultati con indirizzo fisico
        completer.pointOfInterestFilter = .includingAll
    }
    
    private func updateCompleter() {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            suggestions = []
            isSearching = false
            completer.cancel()
        } else {
            isSearching = true
            completer.queryFragment = q
        }
    }
    
    // MARK: - MKLocalSearchCompleterDelegate
    
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.suggestions = completer.results
            self.isSearching = false
        }
    }
    
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = []
            self.isSearching = false
        }
    }
    
    /// Compone la stringa leggibile da un suggerimento (titolo + sottotitolo).
    func fullText(of result: MKLocalSearchCompletion) -> String {
        let sub = result.subtitle
        if sub.isEmpty { return result.title }
        return "\(result.title), \(sub)"
    }
}

// MARK: - View

/// Campo testo con autocomplete indirizzi.
/// Uso:
/// ```swift
/// KBLocationSearchField(location: $location, tint: tint)
/// ```
struct KBLocationSearchField: View {
    
    @Binding var location: String
    var tint: Color = .accentColor
    
    @StateObject private var vm = KBLocationSearchVM()
    @State private var showSuggestions = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // ── Campo testo ──
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(tint)
                
                TextField("Es: Ospedale Civile, Via Roma 1", text: $vm.query)
                    .focused($isFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .onChange(of: vm.query) { _, new in
                        location          = new
                        showSuggestions   = isFocused && !new.trimmingCharacters(in: .whitespaces).isEmpty
                    }
                    .onChange(of: isFocused) { _, focused in
                        showSuggestions = focused && !vm.query.trimmingCharacters(in: .whitespaces).isEmpty
                    }
                    .onAppear {
                        // Sincronizza il testo iniziale (edit mode)
                        vm.query = location
                    }
                
                if vm.isSearching {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else if !vm.query.isEmpty {
                    Button {
                        vm.query      = ""
                        location      = ""
                        showSuggestions = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // ── Suggerimenti ──
            if showSuggestions && !vm.suggestions.isEmpty {
                Divider().padding(.top, 6)
                
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(vm.suggestions.prefix(5), id: \.self) { result in
                        Button {
                            let full      = vm.fullText(of: result)
                            vm.query      = full
                            location      = full
                            showSuggestions = false
                            isFocused     = false
                        } label: {
                            SuggestionRow(result: result, tint: tint)
                        }
                        .buttonStyle(.plain)
                        
                        if result != vm.suggestions.prefix(5).last {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - SuggestionRow

private struct SuggestionRow: View {
    let result: MKLocalSearchCompletion
    let tint:   Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .foregroundStyle(tint.opacity(0.8))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                highlightedText(result.title, ranges: result.titleHighlightRanges)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                
                if !result.subtitle.isEmpty {
                    highlightedText(result.subtitle, ranges: result.subtitleHighlightRanges)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
    
    /// Evidenzia in grassetto le parti corrispondenti alla query.
    private func highlightedText(_ text: String, ranges: [NSValue]) -> Text {
        var result     = Text("")
        var lastEnd    = text.startIndex
        let nsText     = text as NSString
        
        let nsRanges: [NSRange] = ranges.compactMap { $0.rangeValue }
        
        for nsRange in nsRanges {
            guard let range = Range(nsRange, in: text) else { continue }
            // Testo normale prima del match
            if lastEnd < range.lowerBound {
                result = result + Text(text[lastEnd..<range.lowerBound])
            }
            // Testo in grassetto (match)
            result  = result + Text(text[range]).bold()
            lastEnd = range.upperBound
        }
        // Resto del testo
        if lastEnd < text.endIndex {
            result = result + Text(text[lastEnd...])
        }
        return result
    }
}
