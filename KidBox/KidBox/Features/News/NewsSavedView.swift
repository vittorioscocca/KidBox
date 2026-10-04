//
//  NewsSavedView.swift
//  KidBox
//
//  Le notizie salvate col segnalibro (dall'icona in alto nella scheda
//  Notizie). Dalla più recente; si aprono come nella scheda, e si eliminano
//  scorrendo, dal menu della notizia, a gruppi con «Seleziona» o tutte
//  insieme. Sono di chi le salva (`NewsSavedStore`), sincronizzate fra i suoi
//  dispositivi; Android ha la stessa schermata (`NewsSavedScreen.kt`).
//

import SwiftUI

struct NewsSavedView: View {

    @ObservedObject private var store = NewsSavedStore.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<String>()
    @State private var openedLink: NewsLink?
    @State private var confirmDeleteAll = false

    private var isEditing: Bool { editMode.isEditing }

    var body: some View {
        Group {
            if !store.isLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.items.isEmpty {
                ContentUnavailableView {
                    Label("Nessuna notizia salvata", systemImage: "bookmark")
                } description: {
                    Text("Tocca il segnalibro su una notizia per ritrovarla qui, anche quando non è più nell'edizione del giorno.")
                }
            } else {
                list
            }
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Notizie salvate")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .environment(\.editMode, $editMode)
        .sheet(item: $openedLink) { link in
            NewsSafariView(link: link).ignoresSafeArea()
        }
        .confirmationDialog("Eliminare tutte le notizie salvate?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Elimina tutte", role: .destructive) {
                store.removeAll()
                endEditing()
            }
        } message: {
            Text("Spariscono da tutti i tuoi dispositivi. Gli articoli restano sui siti delle fonti.")
        }
        .onChange(of: store.items) { _, items in
            // Tolte da un altro dispositivo: fuori anche dalla selezione.
            selection.formIntersection(items.map(\.id))
            if items.isEmpty { endEditing() }
        }
        .task { store.bind() }
    }

    // MARK: - Elenco

    private var list: some View {
        List(selection: $selection) {
            ForEach(store.items) { saved in
                NewsItemCard(item: saved.item, placeName: saved.placeName) {
                    open(saved)
                }
                .labelStyle(NewsCardLabelStyle())
                // Selezionando, il tocco sceglie la riga invece di aprire.
                .allowsHitTesting(!isEditing)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        store.remove(ids: [saved.id])
                    } label: {
                        Label("Elimina", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        open(saved)
                    } label: {
                        Label("Apri", systemImage: "safari")
                    }
                    if let url = URL(string: saved.item.url) {
                        ShareLink(item: url) {
                            Label("Condividi", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button(role: .destructive) {
                        store.remove(ids: [saved.id])
                    } label: {
                        Label("Elimina", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Barra

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !store.items.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing {
                    // Il «fatto» di sistema: la chiave «Fine» del catalogo vale
                    // anche per la fine di una data, e in inglese è «End».
                    Button(role: .confirm) { endEditing() }
                } else {
                    Menu {
                        Button {
                            withAnimation { editMode = .active }
                        } label: {
                            Label("Seleziona", systemImage: "checkmark.circle")
                        }
                        Button(role: .destructive) {
                            confirmDeleteAll = true
                        } label: {
                            Label("Elimina tutte", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel(Text("Altre azioni"))
                }
            }
        }
        if isEditing {
            ToolbarItem(placement: .bottomBar) {
                if selection.count == store.items.count {
                    Button("Deseleziona tutte") { selection.removeAll() }
                } else {
                    Button("Seleziona tutte") { selection = Set(store.items.map(\.id)) }
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) {
                    store.remove(ids: selection)
                    selection.removeAll()
                } label: {
                    Text("Elimina (\(selection.count))")
                }
                .tint(.red)
                .disabled(selection.isEmpty)
            }
        }
    }

    // MARK: - Azioni

    private func endEditing() {
        withAnimation {
            editMode = .inactive
            selection.removeAll()
        }
    }

    private func open(_ saved: NewsSavedItem) {
        guard let url = URL(string: saved.item.url), url.scheme?.hasPrefix("http") == true else { return }
        openedLink = NewsLink(url: url, item: saved.item, placeName: saved.placeName)
        AppAnalytics.newsItemOpened(kind: "saved", category: saved.item.category, level: saved.item.level)
    }
}
