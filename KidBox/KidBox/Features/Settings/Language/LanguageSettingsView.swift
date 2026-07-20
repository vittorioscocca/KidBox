//
//  LanguageSettingsView.swift
//  KidBox
//
//  Selettore lingua in-app. Rispecchia lo stile di AppearanceSettingsView.
//  La lingua si applica subito, senza riavviare l'app (vedi LanguageManager).
//

import SwiftUI

struct LanguageSettingsView: View {

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var languageManager = LanguageManager.shared

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
            Section {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        languageManager.apply(lang)
                    } label: {
                        HStack(spacing: 14) {
                            Group {
                                if let flag = lang.flag {
                                    Text(flag).font(.title3)
                                } else {
                                    Image(systemName: "globe")
                                        .font(.title3)
                                        .foregroundStyle(KBTheme.bubbleTint)
                                }
                            }
                            .frame(width: 28)

                            Text(lang.label)
                                .foregroundStyle(.primary)

                            Spacer()

                            if languageManager.current == lang {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(KBTheme.bubbleTint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(cardBackground)
                }
            } footer: {
                Text("La lingua viene applicata subito in tutta l'app.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .navigationTitle("Lingua")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.default, value: languageManager.current)
    }
}
