//
//  MedicalAIChatView.swift
//  KidBox
//

import SwiftUI
import SwiftData

struct MedicalAIChatView: View {
    
    let visit: KBMedicalVisit
    let child: KBChild
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    
    @State private var viewModel:     MedicalAIChatViewModel? = nil
    @State private var showSettings   = false
    @State private var showClearAlert = false
    @State private var inputText      = ""
    
    var body: some View {
        NavigationStack {
            Group {
                if let vm = viewModel {
                    MedicalAIChatBody(vm: vm, inputText: $inputText)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Chiedi all'AI")
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
            .task(id: visit.id) {
                guard viewModel == nil else { return }
                let vm = MedicalAIChatViewModel(
                    visit: visit,
                    child: child,
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
    
    private struct MedicalAIChatBody: View {
        @ObservedObject var vm: MedicalAIChatViewModel
        @Binding var inputText: String
        
        var body: some View {
            VStack(spacing: 0) {
                providerBadge
                Divider()
                
                if vm.isLoadingContext {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Preparazione contesto visita…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                if vm.messages.isEmpty && !vm.isLoading {
                                    introBubble
                                }
                                ForEach(vm.messages) { message in
                                    MessageBubble(message: message).id(message.id)
                                }
                                if vm.isLoading {
                                    TypingIndicator().id("typing")
                                }
                            }
                            .padding()
                        }
                        .onChange(of: vm.messages.count) { _, _ in
                            withAnimation {
                                proxy.scrollTo(vm.messages.last?.id ?? "typing", anchor: .bottom)
                            }
                        }
                        .onChange(of: vm.isLoading) { _, loading in
                            if loading { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
                        }
                    }
                }
                
                if let error = vm.errorMessage {
                    errorBanner(error)
                }
                
                Divider()
                inputBar
            }
        }
        
        // --- qui sotto copi/incolli le stesse view helper che avevi in MedicalAIChatView ---
        private var providerBadge: some View {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.caption).foregroundStyle(.blue)
                Text("Assistente AI KidBox").font(.caption.bold())
                Text("· Solo informativo, non sostituisce il medico")
                    .font(.caption2).foregroundStyle(.secondary)
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
                    Text("Ciao! Sono pronto ad aiutarti a capire questa visita medica.")
                        .font(.subheadline)
                    Text("Puoi chiedermi spiegazioni su diagnosi, farmaci, terapie o esami prescritti.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        }
        
        private var inputBar: some View {
            HStack(spacing: 10) {
                TextField("Fai una domanda…", text: $inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
                
                Button {
                    let text = inputText
                    inputText = ""
                    Task { await vm.send(text: text) }
                } label: {
                    Image(systemName: vm.isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : Color.blue)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || vm.isLoading)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        
        @ViewBuilder
        private func errorBanner(_ message: String) -> some View {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.caption).foregroundStyle(.primary)
                Spacer()
                Button { vm.errorMessage = nil } label: {
                    Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.orange.opacity(0.1))
        }
    }
    
    // MARK: - Provider badge
    
    private var providerBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.caption).foregroundStyle(.blue)
            Text("Assistente AI KidBox").font(.caption.bold())
            Text("· Solo informativo, non sostituisce il medico")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.06))
    }
    
    // MARK: - Input bar
    
    private func inputBar(vm: MedicalAIChatViewModel) -> some View {
        HStack(spacing: 10) {
            TextField("Fai una domanda…", text: $inputText, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
            
            Button {
                let text = inputText
                inputText = ""
                Task { await vm.send(text: text) }
            } label: {
                Image(systemName: vm.isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : Color.blue)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || vm.isLoading)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
    
    // MARK: - Error banner
    
    @ViewBuilder
    private func errorBanner(_ message: String, vm: MedicalAIChatViewModel) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption).foregroundStyle(.primary)
            Spacer()
            Button { vm.errorMessage = nil } label: {
                Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.1))
    }
}

// MARK: - MessageBubble

private struct MessageBubble: View {
    let message: KBAIMessage
    var isUser: Bool { message.role == .user }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 40) }
            if !isUser {
                Image(systemName: "sparkles")
                    .font(.caption).foregroundStyle(.blue)
                    .padding(6).background(.blue.opacity(0.1), in: Circle())
            }
            Text(message.content)
                .font(.subheadline)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    isUser ? AnyShapeStyle(.blue) : AnyShapeStyle(.quaternary),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .foregroundStyle(isUser ? .white : .primary)
                .textSelection(.enabled)
            if isUser {
                Image(systemName: "person.circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - TypingIndicator

private struct TypingIndicator: View {
    @State private var animate = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption).foregroundStyle(.blue)
                .padding(6).background(.blue.opacity(0.1), in: Circle())
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle().fill(.secondary).frame(width: 7, height: 7)
                        .scaleEffect(animate ? 1.0 : 0.5)
                        .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15), value: animate)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
            Spacer(minLength: 40)
        }
        .onAppear { animate = true }
    }
}
