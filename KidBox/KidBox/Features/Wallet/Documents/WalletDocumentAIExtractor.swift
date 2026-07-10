//
//  WalletDocumentAIExtractor.swift
//  KidBox
//
//  Created by vscocca on 10/07/26.
//
//  Lettura "assistita AI" dei documenti d'identità del Wallet: manda le
//  immagini scansionate al modello vision (via la Cloud Function `askAI`,
//  Haiku 4.5) e ne ricava i campi strutturati. Riservata al piano Max.
//
//  Costo in "messaggi" (contatore famiglia): il server conta ogni immagine
//  come 1 unità (50.000 caratteri) + il prompt → ≈ n_immagini + 1. Il costo
//  è mostrato all'utente prima dell'invio; il contatore reale viene aggiornato
//  da `AIService` (che riflette `usageToday`/`messageUnitsConsumed` del server).
//

import Foundation
import UIKit

enum WalletDocumentAIExtractorError: LocalizedError {
    case noImages
    case emptyReply
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .noImages:    return "Nessuna immagine da analizzare."
        case .emptyReply:  return "L'AI non ha restituito dati."
        case .invalidJSON: return "Risposta AI non interpretabile."
        }
    }
}

enum WalletDocumentAIExtractor {

    /// Lato lungo massimo dell'immagine inviata (px) e qualità JPEG.
    private static let maxImageSide: CGFloat = 1600
    private static let jpegQuality: CGFloat = 0.6
    private static let purpose = "wallet_doc"

    /// Stima delle unità-messaggio consumate: il server conta 1 unità per
    /// immagine (50k char-equivalent) + 1 per il prompt. `ceil((n·50k + p)/50k)`
    /// con `p>0` ⇒ `n + 1`.
    static func estimatedMessageUnits(imageCount: Int) -> Int {
        max(1, imageCount + 1)
    }

    /// Analizza le immagini e riempie una `WalletDocumentExtraction`.
    static func extract(images: [UIImage], kind: KBWalletDocumentKind) async throws -> WalletDocumentExtraction {
        let jpegs = images.compactMap { downscaledJPEG($0) }
        guard !jpegs.isEmpty else { throw WalletDocumentAIExtractorError.noImages }

        var blocks: [[String: Any]] = []
        for jpeg in jpegs {
            blocks.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": jpeg.base64EncodedString(),
                ],
            ])
        }
        blocks.append(["type": "text", "text": userPrompt(kind: kind)])

        let payload = [AIMessagePayload(role: "user", content: blocks)]
        let response = try await AIService.shared.sendMessages(
            messages: payload,
            systemPrompt: systemPrompt,
            purpose: purpose
        )

        let reply = response.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { throw WalletDocumentAIExtractorError.emptyReply }
        guard let parsed = parse(reply) else { throw WalletDocumentAIExtractorError.invalidJSON }
        return mapping(parsed, kind: kind, rawText: reply)
    }

    // MARK: - Prompt

    private static let systemPrompt = """
    Sei un estrattore di dati da documenti d'identità italiani (tessera sanitaria, \
    carta d'identità, CIE, patente di guida, passaporto, codice fiscale). \
    Ti vengono fornite una o più immagini (fronte/retro). Estrai i dati leggibili.

    Rispondi ESCLUSIVAMENTE con un oggetto JSON valido, senza testo prima o dopo, \
    senza markdown, senza ```. Schema:
    {
      "holderName": "Nome Cognome del titolare, o null",
      "birthInfo": "data e luogo di nascita come testo, o null",
      "documentNumber": "numero del documento, o null",
      "codiceFiscale": "codice fiscale a 16 caratteri se presente, o null",
      "issueDate": "AAAA-MM-GG o null",
      "expiryDate": "AAAA-MM-GG o null",
      "categories": [ {"code":"B","issueDate":"AAAA-MM-GG o null","expiryDate":"AAAA-MM-GG o null"} ]
    }

    REGOLE:
    - Non inventare dati: se un campo non è leggibile, usa null.
    - Le date SEMPRE in formato AAAA-MM-GG. Anno a 2 cifre: 00–49 → 2000+, 50–99 → 1900+.
    - PATENTE: il numero è al campo 5 del fronte. Le categorie con rilascio e \
    scadenza sono nella tabella sul retro (colonna 9 = categoria, colonna 10 = \
    rilascio, colonna 11 = scadenza). Includi in "categories" SOLO le categorie \
    che hanno almeno una data. NON usare le date dei campi 4a/4b/4c del fronte. \
    La patente NON ha codice fiscale: metti null.
    - TESSERA SANITARIA: "codiceFiscale" è quello a 16 caratteri; "categories" resta [].
    - Per i documenti diversi dalla patente lascia "categories": [].
    """

    private static func userPrompt(kind: KBWalletDocumentKind) -> String {
        "Tipo documento indicato dall'utente: \(kind.displayName). Estrai i dati in JSON."
    }

    // MARK: - Parse / mapping

    private struct AIResult: Decodable {
        let holderName: String?
        let birthInfo: String?
        let documentNumber: String?
        let codiceFiscale: String?
        let issueDate: String?
        let expiryDate: String?
        let categories: [AICategory]?

        struct AICategory: Decodable {
            let code: String?
            let issueDate: String?
            let expiryDate: String?
        }
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

    private static func mapping(_ r: AIResult, kind: KBWalletDocumentKind, rawText: String) -> WalletDocumentExtraction {
        let cats: [KBPatenteCategory] = (r.categories ?? []).compactMap { c in
            let code = (c.code ?? "").trimmingCharacters(in: .whitespaces).uppercased()
            guard !code.isEmpty else { return nil }
            return KBPatenteCategory(code: code, issueDate: date(c.issueDate), expiryDate: date(c.expiryDate))
        }
        return WalletDocumentExtraction(
            codiceFiscale: kind == .patente ? nil : nonEmpty(r.codiceFiscale),
            holderName: nonEmpty(r.holderName),
            birthInfo: nonEmpty(r.birthInfo),
            documentNumber: nonEmpty(r.documentNumber),
            issueDate: kind == .patente ? nil : date(r.issueDate),
            expiryDate: kind == .patente ? nil : date(r.expiryDate),
            patenteCategories: kind == .patente ? cats : [],
            rawText: rawText
        )
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, s.lowercased() != "null" else { return nil }
        return s
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Rome")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func date(_ s: String?) -> Date? {
        guard let s = nonEmpty(s) else { return nil }
        return dateFormatter.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    // MARK: - Image downscale

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
