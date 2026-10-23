//
//  InsightSettingsView.swift
//  KidBox
//
//  Preferenze degli avvisi proattivi: come arrivano, gli orari di silenzio e
//  quali tipi. Tutto passa da `KBInsightPreferencesStore`, che le porta anche
//  sugli altri dispositivi dell'account.
//

import SwiftUI

struct InsightSettingsView: View {

    @ObservedObject private var store = KBInsightPreferencesStore.shared
    @Environment(\.colorScheme) private var colorScheme

    private var prefs: KBInsightPreferences { store.prefs }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(red: 0.18, green: 0.18, blue: 0.18) : Color(.systemBackground)
    }

    var body: some View {
        Form {
            Section {
                Picker(selection: Binding(
                    get: { prefs.delivery },
                    set: { value in store.update { $0.delivery = value } }
                )) {
                    Text("Subito").tag(KBInsightPreferences.Delivery.immediate)
                    Text("Riepilogo serale alle 19").tag(KBInsightPreferences.Delivery.eveningDigest)
                    Text("Spenti").tag(KBInsightPreferences.Delivery.off)
                } label: {
                    Text("Come arrivano")
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .listRowBackground(cardBackground)
            } header: {
                Text("Come arrivano")
            } footer: {
                Text("Con il riepilogo serale i to-do arrivano tutti insieme; le dosi restano puntuali. Gli avvisi non usano messaggi AI.")
            }

            if prefs.delivery != .off {
                Section {
                    DatePicker("Dalle", selection: timeBinding(\.quietStartMinutes), displayedComponents: .hourAndMinute)
                        .listRowBackground(cardBackground)
                    DatePicker("Alle", selection: timeBinding(\.quietEndMinutes), displayedComponents: .hourAndMinute)
                        .listRowBackground(cardBackground)
                } header: {
                    Text("Orari di silenzio")
                } footer: {
                    Text("In questi orari gli avvisi aspettano la fine del silenzio. Le dosi da registrare arrivano comunque.")
                }

                Section {
                    typeToggle(.todoUnassignedDueSoon) {
                        Text("To-do che nessuno ha preso")
                    }
                    typeToggle(.treatmentDoseMissing) {
                        Text("Dosi da registrare")
                    }
                } header: {
                    Text("Quali avvisi")
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { prefs.delegateAsk },
                    set: { value in store.update { $0.delegateAsk = value } }
                )) {
                    Text("Chiedi agli altri al posto mio")
                }
                .listRowBackground(cardBackground)
            } header: {
                Text("Lascia fare a KidBox")
            } footer: {
                Text("Se 12 ore prima della scadenza nessuno ha preso un to-do che hai creato tu, KidBox manda la richiesta agli altri membri che lo vedono e ti avvisa. Puoi ritirarla quando vuoi.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Avvisi proattivi")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func typeToggle(_ type: KBInsightType, @ViewBuilder label: () -> Text) -> some View {
        Toggle(isOn: Binding(
            get: { !prefs.isMuted(type) },
            set: { on in
                store.update {
                    if on { $0.mutedTypes.remove(type) } else { $0.mutedTypes.insert(type) }
                }
            }
        ), label: label)
        .listRowBackground(cardBackground)
    }

    /// Minuti dalla mezzanotte ↔ orario del `DatePicker` (la data non conta).
    private func timeBinding(_ keyPath: WritableKeyPath<KBInsightPreferences, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = prefs[keyPath: keyPath]
                return Calendar.current.date(
                    bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
                ) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                store.update { $0[keyPath: keyPath] = minutes }
            }
        )
    }
}
