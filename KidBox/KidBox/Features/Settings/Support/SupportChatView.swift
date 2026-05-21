//
//  SupportChatView.swift
//  KidBox
//

import PhotosUI
import SwiftUI
import UIKit

struct SupportChatView: View {
    @StateObject private var vm = SupportChatViewModel()
    @State private var showInfoSheet = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showTicketSentToast = false
    @FocusState private var isInputFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var inputHeight: CGFloat = 40

    private let tint = KBTheme.bubbleTint

    var body: some View {
        VStack(spacing: 0) {
            messageList
            if let error = vm.errorMessage {
                errorBanner(error)
            }
            inputBar
        }
        .background(KBTheme.background(colorScheme))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(KBTheme.cardBackground(colorScheme), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Text("🤖")
                    Text("Assistente KidBox")
                        .font(.headline)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showInfoSheet = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("Informazioni")
            }
        }
        .sheet(isPresented: $showInfoSheet) {
            SupportInfoSheet()
        }
        .sheet(isPresented: $vm.showSubmitConfirm) {
            SupportSubmitConfirmSheet(
                isBug: vm.detectedType == "bug",
                isLoading: vm.isLoading,
                onCancel: { vm.dismissSubmitConfirm() },
                onSubmit: { vm.confirmSubmit() },
            )
            .presentationDetents([.height(vm.detectedType == "bug" ? 260 : 220)])
            .presentationBackground(KBTheme.cardBackground(colorScheme))
        }
        .onChange(of: vm.ticketSent) { _, sent in
            if sent { showTicketSentToast = true }
        }
        .overlay(alignment: .bottom) {
            if showTicketSentToast {
                ticketSentBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            withAnimation { showTicketSentToast = false }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showTicketSentToast)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if vm.messages.isEmpty && !vm.isLoading {
                        Text("Descrivi un problema, una domanda o un suggerimento. Puoi allegare fino a 5 screenshot.")
                            .font(.subheadline)
                            .foregroundStyle(KBTheme.secondaryText(colorScheme))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 20)
                    }
                    ForEach(vm.messages) { message in
                        SupportMessageRow(message: message)
                            .id(message.id)
                    }
                    if vm.isLoading {
                        AIChatTypingIndicator()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 16)
                            .id("typing")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                isInputFocused = false
            }
            .onChange(of: vm.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: vm.isLoading) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            if !vm.attachedImages.isEmpty {
                supportAttachmentPreviewTray
                Rectangle()
                    .fill(KBTheme.separator(colorScheme))
                    .frame(height: 1)
            }

            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: max(0, SupportImageEncoder.maxImages - vm.attachedImages.count),
                    matching: .images,
                ) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(tint)
                }
                .disabled(vm.ticketSent || vm.isLoading || vm.attachedImages.count >= SupportImageEncoder.maxImages)
                .onChange(of: pickerItems) { _, items in
                    Task { await loadPickerItems(items) }
                }

                supportMessageField

                if vm.isLoading {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else {
                    Button {
                        isInputFocused = false
                        vm.sendMessage(
                            text: vm.inputText,
                            imageDatas: vm.attachedImages.map(\.data),
                        )
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(canSend ? tint : KBTheme.secondaryText(colorScheme).opacity(0.45))
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(inputBarBackground)
    }

    private var supportAttachmentPreviewTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(vm.attachedImages) { item in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let uiImage = UIImage(data: item.data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                KBTheme.inputBackground(colorScheme)
                            }
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        Button {
                            vm.removeImage(id: item.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: 88)
        .frame(maxWidth: .infinity)
        .background(inputBarBackground)
    }

    private var inputBarBackground: Color {
        KBTheme.cardBackground(colorScheme)
    }

    private var supportFieldBackground: Color {
        KBTheme.inputBackground(colorScheme)
    }

    private var supportMessageField: some View {
        ZStack(alignment: .topLeading) {
            ExpandingChatTextView(
                text: $vm.inputText,
                measuredHeight: $inputHeight,
                isEnabled: !vm.ticketSent,
                placeholder: "",
                onTextChange: {},
                minHeight: 40,
                maxHeight: 120
            )
            .padding(.leading, 4)
            .frame(height: inputHeight)
            .focused($isInputFocused)

            if vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Messaggio…")
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))
                    .padding(.leading, 18)
                    .padding(.trailing, 14)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background(supportFieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(KBTheme.separator(colorScheme), lineWidth: 1)
        )
    }

    private var canSend: Bool {
        !vm.isLoading && !vm.ticketSent &&
        (!vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !vm.attachedImages.isEmpty)
    }

    private func loadPickerItems(_ items: [PhotosPickerItem]) async {
        defer { pickerItems = [] }
        for item in items {
            guard vm.attachedImages.count < SupportImageEncoder.maxImages else { break }
            if let data = try? await item.loadTransferable(type: Data.self) {
                vm.addImage(data: data)
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.footnote)
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            Spacer()
            Button { vm.dismissError() } label: {
                Image(systemName: "xmark.circle.fill")
            }
        }
        .padding(10)
        .background(KBTheme.cardBackground(colorScheme))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red.opacity(colorScheme == .dark ? 0.45 : 0.25), lineWidth: 1),
        )
        .padding(.horizontal, 12)
    }

    private var ticketSentBanner: some View {
        Text("✅ Segnalazione inviata. Ti risponderemo presto.")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.green.opacity(0.92), in: Capsule())
            .padding(.bottom, 100)
    }
}

