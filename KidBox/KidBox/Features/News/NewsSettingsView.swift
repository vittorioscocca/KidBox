//
//  NewsSettingsView.swift
//  KidBox
//
//  Impostazioni → Notizie (e l'icona in alto nella scheda Notizie).
//  L'interruttore generale e la città sono della famiglia (`NewsFamilyStore`):
//  cambiano le notizie di tutti i membri. Gli argomenti e le offerte in vista
//  sono di chi legge (`NewsPrefsStore`).
//

import SwiftUI
import SwiftData

struct NewsSettingsView: View {

    @ObservedObject private var store = NewsPrefsStore.shared
    @ObservedObject private var familyStore = NewsFamilyStore.shared
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \KBFamily.updatedAt, order: .reverse) private var families: [KBFamily]

    /// Nil da Impostazioni: la famiglia attiva, come per la scheda Notizie.
    var familyId: String? = nil

    @State private var cityQuery = ""
    @State private var isLocating = false
    @State private var placeError: String?
    @State private var resolver = NewsLocationResolver()

    private var prefs: NewsPrefs { store.prefs }
    private var family: NewsFamilySettings { familyStore.settings }
    private var resolvedFamilyId: String {
        familyId ?? coordinator.activeFamilyId ?? families.first?.id ?? ""
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { family.enabled },
                    set: { on in familyStore.update { $0.enabled = on } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notizie attive")
                        Text("Bonus, scuola, salute ed eventi vicino a te, ogni giorno")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(KBTheme.bubbleTint)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Le ricerche si pagano in messaggi AI, dalla quota della famiglia: ogni edizione al massimo 6 messaggi, e meno quando la leggono anche altre famiglie della tua zona. Incluse nei piani Pro e Max.")
                    Text("Accensione e città valgono per tutta la famiglia: le notizie trovate per uno le leggono tutti, e si pagano una volta sola.")
                }
            }

            Section {
                ForEach(NewsCategory.allCases) { cat in
                    Toggle(isOn: binding(for: cat)) {
                        HStack(spacing: 12) {
                            Image(systemName: cat.symbol)
                                .foregroundStyle(cat.tint)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cat.title)
                                Text(cat.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(cat.tint)
                    // Almeno un argomento: senza, l'edizione sarebbe vuota.
                    .disabled(prefs.categories == [cat])
                }
            } header: {
                Text("Argomenti")
            } footer: {
                Text("Gli argomenti sono solo tuoi: scegli cosa leggere senza cambiare le notizie degli altri. Gli eventi vicini arrivano con Tempo libero.")
            }

            Section {
                HStack {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(KBTheme.bubbleTint)
                    Text(verbatim: family.effectivePlace.label)
                    Spacer()
                    if family.place?.hasCity == true {
                        Button(role: .destructive) {
                            familyStore.update { p in
                                if var place = p.place {
                                    place.city = ""
                                    place.province = ""
                                    place.region = ""
                                    p.place = place
                                }
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Togli la città"))
                    }
                }
                Button {
                    Task { await useCurrentLocation() }
                } label: {
                    HStack {
                        Label("Usa la mia posizione", systemImage: "location.fill")
                        if isLocating {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isLocating)
                HStack {
                    TextField("Oppure scrivi la città", text: $cityQuery)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.search)
                        .onSubmit { Task { await searchCity() } }
                    Button("Cerca") { Task { await searchCity() } }
                        .disabled(cityQuery.trimmingCharacters(in: .whitespaces).isEmpty || isLocating)
                }
                if let placeError {
                    Text(placeError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Dove vivete")
            } footer: {
                Text("Le notizie vanno dal paese alla regione fino al comune, e gli eventi entro 60 km. Si salvano solo paese, regione e città, mai la posizione esatta.")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { prefs.personalOffers },
                    set: { on in store.update { $0.personalOffers = on } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Offerte su misura")
                        Text("Luce, gas, acqua e spesa più convenienti")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(KBTheme.bubbleTint)
            } footer: {
                Text("Si cercano solo quando tocchi «Cerca offerte», partendo dalle bollette in Casa e dalla lista della spesa. All'AI arrivano fornitore, importi, consumi e prodotti: mai nomi, indirizzi o codici dei contratti.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Notizie")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.refreshFromRemote() }
        .task(id: resolvedFamilyId) { familyStore.bind(familyId: resolvedFamilyId) }
    }

    private func binding(for cat: NewsCategory) -> Binding<Bool> {
        Binding(
            get: { prefs.categories.contains(cat) },
            set: { on in
                store.update { p in
                    var set = Set(p.categories)
                    if on { set.insert(cat) } else { set.remove(cat) }
                    p.categories = NewsCategory.allCases.filter(set.contains)
                }
            }
        )
    }

    private func useCurrentLocation() async {
        isLocating = true
        placeError = nil
        defer { isLocating = false }
        do {
            let place = try await resolver.resolveCurrentPlace()
            familyStore.update { $0.place = place }
        } catch {
            placeError = error.localizedDescription
        }
    }

    private func searchCity() async {
        let query = cityQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isLocating = true
        placeError = nil
        defer { isLocating = false }
        do {
            let place = try await resolver.resolve(cityName: query)
            familyStore.update { $0.place = place }
            cityQuery = ""
        } catch {
            placeError = error.localizedDescription
        }
    }
}
