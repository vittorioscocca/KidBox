//
//  HomeTipsView.swift
//  KidBox
//
//  Elenco di suggerimenti sulle funzionalità dell'app: una card per ogni
//  sezione della Home, al tap mostra un suggerimento su cosa si può fare lì.
//

import SwiftUI

struct HomeTipItem: Identifiable, Hashable {
    let id: String
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    let tip: LocalizedStringKey

    static func == (lhs: HomeTipItem, rhs: HomeTipItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// La sezione a cui il suggerimento si riferisce.
    ///
    /// Serve al pulsante "Vai": leggere cosa si può fare in una sezione e poi
    /// doverla cercare a mano nella Home è il punto in cui il suggerimento
    /// smette di essere utile. `nil` per i pochi id che non hanno una
    /// destinazione propria, così il pulsante semplicemente non compare invece
    /// di portare da qualche parte a caso.
    func destination(familyId: String) -> HomeDestination? {
        switch id {
        case "note":       return .notes(familyId: familyId)
        case "todo":       return .todo
        case "shopping":   return .shopping(familyId: familyId)
        case "calendar":   return .calendar(familyId: familyId)
        case "health":     return .pediatric(familyId: familyId, childId: "")
        case "documents":  return .document
        case "expenses":   return .expenses(familyId: familyId)
        case "wallet":     return .wallet(familyId: familyId)
        case "passwords":  return .passwords(familyId: familyId)
        case "location":   return .familyLocation(familyId: familyId)
        case "photos":     return .familyPhotos(familyId: familyId)
        case "family":     return .familySettings
        case "pets":       return .pets(familyId: familyId)
        case "home_items": return .homeItems(familyId: familyId)
        case "vehicles":   return .vehicles(familyId: familyId)
        case "travel":     return .travel(familyId: familyId)
        case "expert":     return .askExpert
        default:           return nil
        }
    }
}

enum HomeTipsCatalog {
    static let items: [HomeTipItem] = [
        .init(id: "note", title: "Note", symbol: "note.text", tint: .yellow,
              tip: "Scrivi note libere o formattate (grassetto, corsivo, liste) e scegli se condividerle con tutta la famiglia o tenerle solo per te."),
        .init(id: "todo", title: "To-Do", symbol: "checklist", tint: .blue,
              tip: "Crea liste di attività e assegnale a un membro della famiglia. Quando qualcuno spunta un'attività, tutti la vedono aggiornata all'istante."),
        .init(id: "shopping", title: "Lista della Spesa", symbol: "cart.fill", tint: .green,
              tip: "La lista della spesa è condivisa in tempo reale: se un familiare spunta un prodotto al supermercato, lo vedi subito anche tu. I prodotti sono organizzati per categoria per fare la spesa più in fretta."),
        .init(id: "calendar", title: "Calendario", symbol: "calendar", tint: .purple,
              tip: "Un calendario unico per tutta la famiglia, con categorie colorate ed eventi ricorrenti. Puoi collegare un evento a una visita o a un vaccino, così non dimentichi mai una scadenza sanitaria."),
        .init(id: "health", title: "Salute", symbol: "heart.fill", tint: .red,
              tip: "Gestisci cartella clinica, vaccini, visite ed esami di ogni bambino. Chiedi all'assistente AI un riepilogo dello stato di salute o un consiglio basato sullo storico clinico."),
        .init(id: "documents", title: "Documenti", symbol: "doc.text", tint: .orange,
              tip: "Carica e condividi documenti e immagini con i membri della famiglia che scegli, oppure tienili solo per te. Se un PDF è protetto da password puoi rimuoverla direttamente dall'app, e selezionando più PDF puoi unirli in un unico file."),
        .init(id: "expenses", title: "Spese", symbol: "eurosign.circle", tint: .mint,
              tip: "Traccia le spese di famiglia per categoria, allega scontrini e foto e scopri a colpo d'occhio chi ha speso cosa e quando."),
        .init(id: "wallet", title: "Wallet", symbol: "ticket.fill", tint: .indigo,
              tip: "Conserva biglietti, tessere e documenti d'identità della famiglia in un unico posto, sempre a portata di mano anche senza connessione."),
        .init(id: "passwords", title: "Password", symbol: "key.fill", tint: Color(hex: "#5E5CE6") ?? .blue,
              tip: "Salva le password di famiglia in modo sicuro e condividile solo con chi vuoi. Ogni password mostra un indicatore di robustezza, così sai subito quali conviene cambiare."),
        .init(id: "location", title: "Posizione", symbol: "location.fill", tint: .cyan,
              tip: "Condividi la posizione in tempo reale con la famiglia e crea zone (geofence) per essere avvisato quando un bambino entra o esce da un luogo, come scuola o casa."),
        .init(id: "photos", title: "Foto e video", symbol: "photo.stack.fill", tint: .pink,
              tip: "Raccogli le foto e i video importanti della famiglia in album condivisi, organizzati automaticamente per data."),
        .init(id: "family", title: "Family", symbol: "person.2.fill", tint: .teal,
              tip: "Gestisci i membri della famiglia, invita un nuovo genitore con un QR code e tieni sotto controllo chi fa parte del nucleo familiare."),
        .init(id: "pets", title: "Animali domestici", symbol: "pawprint.fill", tint: Color(hex: "#FF9500") ?? .orange,
              tip: "Tieni traccia di vaccini, visite veterinarie e promemoria per ogni animale domestico di famiglia."),
        .init(id: "home_items", title: "Casa", symbol: "house.fill", tint: Color(hex: "#8B6914") ?? .brown,
              tip: "Registra elettrodomestici, garanzie e scadenze di manutenzione della casa, con promemoria automatici quando si avvicina una scadenza."),
        .init(id: "vehicles", title: "Garage", symbol: "car.fill", tint: Color(hex: "#1A1A1A") ?? .primary,
              tip: "Tieni sotto controllo bollo, assicurazione, revisione e manutenzioni di ogni veicolo di famiglia, senza dimenticare le scadenze."),
        .init(id: "travel", title: "Viaggi", symbol: "suitcase.fill", tint: .teal,
              tip: "Organizza i tuoi viaggi con itinerari, documenti e checklist, il tutto condiviso con chi parte con te."),
        .init(id: "expert", title: "Assistente AI", symbol: "brain.head.profile", tint: .purple,
              tip: "Chiedi qualsiasi cosa sulla tua famiglia: l'assistente conosce salute, documenti, spese, calendario e password, e può creare eventi o promemoria al posto tuo."),
    ]
}

struct HomeTipsView: View {
    /// La navigazione resta della Home, che possiede il coordinator: questa
    /// schermata è un foglio, e spingere una destinazione dal suo stack la
    /// aprirebbe dentro il foglio invece che nell'app.
    var familyId: String = ""
    var onNavigate: ((HomeDestination) -> Void)?

