//
//  KBVideoEncoder.swift
//  KidBox
//
//  Ricodifica dei video con parametri espliciti, per chat e album.
//
//  Prima si usava AVAssetExportPresetMediumQuality: un verticale 1080×1920
//  usciva 320×568 a 0,7 Mbps, sgranato su qualunque telefono. I preset a
//  risoluzione fissa (1280×720) non controllano il bitrate e un minuto pesava
//  ~50 MB. Qui si fissa tutto: lato lungo, bitrate H.264 (scalato sull'area se
//  il video è più piccolo), AAC 128 kbps. H.264 in MP4 perché Android e web lo
//  riproducono ovunque.
//

import AVFoundation

enum KBVideoEncoder {

    struct Profile: Sendable {
        /// Lato lungo massimo del video codificato.
        let maxSide: CGFloat
        /// Bitrate a piena risoluzione del profilo; i video più piccoli ne ricevono in proporzione all'area.
        let videoBitrate: Int

        /// Chat: 720p a ~2 Mbps, circa 16 MB al minuto. Si manda e si guarda sul telefono.
        static let chat = Profile(maxSide: 1280, videoBitrate: 2_000_000)
        /// Album Foto e video: 1080p a ~4,5 Mbps, circa 35 MB al minuto. È l'archivio dei ricordi.
        static let album = Profile(maxSide: 1920, videoBitrate: 4_500_000)
    }

    static let minVideoBitrate = 600_000
    static let audioBitrate = 128_000

    enum CompressionError: Error { case noVideoTrack, cannotRead, cannotWrite(String) }

    /// Restituisce un nuovo .mp4 nella cartella temporanea (lo cancella il chiamante).
    static func compress(_ source: URL, profile: Profile) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw CompressionError.noVideoTrack
        }
        let (natural, transform) = try await videoTrack.load(.naturalSize, .preferredTransform)
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first

        // Dimensioni di codifica: quelle «native» della traccia, ridotte; la rotazione
        // resta nel transform, così un verticale resta verticale.
        let scale = min(1, profile.maxSide / max(natural.width, natural.height))
        let width = even(natural.width * scale)
        let height = even(natural.height * scale)
        // Area di riferimento: il 16:9 al lato lungo del profilo.
        let fullArea = Double(profile.maxSide) * Double(profile.maxSide) * 9 / 16
        let area = Double(width * height) / fullArea
        let bitrate = max(minVideoBitrate, Int(Double(profile.videoBitrate) * min(area, 1)))

        let reader = try AVAssetReader(asset: asset)
        let videoOut = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        videoOut.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOut) else { throw CompressionError.cannotRead }
        reader.add(videoOut)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
            ],
        ])
        videoIn.transform = transform
        videoIn.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoIn) else { throw CompressionError.cannotWrite("video") }
        writer.add(videoIn)

        var audioPair: (AVAssetReaderTrackOutput, AVAssetWriterInput)?
        if let audioTrack {
            let channels = try await channelCount(of: audioTrack)
            let audioOut = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
            ])
            let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: channels,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: channels == 1 ? audioBitrate / 2 : audioBitrate,
            ])
            audioIn.expectsMediaDataInRealTime = false
            // Un audio che non si riesce a ricodificare non deve far perdere il video.
            if reader.canAdd(audioOut), writer.canAdd(audioIn) {
                reader.add(audioOut)
                writer.add(audioIn)
                audioPair = (audioOut, audioIn)
            }
        }

        guard reader.startReading() else { throw reader.error ?? CompressionError.cannotRead }
        guard writer.startWriting() else {
            reader.cancelReading()
            throw writer.error ?? CompressionError.cannotWrite("start")
        }
        writer.startSession(atSourceTime: .zero)

        let pumps = [(videoOut, videoIn)] + (audioPair.map { [$0] } ?? [])
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for (index, (output, input)) in pumps.enumerated() {
                group.enter()
                let pump = SamplePump(output: output, input: input, onDone: { group.leave() })
                input.requestMediaDataWhenReady(on: DispatchQueue(label: "kidbox.chat.video-compress.\(index)")) {
                    pump.drain()
                }
            }
            group.notify(queue: .global()) { continuation.resume() }
        }

        if reader.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw reader.error ?? CompressionError.cannotRead
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            throw writer.error ?? CompressionError.cannotWrite("finish")
        }
        return outputURL
    }

    private static func even(_ value: CGFloat) -> Int { max(2, Int((value / 2).rounded()) * 2) }

    private static func channelCount(of track: AVAssetTrack) async throws -> Int {
        let formats = try await track.load(.formatDescriptions)
        let channels = formats.first
            .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame }
            .map(Int.init) ?? 2
        return min(max(channels, 1), 2)
    }
}

/// Copia i campioni da un output del reader a un input del writer quando il
/// writer è pronto. Chiamato sempre dalla stessa coda seriale.
private final class SamplePump: @unchecked Sendable {
    private let output: AVAssetReaderOutput
    private let input: AVAssetWriterInput
    private let onDone: () -> Void
    private var finished = false

    init(output: AVAssetReaderOutput, input: AVAssetWriterInput, onDone: @escaping () -> Void) {
        self.output = output
        self.input = input
        self.onDone = onDone
    }

    func drain() {
        guard !finished else { return }
        while input.isReadyForMoreMediaData {
            guard let sample = output.copyNextSampleBuffer(), input.append(sample) else {
                finished = true
                input.markAsFinished()
                onDone()
                return
            }
        }
    }
}
