//
//  ChatUploadProgress.swift
//  KidBox
//
//  Avanzamento dell'invio per singolo messaggio, mostrato come anello dentro
//  la bubble (stile WhatsApp) al posto della barra lineare sopra l'input.
//
//  Vive fuori dal ViewModel di proposito: se il progresso fosse un @Published
//  del ViewModel, ogni tick ridisegnerebbe l'intera lista. Qui osserva lo store
//  solo il piccolo anello della bubble interessata.
//

import SwiftUI
import UIKit
import AVFoundation
import Combine
import BackgroundTasks

@MainActor
final class ChatUploadProgressStore: ObservableObject {
    static let shared = ChatUploadProgressStore()
    private init() {}

    /// messageId → 0...1. Presente ma nil = in preparazione (compressione).
    @Published private(set) var progress: [String: Double?] = [:]
    /// messageId → anteprima locale, per non mostrare un riquadro vuoto durante l'invio.
    @Published private(set) var previews: [String: UIImage] = [:]

    /// - Parameter longRunning: invio che può superare i ~30 s concessi in
    ///   background (video, file grandi): chiede anche un BGContinuedProcessingTask.
    func begin(_ messageId: String, preview: UIImage? = nil, longRunning: Bool = false) {
        progress[messageId] = .some(nil)
        if let preview { previews[messageId] = preview }
        startBackgroundProtection(messageId, longRunning: longRunning)
    }

    func setPreview(_ image: UIImage?, for messageId: String) {
        guard let image, progress[messageId] != nil else { return }
        previews[messageId] = image
    }

    func update(_ messageId: String, _ value: Double) {
        guard progress[messageId] != nil else { return }
        let clamped = min(max(value, 0), 1)
        progress[messageId] = clamped
        reportContinuedProgress(messageId, clamped)
    }

    func end(_ messageId: String) {
        stopBackgroundProtection(messageId, success: !cancelled.contains(messageId))
        progress[messageId] = nil
        previews[messageId] = nil
        cancelHandlers[messageId] = nil
        cancelled.remove(messageId)
    }

    // MARK: - Annullamento (tasto stop nell'anello)

    private var cancelHandlers: [String: () -> Void] = [:]
    private var cancelled: Set<String> = []

    /// Registrato da chi ha in mano il task di Storage. Se lo stop è già stato
    /// premuto (per esempio durante la compressione) scatta subito.
    func setCancelHandler(_ messageId: String, _ handler: @escaping () -> Void) {
        if cancelled.contains(messageId) { handler() } else { cancelHandlers[messageId] = handler }
    }

    /// Stop dall'anello: ferma il caricamento in corso; i percorsi d'invio
    /// vedono `isCancelled` e tolgono il messaggio invece di pubblicarlo.
    func cancel(_ messageId: String) {
        guard progress[messageId] != nil else { return }
        cancelled.insert(messageId)
        cancelHandlers.removeValue(forKey: messageId)?()
    }

    func isCancelled(_ messageId: String) -> Bool { cancelled.contains(messageId) }

    func isActive(_ messageId: String) -> Bool { progress[messageId] != nil }

    // MARK: - Background
    //
    // Senza protezioni iOS sospende l'app pochi secondi dopo il passaggio in
    // background e l'upload di Firebase Storage si ferma a metà.
    // 1. Ogni invio chiede un background task (~30 s, non garantiti): basta per
    //    foto, vocali, documenti piccoli.
    // 2. Gli invii lunghi (video, file grandi) chiedono in più un
    //    BGContinuedProcessingTask (iOS 26): il sistema lo lascia continuare
    //    oltre i 30 s e mostra l'avanzamento, con uno stop che equivale allo stop
    //    nell'anello. Se il sistema non lo concede (strategia .fail) resta il 1.

    private var backgroundTaskIds: [String: UIBackgroundTaskIdentifier] = [:]
    private var continuedTasks: [String: BGContinuedProcessingTask] = [:]
    private var heartbeats: [String: Task<Void, Never>] = [:]

    /// Deve iniziare col bundle id; il prefisso con `*` è in BGTaskSchedulerPermittedIdentifiers.
    private static let continuedPrefix = (Bundle.main.bundleIdentifier ?? "it.vittorioscocca.KidBox") + ".chat-upload."
    /// Unità del Progress di sistema: 0–10% preparazione (compressione), poi upload.
    private static let totalUnits: Int64 = 1000
    private static let preparationUnits: Int64 = 100

