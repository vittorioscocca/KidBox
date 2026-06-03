//
//  PediatricVisitsAIChatView.swift
//  KidBox
//
//  Created by vscocca on 06/03/26.
//

import SwiftUI
import SwiftData

struct PediatricVisitsAIChatView: View {
    
    let subjectName: String
    let visibleVisits: [KBMedicalVisit]
    let selectedPeriod: PeriodFilter
    let customStartDate: Date?
    let customEndDate: Date?
    let scopeId: String
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var viewModel:     PediatricVisitsAIChatViewModel? = nil
    @State private var showSettings   = false
    @State private var showClearAlert = false
    @State private var inputText      = ""
    
    var body: some View {
        ModalNavContainer {
            Group {
                if let vm = viewModel {
                    PediatricVisitsAIChatBody(vm: vm, inputText: $inputText)
                        .aiActionExecutionToast(
                            summary: Binding(
                                get: { vm.actionExecutionSummary },
                                set: { vm.actionExecutionSummary = $0 }
                            )
                        )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Chiedi all'AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if !targetEnvironment(macCatalyst)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
                #endif
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
                let vm = PediatricVisitsAIChatViewModel(
                    subjectName: subjectName,
                    visibleVisits: visibleVisits,
                    selectedPeriod: selectedPeriod,
                    customStartDate: customStartDate,
                    customEndDate: customEndDate,
                    scopeId: scopeId,
                    modelContext: modelContext
                )
                viewModel = vm
                vm.loadOrCreateConversation()
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { AISettingsView() }
            }
            .alert("Nuova conversazione", isPresented: $showClearAlert) {
                Button("Cancella", role: .destructive) {
                    viewModel?.clearConversation()
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("La cronologia di questa conversazione verrà eliminata.")
            }
        }
    }
}

// MARK: - Chat Body

private struct PediatricVisitsAIChatBody: View {
    
    @ObservedObject var vm: PediatricVisitsAIChatViewModel
    @Binding var inputText: String
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            providerBadge
            Divider()
            
            if vm.isLoadingContext {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Preparazione contesto visite…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                messageList
            }
            
            if let error = vm.errorMessage {
                errorBanner(error)
            }
            
            Divider()
            inputBar
        }
    }
    
    // MARK: - Message list
    
    /// Extracted as a stable computed property so SwiftUI does not
    /// re-register the ScrollViewReader + onChange listeners on every
    /// body evaluation — which was causing the typing-indicator animation
    /// to compound and accelerate after re-entering the chat.
    private var messageList: some View {
        AIChatMessageListView(
            messages: vm.messages,
            isLoading: vm.isLoading,
            streamingMessageId: vm.streamingMessageId,
            scrollButtonTint: .blue,
            onStreamingComplete: { vm.finishStreaming(messageId: $0) },
            intro: {
                if vm.messages.isEmpty && !vm.isLoading {
                    introBubble
                }
            },
            messageRow: { message, isStreaming, onTick in
                AIChatBubbleView(
                    text: message.content,
                    isUser: message.role == .user,
                    date: message.createdAt,
                    streamReveal: isStreaming && message.role == .assistant,
                    onStreamingTick: onTick,
                    onStreamingComplete: { vm.finishStreaming(messageId: message.id) }
                )
            }
        )
        .onTapGesture { isInputFocused = false }
    }
    
    // MARK: - Provider badge
    
    private var providerBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(.blue)
            Text("Assistente AI KidBox")
                .font(.caption.bold())
            Text("· Solo informativo, non sostituisce il medico")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.06))
    }
    
    // MARK: - Intro bubble
    
    private var introBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
                .padding(8)
                .background(.blue.opacity(0.1), in: Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Ciao! Posso aiutarti a capire meglio l'insieme delle visite mediche presenti in questa schermata.")
                    .font(.subheadline)
                Text("Puoi chiedermi un riassunto, l'andamento clinico, differenze tra visite, esami, farmaci o referti allegati.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }
    
    // MARK: - Input bar
    
    private var inputBar: some View {
        VStack(spacing: 4) {
            if vm.dailyLimit > 0 {
                HStack {
                    Spacer()
                    Text("\(vm.usageToday)/\(vm.dailyLimit)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
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
                            ? .secondary : Color.blue
                        )
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isLoading)
            }
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
