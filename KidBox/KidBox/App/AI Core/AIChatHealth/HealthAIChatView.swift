//
//  HealthAIChatView.swift
//  KidBox
//
//  Full-health AI chat, opened from PediatricHomeView.
//  Works for both KBChild and KBFamilyMember — callers pass subjectName + subjectId.
//

import SwiftUI
import SwiftData

// MARK: - Chat View

struct HealthAIChatView: View {
    
    let subjectName: String
    let subjectId: String
    let exams: [KBMedicalExam]
    let visits: [KBMedicalVisit]
    let treatments: [KBTreatment]
    let vaccines: [KBVaccine]
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    
    @State private var viewModel:     HealthAIChatViewModel? = nil
    @State private var showSettings   = false
    @State private var showClearAlert = false
    @State private var inputText      = ""
    
    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    HealthAIChatBody(vm: vm, inputText: $inputText)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Salute di \(subjectName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
                if let vm = viewModel, !vm.messages.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button(role: .destructive) {
                                showClearAlert = true
                            } label: {
                                Label("Nuova conversazione", systemImage: "trash")
                            }
                            Button { showSettings = true } label: {
                                Label("Impostazioni AI", systemImage: "gear")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .task {
                guard viewModel == nil else { return }
                let vm = HealthAIChatViewModel(
                    subjectName:  subjectName,
                    subjectId:    subjectId,
                    exams:        exams,
                    visits:       visits,
                    treatments:   treatments,
                    vaccines:     vaccines,
                    modelContext: modelContext
                )
                viewModel = vm
                vm.loadOrCreateConversation()
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { AISettingsView() }
            }
            .alert("Nuova conversazione", isPresented: $showClearAlert) {
                Button("Cancella", role: .destructive) { viewModel?.clearConversation() }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("La cronologia di questa conversazione verrà eliminata.")
            }
        }
    }
}

// MARK: - Chat Body

private struct HealthAIChatBody: View {
    
    @ObservedObject var vm: HealthAIChatViewModel
    @Binding var inputText: String
    @FocusState private var isInputFocused: Bool
    
    private let accent = Color(red: 0.35, green: 0.6, blue: 0.85)
    
    var body: some View {
        VStack(spacing: 0) {
            providerBadge
            Divider()
            
            if vm.isLoadingContext {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Preparazione contesto sanitario…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                messageList
            }
            
            if let error = vm.errorMessage { errorBanner(error) }
            
            Divider()
            inputBar
        }
    }
    
    // MARK: - Message list
    
    /// Extracted into its own computed property so SwiftUI treats it as a
    /// stable subtree. This prevents the ScrollViewReader + onChange closures
    /// from being re-registered every time the parent body is re-evaluated,
    /// which was the root cause of the accelerating typing-indicator animation.
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if vm.messages.isEmpty && !vm.isLoading {
                        introBubble
                    }
                    ForEach(vm.messages) { message in
                        AIChatBubbleView(
                            text:   message.content,
                            isUser: message.role == .user,
                            date:   message.createdAt
                        )
                        .id(message.id)
                    }
                    
                    // Typing indicator — given a stable, unique id so SwiftUI
                    // never recycles or re-creates it while it is visible.
                    // This prevents its internal repeating animation from
                    // restarting (and compounding) when the view is remounted.
                    if vm.isLoading {
                        AIChatTypingIndicator()
                            .id("typing-indicator")
                            .transition(.opacity)
                    }
                }
                .padding()
                
                // Invisible anchor always present at the very bottom.
                // scrollTo targets this instead of "typing" so there is
                // never a missing-id failure when isLoading flips quickly.
                Color.clear
                    .frame(height: 1)
                    .id("scroll-bottom")
            }
            .onTapGesture { isInputFocused = false }
            // Scroll to bottom whenever a new message arrives.
            .onChange(of: vm.messages.count) { _, _ in
                proxy.scrollTo("scroll-bottom", anchor: .bottom)
            }
            // Scroll to bottom when generation starts so the indicator is visible.
            .onChange(of: vm.isLoading) { _, loading in
                if loading {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("scroll-bottom", anchor: .bottom)
                    }
                }
            }
            // Restore scroll position when re-entering an existing conversation.
            .onAppear {
                proxy.scrollTo("scroll-bottom", anchor: .bottom)
            }
        }
    }
    
    // MARK: - Provider badge
    
    private var providerBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(accent)
            Text("Assistente AI KidBox — Salute")
                .font(.caption.bold())
            Text("· Solo informativo, non sostituisce il medico")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.06))
    }
    
    // MARK: - Intro bubble
    
    private var introBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "heart.text.clipboard")
                .foregroundStyle(accent)
                .padding(8)
                .background(accent.opacity(0.1), in: Circle())
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Ciao! Sono il tuo assistente sanitario per \(vm.subjectName).")
                    .font(.subheadline.bold())
                
                if !vm.treatments.isEmpty || !vm.vaccines.isEmpty ||
                    !vm.visits.isEmpty    || !vm.exams.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ho accesso a:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !vm.treatments.isEmpty {
                            infoRow(icon: "cross.case.fill",
                                    text: "\(vm.treatments.count) cur\(vm.treatments.count == 1 ? "a" : "e") attiv\(vm.treatments.count == 1 ? "a" : "e")",
                                    color: Color(red: 0.6, green: 0.45, blue: 0.85))
                        }
                        if !vm.vaccines.isEmpty {
                            infoRow(icon: "syringe.fill",
                                    text: "\(vm.vaccines.count) vaccin\(vm.vaccines.count == 1 ? "o" : "i")",
                                    color: Color(red: 0.95, green: 0.55, blue: 0.45))
                        }
                        if !vm.visits.isEmpty {
                            infoRow(icon: "stethoscope",
                                    text: "\(vm.visits.count) visit\(vm.visits.count == 1 ? "a" : "e")",
                                    color: accent)
                        }
                        if !vm.exams.isEmpty {
                            infoRow(icon: "testtube.2",
                                    text: "\(vm.exams.count) esam\(vm.exams.count == 1 ? "e" : "i")",
                                    color: Color(red: 0.25, green: 0.65, blue: 0.75))
                        }
                    }
                } else {
                    Text("Non ci sono ancora dati sanitari registrati, ma puoi farmi domande generali.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text("Puoi chiedermi un riepilogo, farmaci in corso, vaccini, visite recenti o esami in attesa.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }
    
    private func infoRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2).foregroundStyle(color)
            Text(text).font(.caption).foregroundStyle(.primary)
        }
    }
    
    // MARK: - Input bar
    
    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Fai una domanda…", text: $inputText, axis: .vertical)
                .focused($isInputFocused)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
            
            Button {
                let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                inputText = ""
                Task { await vm.send(text: text) }
            } label: {
                Image(systemName: vm.isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? .secondary : accent
                    )
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isLoading)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
    
    // MARK: - Error banner
    
    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button { vm.errorMessage = nil } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.1))
    }
}
