//
//  NotificationSettingsView.swift
//  KidBox
//
//  Created by vscocca on 06/03/26.
//

import SwiftUI
import SwiftData
import Combine
internal import os

struct NotificationSettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    /// Specchio di `NudgeState.isOptedOut`, che è una `static` su UserDefaults
    /// e quindi non osservabile. Senza questo `@State` SwiftUI non avrebbe
    /// nessuna dipendenza da cui ridisegnare: il Toggle tornerebbe indietro da
    /// solo appena toccato, pur avendo salvato il valore giusto.
    @State private var nudgesEnabled = !NudgeState.isOptedOut
    
    // MARK: - Dynamic theme (same as LoginView)
    
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
    
    var body: some View {
        List {
            Toggle(
                "Notifica nuovi documenti",
                isOn: Binding(
                    get: { vm.notifyOnNewDocs },
                    set: { newValue in
                        KBLog.settings.kbInfo("Toggle notifyOnNewDocs set=\(newValue)")
                        vm.notifyOnNewDocs = newValue
                        vm.toggleNotifyOnNewDocs(newValue)
                    }
                )
            )
            .disabled(vm.isLoading)
            .listRowBackground(cardBackground)
            
            Toggle(
                "Notifica nuovi messaggi in chat",
                isOn: Binding(
                    get: { vm.notifyOnNewMessages },
                    set: { vm.toggleNotifyOnNewMessages($0) }
                )
            )
            .disabled(vm.isLoading)
            .listRowBackground(cardBackground)
            
            Toggle(
                "Notifiche posizione (inizio/fine condivisione)",
                isOn: Binding(
                    get: { vm.notifyOnLocationSharing },
                    set: { newValue in
                        KBLog.settings.kbInfo("Toggle notifyOnLocationSharing set=\(newValue)")
                        vm.notifyOnLocationSharing = newValue
                        vm.toggleNotifyOnLocationSharing(newValue)
                    }
                )
            )
            .disabled(vm.isLoading)
            .listRowBackground(cardBackground)
            
            Toggle(
                "Notifiche Todo (assegnazioni/scadenze)",
                isOn: Binding(
                    get: { vm.notifyOnTodos },
                    set: { vm.toggleNotifyOnTodos($0) }
                )
            )
            .disabled(vm.isLoading)
            .listRowBackground(cardBackground)
            
            Toggle(
                "Notifiche lista della spesa",
                isOn: Binding(
                    get: { vm.notifyOnNewGroceryItem },
                    set: { newValue in
                        KBLog.settings.kbInfo("Toggle notifyOnNewGroceryItem set=\(newValue)")
                        vm.toggleNotifyOnNewGroceryItem(newValue)
                    }
                )
            )
            .disabled(vm.isLoading)
            .accessibilityHint("Ricevi una notifica quando un membro aggiunge un prodotto alla lista della spesa.")
            .listRowBackground(cardBackground)
            
            Toggle(
                "Notifiche nuove note",
                isOn: Binding(
                    get: { vm.notifyOnNewNote },
                    set: { newValue in
                        KBLog.settings.kbInfo("Toggle notifyOnNewNote set=\(newValue)")
                        vm.toggleNotifyOnNewNote(newValue)
                    }
                )
            )
            .disabled(vm.isLoading)
            .accessibilityHint("Ricevi una notifica quando un membro crea una nuova nota.")
            .listRowBackground(cardBackground)
            
            Toggle(
                "Notifiche nuove spese",
                isOn: Binding(
                    get: { vm.notifyOnNewExpense },
                    set: { newValue in
                        KBLog.settings.kbInfo("Toggle notifyOnNewExpense set=\(newValue)")
                        vm.toggleNotifyOnNewExpense(newValue)
                    }
                )
            )
            .disabled(vm.isLoading)
            .accessibilityHint("Ricevi una notifica quando un membro registra una nuova spesa di famiglia.")
            .listRowBackground(cardBackground)

            Toggle(
                "Notifiche nuovo biglietto Wallet",
                isOn: Binding(
                    get: { vm.notifyOnNewWalletTicket },
                    set: { newValue in
                        KBLog.settings.kbInfo("Toggle notifyOnNewWalletTicket set=\(newValue)")
                        vm.toggleNotifyOnNewWalletTicket(newValue)
                    }
                )
            )
            .disabled(vm.isLoading)
            .accessibilityHint("Ricevi una notifica quando un membro aggiunge un nuovo biglietto al Wallet.")
            .listRowBackground(cardBackground)

            Toggle(
                "Promemoria biglietti Wallet",
                isOn: Binding(
                    get: { vm.notifyOnWalletReminder },
                    set: { newValue in
                        KBLog.settings.kbInfo("Toggle notifyOnWalletReminder set=\(newValue)")
                        vm.toggleNotifyOnWalletReminder(newValue)
                    }
                )
            )
            .disabled(vm.isLoading)
            .accessibilityHint("Ricevi promemoria locali e push prima della partenza/evento (es. 24h e 2h prima).")
            .listRowBackground(cardBackground)

            // Separato dagli altri: le preferenze sopra sono lato server e
            // riguardano cose che succedono in famiglia. Questa è locale e
            // riguarda ciò che KidBox dice di sé — mescolarle porterebbe a
            // spegnere le notifiche utili per zittire i suggerimenti.
            Section {
                Toggle("Consigli su KidBox", isOn: $nudgesEnabled)
                    .onChange(of: nudgesEnabled) { _, newValue in
                        KBLog.settings.kbInfo("Toggle nudges set=\(newValue)")
                        NudgeState.isOptedOut = !newValue
                        // Spegnendolo la coda si svuota subito, senza aspettare
                        // il prossimo foreground.
                        Task { await NudgeEngine.shared.refresh(modelContext: modelContext) }
                    }
                .accessibilityHint("Suggerimenti occasionali sulle funzioni che non hai ancora provato.")
            } footer: {
                Text("Suggerimenti occasionali sulle funzioni che non hai ancora provato. Non influisce sulle notifiche qui sopra.")
            }
            .listRowBackground(cardBackground)

            if let t = vm.infoText {
                Text(t)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(cardBackground)
            }

            Section("Privacy password breach check") {
                Text("Per il controllo sicurezza password (Have I Been Pwned), KidBox usa k-anonymity: invia solo i primi 5 caratteri dell'hash SHA-1, mai la password in chiaro.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(cardBackground)
        }
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .navigationTitle("Notifiche")
        .task {
            KBLog.settings.kbDebug("NotificationSettingsView task start")
            vm.load()
            KBLog.settings.kbDebug("NotificationSettingsView task end")
        }
    }
}
