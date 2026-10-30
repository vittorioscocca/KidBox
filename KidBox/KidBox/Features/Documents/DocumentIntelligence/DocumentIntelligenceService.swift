//
//  DocumentIntelligenceService.swift
//  KidBox
//
//  Analizza un documento importato (vision, Claude Haiku) e propone azioni
//  cross-feature. Opt-in da AISettings.documentIntelligenceEnabled.
//

import Foundation
import PDFKit
import SwiftData
import UIKit

enum DocumentIntelligenceService {

    /// Contesto entità per permettere all'AI di indirizzare le azioni.
    /// Persona dei dati sanitari: figlio (`childId`) o adulto (`userId`).
    struct ChildRef {
        let id: String
        let name: String
        var isAdult: Bool = false
    }
    struct VehicleRef { let id: String; let label: String }

    /// Max pagine PDF inviate come immagini (= max unità messaggio consumate).
    private static let maxPages = 3
    /// Lato lungo massimo dell'immagine inviata (px).
    private static let maxImageSide: CGFloat = 1600
    private static let jpegQuality: CGFloat = 0.6

    private static let purpose = "doc_intelligence"

    enum AnalyzeError: Error {
        /// Né immagine né PDF: niente da far leggere.
        case unreadable
        /// La risposta non era il JSON atteso.
        case badResponse
    }

    /// Analizza il documento e ritorna le azioni proposte, oppure `nil` se
    /// non c'è nulla da proporre o l'analisi fallisce.
    static func analyze(
        data: Data,
        fileName: String,
        mimeType: String,
        children: [ChildRef],
        vehicles: [VehicleRef]
    ) async -> DocIntelResult? {
        do {
            return try await analyzeThrowing(
                data: data, fileName: fileName, mimeType: mimeType,
                children: children, vehicles: vehicles
            )
        } catch {
            KBLog.ai.kbError("DocIntel: analisi fallita \(error.localizedDescription)")
            return nil
        }
    }

