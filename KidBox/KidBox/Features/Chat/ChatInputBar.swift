import SwiftUI

struct ChatInputBar: View {
    
    @Binding var text: String
    
    let isRecording: Bool
    let isRecordingLocked: Bool
    let recordingDuration: TimeInterval
    let waveformSamples: [CGFloat]
    let isSending: Bool
    
    let onSendText: () -> Void
    let onStartRecord: () -> Void
    let onStopRecord: () -> Void
    let onLockRecording: () -> Void
    let onSendLockedRecording: () -> Void
    let onCancelLockedRecording: () -> Void
    let onCancelRecord: () -> Void
    let onMediaTap: () -> Void
    let onCameraTap: () -> Void
    let onDocumentTap: () -> Void
    let onTextChange: () -> Void
    let onLocationTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var dragOffset: CGSize = .zero
    @State private var showLockHint = false
    @State private var inputHeight: CGFloat = 40
    
    private let tint = KBTheme.bubbleTint
    
    private var backgroundColor: Color {
        colorScheme == .dark
        ? Color(red: 0.18, green: 0.18, blue: 0.18)
        : Color(.systemBackground)
    }
    
    private var fieldBackground: Color {
        colorScheme == .dark
        ? Color(red: 0.22, green: 0.22, blue: 0.22)
        : Color(.secondarySystemBackground)
    }
    
    private var isTextEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            normalBar
                .opacity(isRecording ? 0.05 : 1)
            
            if isRecordingLocked {
                lockedRecordingBar
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if isRecording {
                recordingBar
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .background(backgroundColor)
        .animation(.easeInOut(duration: 0.2), value: isRecording)
        .animation(.easeInOut(duration: 0.2), value: isRecordingLocked)
    }
}

private extension ChatInputBar {
    
    var normalBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button { onMediaTap() } label: {
                    Label("Foto e Video", systemImage: "photo.on.rectangle")
                }
                Button { onCameraTap() } label: {
                    Label("Fotocamera", systemImage: "camera")
                }
                Button { onDocumentTap() } label: {
                    Label("Documento", systemImage: "doc")
                }
                Button { onLocationTap() } label: {
                    Label("Invia posizione", systemImage: "location.fill")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(tint)
            }
            .disabled(isRecording)
            
            messageField
            
            if isTextEmpty {
                micButton
            } else {
                sendButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    var messageField: some View {
        ZStack(alignment: .topLeading) {
            ExpandingChatTextView(
                text: $text,
                measuredHeight: $inputHeight,
                isEnabled: !isRecording,
                placeholder: "",
                onTextChange: {
                    if !isRecording {
                        onTextChange()
                    }
                },
                minHeight: 40,
                maxHeight: 120
            )
            .padding(.leading, 4)   // ← spazio extra per il cursore
            .frame(height: inputHeight)
            
            if isTextEmpty {
                Text("Messaggio…")
                    .foregroundStyle(.secondary)
                    .padding(.leading, 18)
                    .padding(.trailing, 14)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background(fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    var micButton: some View {
        Image(systemName: "mic.circle.fill")
            .font(.system(size: 32))
            .foregroundStyle(tint)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragOffset = value.translation
                        
                        if !isRecording {
                            onStartRecord()
                        }
                        
                        showLockHint = true
                        
                        if value.translation.height < -60 && !isRecordingLocked {
                            onLockRecording()
                        }
                    }
                    .onEnded { _ in
                        showLockHint = false
                        
                        if isRecordingLocked {
                            return
                        }
                        
                        if isRecording {
                            onStopRecord()
                        }
                        
                        dragOffset = .zero
                    }
            )
            .allowsHitTesting(true)
    }
    
    var sendButton: some View {
        Button(action: onSendText) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(tint)
        }
        .disabled(isSending || isRecording)
        .transition(.scale.combined(with: .opacity))
    }
    
    private var recordingBar: some View {
        GeometryReader { geo in
            let horizontalPadding: CGFloat = 8
            let rightWidth: CGFloat = 24
            let spacing: CGFloat = 8
            let contentWidth = geo.size.width
            - (horizontalPadding * 2)
            - rightWidth
            - spacing
            
            HStack(spacing: spacing) {
                centralRecordingContent(availableWidth: max(0, contentWidth))
                
                Image(systemName: "mic.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
                    .frame(width: rightWidth)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 10)
            .frame(width: geo.size.width, alignment: .leading)
        }
        .frame(height: 78)
    }
    
    private var lockedRecordingBar: some View {
        GeometryReader { geo in
            let horizontalPadding: CGFloat = 8
            let spacing: CGFloat = 8
            let leftWidth: CGFloat = 32
            let rightWidth: CGFloat = 44
            let contentWidth = geo.size.width
            - (horizontalPadding * 2)
            - leftWidth
            - rightWidth
            - (spacing * 2)
            
            HStack(spacing: spacing) {
                Button {
                    onCancelLockedRecording()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 24))
                        .foregroundStyle(.red)
                        .frame(width: leftWidth, height: 32)
                }
                .buttonStyle(.plain)
                
                centralLockedRecordingContent(availableWidth: max(0, contentWidth))
                
                Button {
                    onSendLockedRecording()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: rightWidth, height: rightWidth)
                        .background(KBTheme.bubbleTint, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 10)
            .frame(width: geo.size.width, alignment: .leading)
        }
        .frame(height: 78)
    }
    
    private func centralRecordingContent(availableWidth: CGFloat) -> some View {
        VStack(spacing: 6) {
            AdaptiveRecordingWaveformView(
                samples: waveformSamples,
                availableWidth: availableWidth
            )
            .frame(height: 30)
            
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                
                Text(formatDuration(recordingDuration))
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(.primary)
            }
            
            if showLockHint {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                    Text("Scorri su per bloccare")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .frame(width: availableWidth)
        .layoutPriority(1)
    }
    
    private func centralLockedRecordingContent(availableWidth: CGFloat) -> some View {
        VStack(spacing: 6) {
            AdaptiveRecordingWaveformView(
                samples: waveformSamples,
                availableWidth: availableWidth
            )
            .frame(height: 30)
            
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                
                Text(formatDuration(recordingDuration))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: availableWidth)
        .layoutPriority(1)
    }
    
    func formatDuration(_ t: TimeInterval) -> String {
        let total = Int(t)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
