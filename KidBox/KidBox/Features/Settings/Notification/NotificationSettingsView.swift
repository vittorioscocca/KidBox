//
//  NotificationSettingsView.swift
//  KidBox
//
//  Created by vscocca on 06/03/26.
//

import SwiftUI
import Combine
internal import os

struct NotificationSettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    
    var body: some View {
        List {
            Toggle(
                "Notifica nuovi documenti",
                isOn: Binding(
                    get: { vm.notifyOnNewDocs },
                    set: { newValue in
                        KBLog.settings.info("Toggle notifyOnNewDocs set=\(newValue, privacy: .public)")
                        vm.notifyOnNewDocs = newValue
                        vm.toggleNotifyOnNewDocs(newValue)
                    }
                )
            )
            .disabled(vm.isLoading)
            
            Toggle(
                "Notifica nuovi messaggi in chat",
                isOn: Binding(
                    get: { vm.notifyOnNewMessages },
                    set: { vm.toggleNotifyOnNewMessages($0) }
                )
            )
            .disabled(vm.isLoading)
            
            Toggle(
                "Notifiche posizione (inizio/fine condivisione)",
                isOn: Binding(
                    get: { vm.notifyOnLocationSharing },
                    set: { newValue in
                        KBLog.settings.info("Toggle notifyOnLocationSharing set=\(newValue, privacy: .public)")
                        vm.notifyOnLocationSharing = newValue
                        vm.toggleNotifyOnLocationSharing(newValue)
                    }
                )
            )
            .disabled(vm.isLoading)
            
            Toggle(
                "Notifiche Todo (assegnazioni/scadenze)",
                isOn: Binding(
                    get: { vm.notifyOnTodos },
                    set: { vm.toggleNotifyOnTodos($0) }
                )
            )
            .disabled(vm.isLoading)
            
            Toggle(
                "Notifiche lista della spesa",
                isOn: Binding(
                    get: { vm.notifyOnNewGroceryItem },
                    set: { newValue in
                        KBLog.settings.info("Toggle notifyOnNewGroceryItem set=\(newValue, privacy: .public)")
                        vm.toggleNotifyOnNewGroceryItem(newValue)
                    }
                )
            )
            .disabled(vm.isLoading)
            .accessibilityHint("Ricevi una notifica quando un membro aggiunge un prodotto alla lista della spesa.")
            
            Toggle(
                "Notifiche nuove note",
                isOn: Binding(
                    get: { vm.notifyOnNewNote },
                    set: { newValue in
                        KBLog.settings.info("Toggle notifyOnNewNote set=\(newValue, privacy: .public)")
                        vm.toggleNotifyOnNewNote(newValue)
                    }
                )
            )
            .disabled(vm.isLoading)
            .accessibilityHint("Ricevi una notifica quando un membro crea una nuova nota.")
            
            if let t = vm.infoText {
                Text(t)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Notifiche")
        .task {
            KBLog.settings.debug("NotificationSettingsView task start")
            vm.load()
            KBLog.settings.debug("NotificationSettingsView task end")
        }
    }
}