    /// Come `analyze`, ma l'errore arriva al chiamante (quota finita, rete…):
    /// la chat dell'assistente lo mostra invece di tacere.
    static func analyzeThrowing(
        data: Data,
        fileName: String,
        mimeType: String,
        children: [ChildRef],
        vehicles: [VehicleRef]
    ) async throws -> DocIntelResult {

        let images = renderImages(data: data, mimeType: mimeType)
        guard !images.isEmpty else {
            KBLog.ai.kbInfo("DocIntel: nessuna immagine renderizzabile da \(fileName)")
            throw AnalyzeError.unreadable
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

        let response = try await AIService.shared.sendMessages(
            messages: payload,
            systemPrompt: systemPrompt,
            purpose: purpose
        )
        guard let result = parse(response.reply) else { throw AnalyzeError.badResponse }
        return result
    }

    // MARK: - Contesto

    /// Persone della famiglia per Salute (figli, poi adulti) e veicoli: le
    /// stesse liste per l'import in Documenti e per il «+» dell'assistente.
    @MainActor
    static func familyRefs(familyId fid: String, modelContext: ModelContext) -> (persons: [ChildRef], vehicles: [VehicleRef]) {
        let kids = ((try? modelContext.fetch(FetchDescriptor<KBChild>())) ?? [])
            .filter { $0.familyId == fid }
            .map { ChildRef(id: $0.id, name: $0.name) }
        let adults = ((try? modelContext.fetch(
            FetchDescriptor<KBFamilyMember>(predicate: #Predicate { $0.familyId == fid })
        )) ?? [])
            .filter { !$0.isDeleted }
            .compactMap { m -> ChildRef? in
                guard let name = m.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
                return ChildRef(id: m.userId, name: name, isAdult: true)
            }
        let vehicles = ((try? modelContext.fetch(
            FetchDescriptor<KBVehicle>(predicate: #Predicate { $0.familyId == fid && !$0.isDeleted })
        )) ?? []).map { v -> VehicleRef in
            let label = [v.name, v.brand, v.model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            return VehicleRef(id: v.id, label: label.isEmpty ? v.name : label)
        }
        return (kids + adults, vehicles)
    }

    // MARK: - Rendering

    /// Anche per la scheda Lavoro (`WorkDocumentService`): stesse pagine, stesso costo.
    static func renderImages(data: Data, mimeType: String) -> [Data] {
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
        (immagini delle pagine), capisci CHE COS'È e lo smisti nella sezione giusta \
        dell'app, compilando la scheda di quella sezione con i dati letti.

        Rispondi ESCLUSIVAMENTE con un oggetto JSON valido (nessun testo prima o dopo, \
        niente markdown, niente ```), con questa forma:
        {
          "documentType": "tipo di documento in italiano (es. bolletta della luce, referto di visita, analisi del sangue, ricetta)",
          "category": "bill|medical_report|lab_results|prescription|receipt|vehicle|school|insurance|other",
          "suggestedTitle": "titolo breve e leggibile per il documento, senza estensione",
          "actions": [ ...azioni... ]
        }

        PRIMA classifica, POI scegli l'azione principale:
        - bill (bolletta luce/gas/acqua/internet/telefono/condominio, tassa IMU/TARI, rata mutuo/affitto) → house_payment. \
          NON aggiungere expense_add: la spesa nasce da sola dal pagamento di Casa.
        - medical_report (referto o relazione di una visita) → medical_visit con medico, data, diagnosis \
          (cosa ha detto il medico) e recommendations (cosa fare). Se prescrive farmaci aggiungi anche treatment_add; \
          se prescrive esami aggiungi exam_add senza resultText; se fissa un controllo aggiungi health_reminder.
        - lab_results (analisi del sangue, urine, radiografia, ecografia…) → exam_add con resultText che riporta \
          TUTTI i valori letti (nome, valore, unità, intervallo di riferimento; segna con * quelli fuori range).
        - prescription (ricetta, piano terapeutico, foglio di terapia) → un treatment_add per ogni farmaco.
        - receipt (scontrino, fattura di acquisto) → expense_add.
        - vehicle (bollo, assicurazione, revisione, tagliando) → vehicle_event (se il veicolo combacia) altrimenti event_add.
        - altro → event_add / todo_add / note_add solo se servono davvero.

        Ogni azione è un oggetto con "type", una "summary" (frase breve in italiano che \
        descrive cosa farà l'azione) e i campi pertinenti. Date sempre in ISO8601 UTC. \
        Tipi disponibili:
        - house_payment: pagamento/scadenza di Casa. {"type":"house_payment","paymentType":"bolletta|tassa|affitto|mutuo|altro","subtype":"luce|gas|acqua|internet|telefono|condominio|IMU|TARI|...","title":"nome breve es. Bolletta luce Enel ottobre","provider":"fornitore","amount":84.20,"date":"<scadenza del pagamento>","notes":"periodo, numero cliente, consumi","summary":"..."}
        - medical_visit: visita medica. {"type":"medical_visit","childId":"<id persona>","doctorName":"...","title":"motivo della visita","date":"...","diagnosis":"cosa ha detto il medico","recommendations":"indicazioni e terapia","notes":"...","summary":"..."}
        - exam_add: esame o analisi. {"type":"exam_add","childId":"<id persona>","title":"nome dell'esame","date":"<data del prelievo/esecuzione>","resultText":"valori letti, uno per riga","location":"laboratorio o struttura","notes":"...","summary":"..."}
        - treatment_add: cura con un farmaco. {"type":"treatment_add","childId":"<id persona>","title":"nome del farmaco","activeIngredient":"...","dosageValue":5,"dosageUnit":"ml|mg|compresse|gocce|bustine|supposte|puff|UI","dailyFrequency":2,"durationDays":7,"isLongTerm":false,"date":"<inizio>","notes":"istruzioni (es. dopo i pasti)","summary":"..."}
        - expense_add: spesa da scontrino/fattura. {"type":"expense_add","title":"...","amount":12.50,"date":"...","summary":"..."}
        - event_add: evento/appuntamento. {"type":"event_add","title":"...","date":"<startAt>","endDate":"...","isAllDay":false,"notes":"...","childId":"...","summary":"..."}
        - todo_add: cosa da fare. {"type":"todo_add","title":"...","date":"<dueAt>","childId":"...","summary":"..."}
        - health_reminder: promemoria sanitario (es. richiamo, controllo). {"type":"health_reminder","title":"...","date":"<dueAt>","childId":"...","summary":"..."}
        - note_add: nota/sintesi del documento. {"type":"note_add","title":"...","body":"...","summary":"..."}
        - vehicle_event: scadenza/intervento veicolo. {"type":"vehicle_event","vehicleId":"<id veicolo se combacia>","vehicleEventType":"insurance|tax|revision|service|repair|tire|altro","title":"...","date":"...","amount":0,"summary":"..."}
        - vaccine_add: vaccino somministrato. {"type":"vaccine_add","childId":"<id figlio>","vaccineType":"esavalente|pneumococco|meningococcoB|mpr|varicella|meningococcoACWY|hpv|influenza|altro","date":"<administeredDate>","title":"nome commerciale","summary":"..."}
        - rename_document: rinomina il documento col titolo corretto. {"type":"rename_document","renameTo":"...","summary":"..."}

        REGOLE:
        - Proponi solo azioni realmente supportate dal contenuto del documento. Non inventare dati.
        - "childId" è l'id della PERSONA (figlio o adulto) fra quelle fornite: scegli quella il cui nome \
          compare sul documento come paziente. Se nessuna combacia chiaramente, ometti il campo (lo sceglierà l'utente).
        - Usa vehicleId SOLO se uno tra quelli forniti combacia chiaramente; altrimenti ometti il campo.
        - Includi quasi sempre "rename_document" con un titolo pulito. Non aggiungere note_add se \
          l'azione principale contiene già il contenuto del documento.
        - Se il documento non contiene nulla di utile, ritorna "actions": [].
        - Gli importi sono numeri (punto decimale), senza simbolo di valuta.
        """
    }

    private static func userPrompt(fileName: String, children: [ChildRef], vehicles: [VehicleRef]) -> String {
        let iso = ISO8601DateFormatter()
        let today = iso.string(from: Date())
        var s = "Data odierna: \(today). Nome file originale: \"\(fileName)\".\n"
        let kids = children.filter { !$0.isAdult }
        let adults = children.filter { $0.isAdult }
        if kids.isEmpty {
            s += "Figli in famiglia: nessuno.\n"
        } else {
            s += "Figli in famiglia (id → nome): " + kids.map { "\($0.id) → \($0.name)" }.joined(separator: "; ") + ".\n"
        }
        if !adults.isEmpty {
            s += "Adulti in famiglia (id → nome): " + adults.map { "\($0.id) → \($0.name)" }.joined(separator: "; ") + ".\n"
        }
        if vehicles.isEmpty {
            s += "Veicoli: nessuno.\n"
        } else {
            s += "Veicoli (id → descrizione): " + vehicles.map { "\($0.id) → \($0.label)" }.joined(separator: "; ") + ".\n"
        }
        s += "Analizza le pagine, classifica il documento e proponi le azioni in JSON."
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