    private func startBackgroundProtection(_ messageId: String, longRunning: Bool) {
        if backgroundTaskIds[messageId] == nil {
            let id = UIApplication.shared.beginBackgroundTask(withName: "chat-upload") { [weak self] in
                // Scaduto il tempo: va chiuso subito o iOS termina l'app.
                MainActor.assumeIsolated { self?.endBackgroundTask(messageId) }
            }
            if id != .invalid { backgroundTaskIds[messageId] = id }
        }
        if longRunning { submitContinuedTask(messageId) }
    }

    private func endBackgroundTask(_ messageId: String) {
        guard let id = backgroundTaskIds.removeValue(forKey: messageId) else { return }
        UIApplication.shared.endBackgroundTask(id)
    }

    private func submitContinuedTask(_ messageId: String) {
        let identifier = Self.continuedPrefix + messageId
        // I continued processing task si registrano quando servono, non al lancio;
        // l'identificatore è unico per messaggio, quindi mai registrato due volte.
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let task = task as? BGContinuedProcessingTask, let self else {
                    task.setTaskCompleted(success: false); return
                }
                self.attachContinuedTask(task, to: messageId)
            }
        }
        guard registered else {
            KBLog.data.kbError("ChatUpload continued task not registered id=\(identifier)")
            return
        }
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: String(localized: "Invio in corso…"),
            subtitle: String(localized: "Chat di famiglia")
        )
        // Serve adesso o mai: se il sistema non può avviarlo subito resta il background task.
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            KBLog.data.kbInfo("ChatUpload continued task not granted: \(error.localizedDescription)")
        }
    }

    private func attachContinuedTask(_ task: BGContinuedProcessingTask, to messageId: String) {
        // Invio già finito prima che il sistema consegnasse il task.
        guard progress[messageId] != nil else { task.setTaskCompleted(success: true); return }
        continuedTasks[messageId] = task
        task.progress.totalUnitCount = Self.totalUnits
        // Stop dalla notifica di sistema, o il sistema che deve fermarlo: come lo stop nell'anello.
        // Il task si chiude subito: se l'invio è in compressione (non interrompibile)
        // end() arriverebbe troppo tardi per il sistema.
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.heartbeats.removeValue(forKey: messageId)?.cancel()
                self.continuedTasks.removeValue(forKey: messageId)?.setTaskCompleted(success: false)
                self.cancel(messageId)
            }
        }
        if let value = progress[messageId] ?? nil {
            reportContinuedProgress(messageId, value)
        } else {
            startHeartbeat(messageId)
        }
    }

    /// Durante la compressione non c'è un avanzamento vero; il sistema però chiude
    /// i task che non avanzano. Si fa crescere piano la fase di preparazione, mai oltre il 10%.
    private func startHeartbeat(_ messageId: String) {
        heartbeats[messageId]?.cancel()
        heartbeats[messageId] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, let task = self.continuedTasks[messageId] else { return }
                let next = task.progress.completedUnitCount + 5
                if next < Self.preparationUnits { task.progress.completedUnitCount = next }
            }
        }
    }

    private func reportContinuedProgress(_ messageId: String, _ value: Double) {
        guard let task = continuedTasks[messageId] else { return }
        heartbeats.removeValue(forKey: messageId)?.cancel()
        let upload = Self.totalUnits - Self.preparationUnits
        task.progress.completedUnitCount = Self.preparationUnits + Int64(Double(upload) * value)
    }

    private func stopBackgroundProtection(_ messageId: String, success: Bool) {
        heartbeats.removeValue(forKey: messageId)?.cancel()
        if let task = continuedTasks.removeValue(forKey: messageId) {
            if success { task.progress.completedUnitCount = Self.totalUnits }
            task.setTaskCompleted(success: success)
        }
        endBackgroundTask(messageId)
    }

    // MARK: - Anteprime

    nonisolated static func photoPreview(from data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 900
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }.value
    }

    nonisolated static func videoPreview(from url: URL) async -> UIImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 900, height: 900)
        guard let (cg, _) = try? await gen.image(at: .zero) else { return nil }
        return UIImage(cgImage: cg)
    }

    nonisolated static func videoPreview(from data: Data) async -> UIImage? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        guard (try? data.write(to: url)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        return await videoPreview(from: url)
    }
}

// MARK: - Anello

/// Anello di avanzamento: indeterminato (gira) finché non arriva il primo
/// progresso, poi si riempie. Non disegna nulla se il messaggio non è in invio.
struct ChatUploadRing: View {
    let messageId: String
    var diameter: CGFloat = 46
    var tint: Color = ChatProgressRing.mediaTint
    var backdrop: Color = ChatProgressRing.mediaBackdrop

    @ObservedObject private var store = ChatUploadProgressStore.shared

    var body: some View {
        if let entry = store.progress[messageId] {
            ChatProgressRing(value: entry, diameter: diameter, tint: tint, backdrop: backdrop,
                             onCancel: { store.cancel(messageId) })
        }
    }
}

