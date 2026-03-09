//
//  MessageSettingsView.swift
//  KidBox
//
//  Created by vscocca on 07/03/26.
//

import SwiftUI

/// Settings screen for message-related preferences.
struct MessageSettingsView: View {
    
    @StateObject private var viewModel = SettingsViewModel()
    
    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { viewModel.audioTranscriptionEnabled },
                    set: { viewModel.toggleAudioTranscription($0) }
                )) {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.and.mic")
                            .foregroundStyle(KBTheme.bubbleTint)
                            .frame(width: 22)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Trascrizione messaggi vocali")
                                .foregroundStyle(.primary)
                            Text("Converti automaticamente i messaggi audio in testo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .tint(KBTheme.bubbleTint)
            } header: {
                Text("Messaggi vocali")
            } footer: {
                Text("La trascrizione avviene direttamente sul dispositivo e richiede iOS 26 o versioni successive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if let info = viewModel.infoText {
                Section {
                    Text(info)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Messaggi")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.load() }
    }
}
