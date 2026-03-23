//
//  Untitled.swift
//  KidBox
//
//  Created by vscocca on 23/03/26.
//


import SwiftUI

struct AppearanceSettingsView: View {
    
    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var vm = SettingsViewModel()
    @Environment(\.colorScheme) private var colorScheme
    
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
            ForEach(AppearanceMode.allCases) { mode in
                Button {
                    vm.setAppearanceMode(mode, coordinator: coordinator)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: mode.icon)
                            .font(.title3)
                            .foregroundStyle(KBTheme.bubbleTint)
                            .frame(width: 28)
                        
                        Text(mode.label)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        if vm.appearanceMode == mode {
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
        }
        .scrollContentBackground(.hidden)
        .background(backgroundColor)
        .navigationTitle("Tema")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.load() }
    }
}
