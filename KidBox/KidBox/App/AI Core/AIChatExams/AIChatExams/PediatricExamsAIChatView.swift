//
//  PediatricExamsAIChatView.swift
//  KidBox
//

import SwiftUI
import SwiftData

// MARK: - Chat View

struct PediatricExamsAIChatView: View {
    
    let subjectName: String
    let scope: ExamAIChatScope
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    
    @State private var viewModel:     PediatricExamsAIChatViewModel? = nil
    @State private var showSettings   = false
    @State private var showClearAlert = false
    @State private var inputText      = ""
    
    private var navigationTitle: String {
        switch scope {
        case .single(let e): return e.name
        case .all:           return "Esami"
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    ExamsAIChatBody(vm: vm, inputText: $inputText)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(navigationTitle)
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
                let vm = PediatricExamsAIChatViewModel(
                    subjectName: subjectName,
                    scope: scope,
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

private struct ExamsAIChatBody: View {
    
    @ObservedObject var vm: PediatricExamsAIChatViewModel
    @Binding var inputText: String
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            providerBadge
            Divider()
            
            if vm.isLoadingContext {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Preparazione contesto esami…")
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
    /// from being re-registered on every body evaluation, which caused the
    /// typing-indicator animation to compound/accelerate after re-entering.
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if vm.messages.isEmpty && !vm.isLoading {
                        introBubble
                    }
                    ForEach(vm.messages) { message in
                        AIChatBubbleView(
                            text: message.content,
                            isUser: message.role == .user,
                            date: message.createdAt
                        )
                        .id(message.id)
                    }
                    
                    // Stable id prevents SwiftUI from recycling the view and
                    // restarting its internal repeating animation on remount.
                    if vm.isLoading {
                        AIChatTypingIndicator()
                            .id("typing-indicator")
                            .transition(.opacity)
                    }
                }
                .padding()
                
                // Persistent bottom anchor — scrollTo always has a valid target.
                Color.clear
                    .frame(height: 1)
                    .id("scroll-bottom")
            }
            .onTapGesture { isInputFocused = false }
            .onChange(of: vm.messages.count) { _, _ in
                proxy.scrollTo("scroll-bottom", anchor: .bottom)
            }
            .onChange(of: vm.isLoading) { _, loading in
                if loading {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("scroll-bottom", anchor: .bottom)
                    }
                }
            }
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
                .foregroundStyle(.teal)
            Text("Assistente AI KidBox")
                .font(.caption.bold())
            Text("· Solo informativo, non sostituisce il medico")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.teal.opacity(0.06))
    }
    
    // MARK: - Intro bubble
    
    private var introBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.teal)
                .padding(8)
                .background(.teal.opacity(0.1), in: Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                if vm.scope.isSingle {
                    Text("Ciao! Posso aiutarti a capire meglio questo esame.")
                        .font(.subheadline)
                    Text("Puoi chiedermi informazioni sulla preparazione, lo stato, il risultato o gli allegati.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Ciao! Posso aiutarti a capire meglio l'insieme degli esami presenti in questa schermata.")
                        .font(.subheadline)
                    Text("Puoi chiedermi un riepilogo, quali sono in scadenza, urgenti, con risultato disponibile o referti allegati.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(.teal.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
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
                        ? .secondary : Color.teal
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