// MARK: - Message row

private struct SupportMessageRow: View {
    let message: SupportMessage

    var body: some View {
        if message.role == "assistant" {
            AIChatBubbleView(
                text: message.text,
                isUser: false,
                date: Date(),
                streamReveal: false,
            )
            .padding(.horizontal, 8)
        } else if message.imageDatas.isEmpty {
            AIChatBubbleView(
                text: message.text,
                isUser: true,
                date: Date(),
                streamReveal: false,
            )
            .padding(.horizontal, 8)
        } else {
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 6) {
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.body)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(KBTheme.bubbleTint, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if !message.imageDatas.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(message.imageDatas.enumerated()), id: \.offset) { _, data in
                                    if let uiImage = UIImage(data: data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 72, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Submit confirm sheet

private struct SupportSubmitConfirmSheet: View {
    let isBug: Bool
    let isLoading: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Invia segnalazione?")
                .font(.title3.weight(.bold))
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            Text(
                "La conversazione verrà inviata al team KidBox. Riceverai assistenza il prima possibile.",
            )
            .font(.subheadline)
            .foregroundStyle(KBTheme.secondaryText(colorScheme))
            if isBug {
                Text(
                    "Per i bug, KidBox allega automaticamente i log diagnostici dell'app (gli stessi usati per i crash report).",
                )
                .font(.subheadline)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
            }
            HStack {
                Button("Annulla", action: onCancel)
                    .frame(maxWidth: .infinity)
                Button("Invia", action: onSubmit)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(isLoading)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .background(KBTheme.cardBackground(colorScheme))
    }
}

// MARK: - Info sheet

private struct SupportInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Questa chat ti aiuta a ottenere risposte su KidBox e, se serve, a inviare una segnalazione al nostro team.")
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))

                    infoSection(
                        title: "Domande",
                        body: "Chiedi come funzionano calendario, documenti, salute, chat, viaggi e le altre sezioni dell'app.",
                    )
                    infoSection(
                        title: "Problemi e bug",
                        body: "Descrivi cosa non va: l'assistente ti guida e, per i bug, allega automaticamente i log diagnostici all'invio della segnalazione.",
                    )
                    infoSection(
                        title: "Suggerimenti",
                        body: "Proponi miglioramenti o nuove funzioni: li classifichiamo per le prossime versioni.",
                    )
                    infoSection(
                        title: "Screenshot",
                        body: "Puoi allegare fino a 5 immagini per chiarire il problema (icona + sotto la chat).",
                    )
                    infoSection(
                        title: "Invio segnalazione",
                        body: "Quando la conversazione è completa, l'assistente ti propone di inviare il ticket. Riceverai assistenza il prima possibile.",
                    )
                    Text("I messaggi usano la quota AI giornaliera del piano famiglia (Pro o Max).")
                        .font(.footnote)
                        .foregroundStyle(KBTheme.secondaryText(colorScheme))
                }
                .padding(20)
            }
            .background(KBTheme.background(colorScheme))
            .navigationTitle("Assistente & Supporto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ho capito") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func infoSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            Text(body)
                .font(.subheadline)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
        }
    }
}