    @State private var selectedTip: HomeTipItem?
    /// Ricalcolato all'apertura: la checklist può essere stata chiusa o
    /// completata dopo che questa schermata è stata istanziata.
    @State private var canRestoreChecklist = OnboardingChecklistState.isRestorable
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Il recupero vive qui e non nelle Impostazioni: è la stessa
            // domanda dei suggerimenti ("cosa posso fare con quest'app?"), e chi
            // ha chiuso la card per sbaglio la cerca dove cerca l'aiuto.
            if canRestoreChecklist {
                Section {
                    Button {
                        OnboardingChecklistState.restore()
                        canRestoreChecklist = false
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "checklist")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            Text("Rivedi i primi passi")
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                ForEach(HomeTipsCatalog.items) { item in
                    Button {
                        selectedTip = item
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(item.tint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            Text(item.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear { canRestoreChecklist = OnboardingChecklistState.isRestorable }
        .navigationTitle("Suggerimenti")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedTip) { item in
            HomeTipDetailSheet(
                item: item,
                destination: item.destination(familyId: familyId),
                onGo: { destination in
                    selectedTip = nil
                    // Il foglio dei suggerimenti va chiuso prima di navigare:
                    // restando aperto coprirebbe la schermata appena raggiunta.
                    dismiss()
                    onNavigate?(destination)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct HomeTipDetailSheet: View {
    let item: HomeTipItem
    let destination: HomeDestination?
    let onGo: (HomeDestination) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: item.symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(item.tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.top, 12)

                Text(item.title)
                    .font(.title3.bold())

                Text(item.tip)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)

                Spacer(minLength: 0)

                if let destination {
                    Button {
                        onGo(destination)
                    } label: {
                        Text("Vai")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(item.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }
}
