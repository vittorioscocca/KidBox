import Foundation
import Speech
import AVFoundation

@available(iOS 26.0, *)
final class SpeechTranscriptionService {
    
    static let shared = SpeechTranscriptionService()
    
    private init() {}
    
    struct Result {
        let text: String
        let isFinal: Bool
        let localeIdentifier: String
    }
    
    func transcribeFile(
        at fileURL: URL,
        localeIdentifier: String = "it-IT"
    ) async throws -> Result {
        
        let locale = Locale(identifier: localeIdentifier)
        
        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .transcription
        )
        
        async let transcriptionFuture: String = try transcriber.results
            .reduce("") { partial, result in
                partial + String(result.text.characters)
            }
        
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        
        let audioFile = try AVAudioFile(forReading: fileURL)
        
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        
        let finalText = try await transcriptionFuture
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        return Result(
            text: finalText,
            isFinal: true,
            localeIdentifier: localeIdentifier
        )
    }
}
