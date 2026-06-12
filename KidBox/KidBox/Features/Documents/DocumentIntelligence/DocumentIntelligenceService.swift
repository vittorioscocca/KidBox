//
//  DocumentIntelligenceService.swift
//  KidBox
//
//  Analizza un documento importato (vision, Claude Haiku) e propone azioni
//  cross-feature. Opt-in da AISettings.documentIntelligenceEnabled.
//

import Foundation
import PDFKit
import UIKit

enum DocumentIntelligenceService {

    /// Contesto entità per permettere all'AI di indirizzare le azioni.
    struct ChildRef { let id: String; let name: String }
    struct VehicleRef { let id: String; let label: String }

    /// Max pagine PDF inviate come immagini (= max unità messaggio consumate).
    private static let maxPages = 3
    /// Lato lungo massimo dell'immagine inviata (px).
    private static let maxImageSide: CGFloat = 1600
    private static let jpegQuality: CGFloat = 0.6

    private static let purpose = "doc_intelligence"

    /// Analizza il documento e ritorna le azioni proposte, oppure `nil` se
    /// non c'è nulla da proporre o l'analisi fallisce.
    static func analyze(
        data: Data,
        fileName: String,
        mimeType: String,
        children: [ChildRef],
        vehicles: [VehicleRef]
    ) async -> DocIntelResult? {

        let images = renderImages(data: data, mimeType: mimeType)
        guard !images.isEmpty else {
            KBLog.ai.kbInfo("DocIntel: nessuna immagine renderizzabile da \(fileName)")
            return nil
        }

        var blocks: [[String: Any]] = []
        for jpeg in images {
            blocks.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": jpeg.base64EncodedString(),
                ],
            ])
        }
        blocks.append(["type": "text", "text": userPrompt(fileName: fileName, children: children, vehicles: vehicles)])

        let payload = [AIMessagePayload(role: "user", content: blocks)]

        do {
            let response = try await AIService.shared.sendMessages(
                messages: payload,
                systemPrompt: systemPrompt,
                purpose: purpose
            )
            return parse(response.reply)
        } catch {
            KBLog.ai.kbError("DocIntel: analisi fallita \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Rendering

    private static func renderImages(data: Data, mimeType: String) -> [Data] {
        if mimeType.hasPrefix("image/") {
            if let img = UIImage(data: data), let jpeg = downscaledJPEG(img) {
                return [jpeg]
            }
            return []
        }
        // PDF (o fallback): prova a renderizzare le pagine.
        guard let pdf = PDFDocument(data: data) else { return [] }
        var out: [Data] = []
        let pageCount = min(pdf.pageCount, maxPages)
        for i in 0..<pageCount {
            guard let page = pdf.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale = min(maxImageSide / max(bounds.width, bounds.height), 2.0)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let img = page.thumbnail(of: size, for: .mediaBox)
            if let jpeg = img.jpegData(compressionQuality: jpegQuality) {
                out.append(jpeg)
            }
        }
        return out
    }

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

    // MARK: - Prompt

    private static var systemPrompt: String {
        """
        Sei l'assistente di KidBox, un'app di gestione familiare. Analizzi un documento \
        (immagini delle pagine) e proponi azioni concrete da svolgere nell'app.

        Rispondi ESCLUSIVAMENTE con un oggetto JSON valido (nessun testo prima o dopo, \
        niente markdown, niente ```), con questa forma:
        {
          "documentType": "tipo di documento in italiano (es. referto medico, fattura, polizza auto)",
          "suggestedTitle": "titolo breve e leggibile per il documento, senza estensione",
          "actions": [ ...azioni... ]
        }

        Ogni azione è un oggetto con "type", una "summary" (frase breve in italiano che \
        descrive cosa farà l'azione) e i campi pertinenti. Date sempre in ISO8601 UTC. \
        Tipi disponibili:
        - expense_add: spesa da fattura/scontrino. {"type":"expense_add","title":"...","amount":12.50,"date":"...","summary":"..."}
        - event_add: evento/appuntamento. {"type":"event_add","title":"...","date":"<startAt>","endDate":"...","isAllDay":false,"notes":"...","childId":"...","summary":"..."}
        - todo_add: cosa da fare. {"type":"todo_add","title":"...","date":"<dueAt>","childId":"...","summary":"..."}
        - health_reminder: promemoria sanitario (es. richiamo, controllo). {"type":"health_reminder","title":"...","date":"<dueAt>","childId":"...","summary":"..."}
        - note_add: nota/sintesi del documento. {"type":"note_add","title":"...","body":"...","summary":"..."}
        - vehicle_event: scadenza/intervento veicolo (assicurazione, bollo, tagliando, revisione). {"type":"vehicle_event","vehicleId":"<id veicolo se combacia>","vehicleEventType":"insurance|tax|revision|service|repair|tire|altro","title":"...","date":"...","amount":0,"summary":"..."}
        - medical_visit: visita medica. {"type":"medical_visit","childId":"<id figlio>","doctorName":"...","date":"...","notes":"diagnosi/raccomandazioni","summary":"..."}
        - vaccine_add: vaccino somministrato. {"type":"vaccine_add","childId":"<id figlio>","vaccineType":"esavalente|pneumococco|meningococcoB|mpr|varicella|meningococcoACWY|hpv|influenza|altro","date":"<administeredDate>","title":"nome commerciale","summary":"..."}
        - rename_document: rinomina il documento col titolo corretto. {"type":"rename_document","renameTo":"...","summary":"..."}

        REGOLE:
        - Proponi solo azioni realmente supportate dal contenuto del documento. Non inventare dati.
        - Usa childId / vehicleId SOLO se uno tra quelli forniti combacia chiaramente; altrimenti ometti il campo.
        - Includi quasi sempre "rename_document" con un titolo pulito, e quando ha senso un "note_add" riassuntivo.
        - Se il documento non contiene nulla di utile, ritorna "actions": [].
        - Gli importi sono numeri (punto decimale), senza simbolo di valuta.
        """
    }

    private static func userPrompt(fileName: String, children: [ChildRef], vehicles: [VehicleRef]) -> String {
        let iso = ISO8601DateFormatter()
        let today = iso.string(from: Date())
        var s = "Data odierna: \(today). Nome file originale: \"\(fileName)\".\n"
        if children.isEmpty {
            s += "Figli in famiglia: nessuno.\n"
        } else {
            s += "Figli in famiglia (id → nome): " + children.map { "\($0.id) → \($0.name)" }.joined(separator: "; ") + ".\n"
        }
        if vehicles.isEmpty {
            s += "Veicoli: nessuno.\n"
        } else {
            s += "Veicoli (id → descrizione): " + vehicles.map { "\($0.id) → \($0.label)" }.joined(separator: "; ") + ".\n"
        }
        s += "Analizza le pagine e proponi le azioni in JSON."
        return s
    }

    // MARK: - Parse

    private static func parse(_ reply: String) -> DocIntelResult? {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        // Rimuovi eventuali fence ```json ... ```
        if text.hasPrefix("```") {
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
            if let fence = text.range(of: "```", options: .backwards) {
                text = String(text[..<fence.lowerBound])
            }
        }
        // Estrai il primo oggetto JSON bilanciato.
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"), start < end else {
            KBLog.ai.kbError("DocIntel: nessun JSON nella risposta")
            return nil
        }
        let json = String(text[start...end])
        guard let data = json.data(using: .utf8),
              let result = try? JSONDecoder().decode(DocIntelResult.self, from: data) else {
            KBLog.ai.kbError("DocIntel: JSON non decodificabile")
            return nil
        }
        return result
    }
}
