//
//  AIChatMessageListView.swift
//  KidBox
//

import SwiftUI

private enum AIChatScrollMetrics {
    static let bottomAnchorID = "scroll-bottom"
    static let streamScrollMinInterval: TimeInterval = 0.12
}

// MARK: - Streaming delivery (ViewModels)

enum AIChatStreamingDelivery {
    @MainActor
    static func beginAssistantReveal(messageId: String, streamingMessageId: inout String?) {
        streamingMessageId = messageId
    }

    @MainActor
    static func finishReveal(messageId: String, streamingMessageId: inout String?) {
        if streamingMessageId == messageId {
            streamingMessageId = nil
        }
    }
}

// MARK: - Message list + stable scroll

struct AIChatMessageListView<MessageRow: View, Intro: View>: View {
    let messages: [KBAIMessage]
    let isLoading: Bool
    let streamingMessageId: String?
    var scrollButtonTint: Color = .blue
    var bottomPadding: CGFloat = 0
    var showsScrollToBottomButton: Bool = true
    let onStreamingComplete: (String) -> Void
    @ViewBuilder var intro: () -> Intro
    @ViewBuilder var messageRow: (KBAIMessage, Bool, @escaping () -> Void) -> MessageRow

    @State private var streamScrollTick = 0
    @State private var lastStreamScrollTime: TimeInterval = 0

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        intro()
                        ForEach(messages) { message in
                            messageRow(message, streamingMessageId == message.id) {
                                streamScrollTick += 1
                            }
                            .id(message.id)
                        }
                        if isLoading {
                            AIChatTypingIndicator()
                                .id("typing-indicator")
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 0)
                    .padding(.vertical, 12)
                    .padding(.bottom, bottomPadding)

                    Color.clear
                        .frame(height: 1)
                        .id(AIChatScrollMetrics.bottomAnchorID)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy: proxy, animated: false)
                }
                .onChange(of: isLoading) { _, loading in
                    if loading {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
                .onChange(of: streamingMessageId) { _, id in
                    if id != nil {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
                .onChange(of: streamScrollTick) { _, _ in
                    let now = Date().timeIntervalSinceReferenceDate
                    guard now - lastStreamScrollTime >= AIChatScrollMetrics.streamScrollMinInterval else { return }
                    lastStreamScrollTime = now
                    scrollToBottom(proxy: proxy, animated: false)
                }
                .onAppear {
                    scrollToBottom(proxy: proxy, animated: false)
                }

                if showsScrollToBottomButton, !messages.isEmpty {
                    Button {
                        scrollToBottom(proxy: proxy, animated: true)
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(scrollButtonTint))
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(AIChatScrollMetrics.bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(AIChatScrollMetrics.bottomAnchorID, anchor: .bottom)
        }
    }

    func standardBubble(for message: KBAIMessage, isStreaming: Bool, onTick: @escaping () -> Void) -> AIChatBubbleView {
        AIChatBubbleView(
            text: message.content,
            isUser: message.role == .user,
            date: message.createdAt,
            streamReveal: isStreaming && message.role == .assistant,
            onStreamingTick: onTick,
            onStreamingComplete: { onStreamingComplete(message.id) }
        )
    }
}

extension AIChatMessageListView where Intro == EmptyView {
    init(
        messages: [KBAIMessage],
        isLoading: Bool,
        streamingMessageId: String?,
        scrollButtonTint: Color = .blue,
        bottomPadding: CGFloat = 0,
        showsScrollToBottomButton: Bool = true,
        onStreamingComplete: @escaping (String) -> Void,
        @ViewBuilder messageRow: @escaping (KBAIMessage, Bool, @escaping () -> Void) -> MessageRow
    ) {
        self.messages = messages
        self.isLoading = isLoading
        self.streamingMessageId = streamingMessageId
        self.scrollButtonTint = scrollButtonTint
        self.bottomPadding = bottomPadding
        self.showsScrollToBottomButton = showsScrollToBottomButton
        self.onStreamingComplete = onStreamingComplete
        self.intro = { EmptyView() }
        self.messageRow = messageRow
    }
}
