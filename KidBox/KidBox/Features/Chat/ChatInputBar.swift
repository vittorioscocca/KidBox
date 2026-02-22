import SwiftUI

/// Barra di input della chat.
///
/// Contiene:
/// - Tasto + per foto/video/fotocamera
/// - Campo testo espandibile
/// - Microfono (hold-to-record) / tasto invio
///
/// Fix inclusi:
/// - ✅ Non disabilita l'intera `normalBar` durante la registrazione (altrimenti non arriva mai il "rilascio").
/// - ✅ Una sola gesture sul microfono (niente gesture in conflitto).
/// - ✅ Durante recording: blocca menu + text editor (così non “scrolli” e non rompi la gesture), ma il mic resta attivo.
struct ChatInputBar: View {
    
    @Binding var text: String
    let isRecording: Bool
    let recordingDuration: TimeInterval
    let isSending: Bool
    
    let onSendText: () -> Void
    let onStartRecord: () -> Void
    let onStopRecord: () -> Void
    let onCancelRecord: () -> Void
    let onMediaTap: () -> Void
    let onCameraTap: () -> Void
    
    @FocusState private var isTextFocused: Bool
    
    var body: some View {
        ZStack(alignment: .top) {
            normalBar
            // Durante recording “spegniamo” visivamente la barra normale,
            // ma NON la disabilitiamo tutta (il mic deve ricevere onEnded).
                .opacity(isRecording ? 0.05 : 1)
            
            if isRecording {
                recordingBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color(.systemBackground))
        .animation(.easeInOut(duration: 0.15), value: isRecording)
    }
    
    // MARK: - Normal bar
    
    private var normalBar: some View {
        HStack(alignment: .center, spacing: 10) {
            
            // Tasto + (media)
            Menu {
                Button { onMediaTap() } label: {
                    Label("Foto e Video", systemImage: "photo.on.rectangle")
                }
                Button { onCameraTap() } label: {
                    Label("Fotocamera", systemImage: "camera")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
            }
            // Durante recording blocchiamo il menu (evita gesture/scroll strani)
            .disabled(isSending || isRecording)
            
            // Campo testo
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Messaggio…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                
                TextEditor(text: $text)
                    .focused($isTextFocused)
                    .frame(minHeight: 40, maxHeight: 120)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollContentBackground(.hidden)
                    .disabled(isRecording) // ✅ blocca input testo mentre registri
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            
            // Tasto invio o microfono
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                micButton
            } else {
                Button(action: onSendText) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.accentColor)
                }
                .disabled(isSending || isRecording)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .animation(.spring(response: 0.25), value: text.isEmpty)
    }
    
    // MARK: - Mic button (hold to record)
    
    private var micButton: some View {
        Image(systemName: "mic.circle.fill")
            .font(.system(size: 32))
            .foregroundStyle(Color.accentColor)
            .contentShape(Rectangle()) // area touch più “umana”
        // ✅ UNA SOLA gesture: press -> start, release -> stop
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isRecording {
                            onStartRecord()
                        }
                    }
                    .onEnded { _ in
                        if isRecording {
                            onStopRecord()
                        }
                    }
            )
        // Non disabilitare MAI il mic durante recording:
        // serve proprio a ricevere il rilascio e stoppare.
            .allowsHitTesting(true)
    }
    
    // MARK: - Recording bar
    
    private var recordingBar: some View {
        HStack(spacing: 16) {
            
            // Annulla
            Button { onCancelRecord() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                    Text("Annulla")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Indicatore REC
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(recordingDuration.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.5).repeatForever(), value: recordingDuration)
                
                Text(formatDuration(recordingDuration))
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(.primary)
                
                Text("Rilascia per inviare")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Icona mic attiva
            Image(systemName: "mic.fill")
                .foregroundStyle(.red)
                .font(.title3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground))
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ t: TimeInterval) -> String {
        let total = Int(t)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
