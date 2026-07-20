//
//  WalletTicketAIExtractor.swift
//  KidBox
//
//  Lettura "assistita AI" dei biglietti del Wallet (stessa Cloud Function
//  `askAI` dei documenti d'identità, nuovo purpose "wallet_ticket"; nessuna
//  modifica backend: il `purpose` è gestito interamente lato client). A
//  differenza dei documenti d'identità (foto scattate con lo scanner), un
//  biglietto PDF ha quasi sempre un layer di testo reale già estratto da
//  `WalletPDFParser` (PDFKit): mandare quel testo all'AI è più preciso
//  (nessun errore OCR/vision) e più economico (1 unità messaggio invece di
//  1 per immagine). Se il testo è troppo corto (biglietto scansionato come
//  immagine), ripiego su un'immagine della prima pagina, stesso schema di
//  `WalletDocumentAIExtractor`.
//

import Foundation
import UIKit

/// Campi biglietto letti dall'AI: partenza/arrivo separati, titolare, codice.
struct WalletTicketExtraction {
    var holderName: String?
    var bookingCode: String?
    var emitter: String?
    var kind: KBWalletTicketKind?
    var departureLocation: String?
    var departureDateTime: Date?
    var arrivalLocation: String?
    var arrivalDateTime: Date?
    var rawText: String = ""
}

enum WalletTicketAIExtractorError: LocalizedError {
    case noContent
    case emptyReply
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .noContent:   return "Nessun testo o immagine da analizzare."
        case .emptyReply:  return "L'AI non ha restituito dati."
        case .invalidJSON: return "Risposta AI non interpretabile."
        }
    }
}

enum WalletTicketAIExtractor {

    private static let maxImageSide: CGFloat = 1600
    private static let jpegQuality: CGFloat = 0.6
    private static let minTextLength = 40
    private static let maxTextChars = 6000
    private static let purpose = "wallet_ticket"

    /// Stessa formula del server: 1 unità per il testo (sotto 50k caratteri-equivalenti), +1 se serve un'immagine di fallback.
    static func estimatedMessageUnits(usedImageFallback: Bool) -> Int {
        usedImageFallback ? 2 : 1
    }

    /// Analizza il testo estratto dal PDF (o, in mancanza di testo, un'immagine di fallback).
    static func extract(text: String?, fallbackImage: UIImage?) async throws -> WalletTicketExtraction {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var blocks: [[String: Any]] = []
        if trimmed.count >= minTextLength {
            blocks.append(["type": "text", "text": userPromptForText(String(trimmed.prefix(maxTextChars)))])
        } else if let fallbackImage, let jpeg = downscaledJPEG(fallbackImage) {
            blocks.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": jpeg.base64EncodedString(),
                ],
            ])
            blocks.append(["type": "text", "text": userPromptForImage()])
        } else {
            throw WalletTicketAIExtractorError.noContent
        }

        let payload = [AIMessagePayload(role: "user", content: blocks)]
        let response = try await AIService.shared.sendMessages(
            messages: payload,
            systemPrompt: systemPrompt,
            purpose: purpose
        )

        let reply = response.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { throw WalletTicketAIExtractorError.emptyReply }
        guard let parsed = parse(reply) else { throw WalletTicketAIExtractorError.invalidJSON }
        return mapping(parsed, rawText: reply)
    }

    // MARK: - Prompt

    private static let systemPrompt = """
    Sei un estrattore di dati da biglietti/titoli di viaggio italiani ed \
    europei (treno, aereo, traghetto, autobus, ma anche cinema/concerti/ \
    parcheggi/musei). Ti viene fornito il testo estratto dal PDF del \
    biglietto (o, in mancanza di testo, un'immagine del biglietto).

    Rispondi ESCLUSIVAMENTE con un oggetto JSON valido, senza testo prima o \
    dopo, senza markdown, senza ```. Schema:
    {
      "holderName": "nome e cognome del titolare/passeggero, o null",
      "bookingCode": "codice di prenotazione/PNR/biglietto, o null",
      "emitter": "nome del vettore/emittente (es. Trenitalia, Ryanair), o null",
      "kind": "uno tra train|flight|ferry|bus|concert|cinema|parking|museum|other, o null",
      "departureLocation": "luogo/stazione/aeroporto di partenza, o null",
      "departureDateTime": "AAAA-MM-GGTHH:MM (partenza) o null",
      "arrivalLocation": "luogo/stazione/aeroporto di arrivo, o null",
      "arrivalDateTime": "AAAA-MM-GGTHH:MM (arrivo) o null"
    }

    REGOLE:
    - Non inventare dati: se un campo non è presente/leggibile, usa null.
    - Le date/ore SEMPRE in formato AAAA-MM-GGTHH:MM (24h), anno a 4 cifre.
    - Se è indicato solo un orario senza data esplicita, deducila dal contesto \
    (es. altre date presenti nel testo); se non è possibile, usa null.
    - Per biglietti che non sono viaggi (cinema, concerto, parcheggio, museo) \
    "departureLocation"/"departureDateTime" rappresentano semplicemente \
    luogo e orario dell'evento; "arrivalLocation"/"arrivalDateTime" restano null.
    """

    private static func userPromptForText(_ text: String) -> String {
        "Testo estratto dal PDF del biglietto:\n\n\(text)\n\nEstrai i dati in JSON."
    }

    private static func userPromptForImage() -> String {
        "L'immagine mostra un biglietto/documento di viaggio. Estrai i dati in JSON."
    }

    // MARK: - Parse / mapping

    private struct AIResult: Decodable {
        let holderName: String?
        let bookingCode: String?
        let emitter: String?
        let kind: String?
        let departureLocation: String?
        let departureDateTime: String?
        let arrivalLocation: String?
        let arrivalDateTime: String?
    }

    private static func parse(_ reply: String) -> AIResult? {
        var text = reply
        if text.hasPrefix("```") {
            if let nl = text.firstIndex(of: "\n") { text = String(text[text.index(after: nl)...]) }
            if let fence = text.range(of: "```", options: .backwards) { text = String(text[..<fence.lowerBound]) }
        }
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"), start < end else { return nil }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8),
              let result = try? JSONDecoder().decode(AIResult.self, from: data) else { return nil }
        return result
    }

    private static func mapping(_ r: AIResult, rawText: String) -> WalletTicketExtraction {
        WalletTicketExtraction(
            holderName: nonEmpty(r.holderName),
            bookingCode: nonEmpty(r.bookingCode),
            emitter: nonEmpty(r.emitter),
            kind: r.kind.flatMap { KBWalletTicketKind(rawValue: $0) },
            departureLocation: nonEmpty(r.departureLocation),
            departureDateTime: dateTime(r.departureDateTime),
            arrivalLocation: nonEmpty(r.arrivalLocation),
            arrivalDateTime: dateTime(r.arrivalDateTime),
            rawText: rawText
        )
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, s.lowercased() != "null" else { return nil }
        return s
    }

    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    private static func dateTime(_ s: String?) -> Date? {
        guard let s = nonEmpty(s) else { return nil }
        return dateTimeFormatter.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    // MARK: - Image downscale (fallback)

    private static func downscaledJPEG(_ image: UIImage) -> Data? {
        let longSide = max(image.size.width, image.size.height)
        guard longSide > maxImageSide else {
            return image.jpegData(compressionQuality: jpegQuality)
        }
        let scale = maxImageSide / longSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return scaled.jpegData(compressionQuality: jpegQuality)
    }
}