struct ChatProgressRing: View {
    /// Come WhatsApp sopra foto e video: disco chiaro traslucido, anello e stop scuri.
    static let mediaTint = Color(white: 0.28)
    static let mediaBackdrop = Color.white.opacity(0.62)

    let value: Double?
    var diameter: CGFloat = 46
    var tint: Color = ChatProgressRing.mediaTint
    var backdrop: Color = ChatProgressRing.mediaBackdrop
    /// Tocco sull'anello = stop dell'invio. nil: solo indicatore.
    var onCancel: (() -> Void)? = nil

    @State private var spin = false

    private var lineWidth: CGFloat { max(2.5, diameter * 0.075) }

    var body: some View {
        if let onCancel {
            Button(action: onCancel) { ring }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Annulla"))
                .accessibilityValue(value.map { Text("\(Int($0 * 100))%") } ?? Text(""))
        } else {
            ring
                .accessibilityElement()
                .accessibilityLabel(Text("Invio in corso…"))
                .accessibilityValue(value.map { Text("\(Int($0 * 100))%") } ?? Text(""))
        }
    }

    private var ring: some View {
        ZStack {
            Circle().fill(backdrop)
            Circle()
                .stroke(tint.opacity(0.25), lineWidth: lineWidth)
                .padding(lineWidth * 1.5)
            Group {
                if let value {
                    Circle()
                        .trim(from: 0, to: max(value, 0.03))
                        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: value)
                } else {
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(spin ? 270 : -90))
                        .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
                        .onAppear { spin = true }
                }
            }
            .padding(lineWidth * 1.5)
            // Stop: tocca per annullare l'invio.
            RoundedRectangle(cornerRadius: diameter * 0.04)
                .fill(tint)
                .frame(width: diameter * 0.2, height: diameter * 0.2)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
    }
}

/// L'anello se il messaggio è in invio, altrimenti `fallback`.
struct ChatUploadIndicator<Fallback: View>: View {
    let messageId: String
    var diameter: CGFloat = 46
    var tint: Color = ChatProgressRing.mediaTint
    var backdrop: Color = ChatProgressRing.mediaBackdrop
    @ViewBuilder let fallback: () -> Fallback

    @ObservedObject private var store = ChatUploadProgressStore.shared

    var body: some View {
        if let entry = store.progress[messageId] {
            ChatProgressRing(value: entry, diameter: diameter, tint: tint, backdrop: backdrop,
                             onCancel: { store.cancel(messageId) })
        } else {
            fallback()
        }
    }
}

// MARK: - Segnaposto media in invio

/// Riquadro di una foto/video non ancora caricati. Durante il nostro invio:
/// anteprima locale (o fondo scuro) + anello + orario; altrimenti lo spinner
/// di chi aspetta un media altrui.
struct ChatPendingMediaView: View {
    let messageId: String
    let size: CGSize
    let timeOverlay: AnyView

    @ObservedObject private var store = ChatUploadProgressStore.shared

    var body: some View {
        let active = store.isActive(messageId)
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                if let preview = store.previews[messageId] {
                    Image(uiImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else {
                    Rectangle().fill(active ? Color.black.opacity(0.75) : Color(.tertiarySystemBackground))
                }
                if let entry = store.progress[messageId] {
                    ChatProgressRing(value: entry, onCancel: { store.cancel(messageId) })
                } else {
                    ProgressView()
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if active { timeOverlay }
        }
    }
}

// MARK: - Dimensioni

struct ChatMediaDimensions { let width: Int; let height: Int }

extension ChatUploadProgressStore {
    /// Dimensioni come si vedono: con orientamento EXIF 5…8 larghezza e altezza si scambiano.
    nonisolated static func photoDimensions(from data: Data) -> ChatMediaDimensions? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              w > 0, h > 0 else { return nil }
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return orientation >= 5 ? ChatMediaDimensions(width: h, height: w) : ChatMediaDimensions(width: w, height: h)
    }

    /// Dimensioni del video con la rotazione della traccia applicata (i verticali
    /// dell'iPhone sono 1920×1080 ruotati di 90°).
    nonisolated static func videoDimensions(from url: URL) async -> ChatMediaDimensions? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return nil }
        let r = CGRect(origin: .zero, size: natural).applying(transform)
        let w = Int(abs(r.width).rounded()), h = Int(abs(r.height).rounded())
        return w > 0 && h > 0 ? ChatMediaDimensions(width: w, height: h) : nil
    }

    nonisolated static func videoDimensions(from data: Data) async -> ChatMediaDimensions? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        guard (try? data.write(to: url)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: url) }
        return await videoDimensions(from: url)
    }
}
