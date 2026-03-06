//
//  MedicalDocumentTextExtractor.swift
//  KidBox
//
//  Created by vscocca on 06/03/26.
//

import Foundation
import PDFKit
import Vision
import UIKit
import ZIPFoundation

enum MedicalDocumentTextExtractorError: LocalizedError {
    case fileNotFound
    case unsupportedFileType(String)
    case invalidImage
    case pdfLoadFailed
    case extractionProducedEmptyText
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "File non trovato."
        case .unsupportedFileType(let mimeType):
            return "Tipo file non supportato: \(mimeType)"
        case .invalidImage:
            return "Immagine non valida."
        case .pdfLoadFailed:
            return "Impossibile leggere il PDF."
        case .extractionProducedEmptyText:
            return "Nessun testo rilevato nel documento."
        }
    }
}

struct MedicalDocumentExtractionInput: Sendable {
    let documentId: String
    let fileName: String
    let mimeType: String
    let localFileURL: URL
    
    var fileExtension: String {
        localFileURL.pathExtension.lowercased()
    }
    
    var isPDFDocument: Bool {
        mimeType == "application/pdf"
    }
    
    var isImageDocument: Bool {
        mimeType.hasPrefix("image/")
    }
    
    var isPlainTextDocument: Bool {
        mimeType == "text/plain" || mimeType.hasPrefix("text/")
    }
    
    var isDOCXDocument: Bool {
        mimeType == "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        || fileExtension == "docx"
    }
    
    var isDOCDocument: Bool {
        mimeType == "application/msword"
        || fileExtension == "doc"
    }
    
    var isRTFDocument: Bool {
        mimeType == "application/rtf" || fileExtension == "rtf"
    }
}

protocol MedicalDocumentTextExtracting {
    func extractText(from input: MedicalDocumentExtractionInput) async throws -> String
}

final class MedicalDocumentTextExtractor: MedicalDocumentTextExtracting {
    
    func extractText(from input: MedicalDocumentExtractionInput) async throws -> String {
        KBLog.storage.kbInfo("Start extraction docId=\(input.documentId) fileName=\(input.fileName) mime=\(input.mimeType)")
        
        let fileURL = input.localFileURL
        KBLog.storage.kbDebug("Resolved local file url path=\(fileURL.path)")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            KBLog.storage.kbError("Extraction failed: file not found at path=\(fileURL.path)")
            throw MedicalDocumentTextExtractorError.fileNotFound
        }
        
        // TEXT FILE
        if input.isPlainTextDocument {
            KBLog.storage.kbInfo("Processing text document fileName=\(input.fileName)")
            return try extractPlainText(from: fileURL)
        }
        
        // RTF
        if input.isRTFDocument {
            KBLog.storage.kbInfo("Processing RTF document fileName=\(input.fileName)")
            return try extractRTFText(from: fileURL)
        }
        
        // DOCX
        if input.isDOCXDocument {
            KBLog.storage.kbInfo("Processing DOCX document fileName=\(input.fileName)")
            return try extractDOCXText(from: fileURL)
        }
        
        // DOC
        if input.isDOCDocument {
            KBLog.storage.kbError("DOC legacy format not supported fileName=\(input.fileName)")
            throw MedicalDocumentTextExtractorError.unsupportedFileType(input.mimeType)
        }
        
        if input.isPDFDocument {
            KBLog.storage.kbInfo("Processing PDF fileName=\(input.fileName)")
            let text = try await extractTextFromPDF(at: fileURL)
            KBLog.storage.kbInfo("PDF extraction completed fileName=\(input.fileName) chars=\(text.count)")
            return text
        }
        
        if input.isImageDocument {
            KBLog.storage.kbInfo("Processing image fileName=\(input.fileName)")
            let text = try await extractTextFromImage(at: fileURL)
            KBLog.storage.kbInfo("Image extraction completed fileName=\(input.fileName) chars=\(text.count)")
            return text
        }
        
        KBLog.storage.kbError("Unsupported mimeType=\(input.mimeType) for docId=\(input.documentId)")
        throw MedicalDocumentTextExtractorError.unsupportedFileType(input.mimeType)
    }
}

// MARK: - PDF

private extension MedicalDocumentTextExtractor {
    
    func extractTextFromPDF(at url: URL) async throws -> String {
        KBLog.storage.kbDebug("Opening PDF path=\(url.path)")
        
        guard let pdf = PDFDocument(url: url) else {
            KBLog.storage.kbError("PDF load failed path=\(url.path)")
            throw MedicalDocumentTextExtractorError.pdfLoadFailed
        }
        
        KBLog.storage.kbDebug("PDF loaded successfully pageCount=\(pdf.pageCount)")
        
        let nativeText = extractNativePDFText(pdf)
        if !nativeText.isEmpty {
            KBLog.storage.kbInfo("PDF native text extraction succeeded chars=\(nativeText.count)")
            return nativeText
        }
        
        KBLog.storage.kbInfo("PDF has no native text, falling back to OCR page rendering")
        
        let ocrText = try await extractOCRTextFromPDF(pdf)
        guard !ocrText.isEmpty else {
            KBLog.storage.kbError("PDF OCR produced empty text")
            throw MedicalDocumentTextExtractorError.extractionProducedEmptyText
        }
        
        KBLog.storage.kbInfo("PDF OCR extraction succeeded chars=\(ocrText.count)")
        return ocrText
    }
    
    func extractNativePDFText(_ pdf: PDFDocument) -> String {
        var chunks: [String] = []
        
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else {
                KBLog.storage.kbDebug("PDF native text skip missing page index=\(index)")
                continue
            }
            
            let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                KBLog.storage.kbDebug("PDF native text empty page index=\(index)")
                continue
            }
            
            KBLog.storage.kbDebug("PDF native text found page index=\(index) chars=\(text.count)")
            chunks.append(text)
        }
        
        let joined = chunks.joined(separator: "\n\n")
        KBLog.storage.kbDebug("PDF native extraction total chars=\(joined.count)")
        return joined
    }
    
    func extractOCRTextFromPDF(_ pdf: PDFDocument) async throws -> String {
        var chunks: [String] = []
        
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else {
                KBLog.storage.kbDebug("PDF OCR skip missing page index=\(index)")
                continue
            }
            
            guard let image = renderPDFPage(page, pageIndex: index) else {
                KBLog.storage.kbError("PDF OCR render failed page index=\(index)")
                continue
            }
            
            let text = try await recognizeText(in: image, sourceLabel: "pdf_page_\(index)")
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !trimmed.isEmpty {
                KBLog.storage.kbDebug("PDF OCR page index=\(index) chars=\(trimmed.count)")
                chunks.append(trimmed)
            } else {
                KBLog.storage.kbDebug("PDF OCR page index=\(index) produced empty text")
            }
        }
        
        let joined = chunks.joined(separator: "\n\n")
        KBLog.storage.kbDebug("PDF OCR total chars=\(joined.count)")
        return joined
    }
    
    func renderPDFPage(_ page: PDFPage, pageIndex: Int) -> UIImage? {
        let pageRect = page.bounds(for: .mediaBox)
        guard pageRect.width > 0, pageRect.height > 0 else {
            KBLog.storage.kbError("Invalid PDF page bounds index=\(pageIndex) width=\(pageRect.width) height=\(pageRect.height)")
            return nil
        }
        
        let scale: CGFloat = 2.0
        let targetSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        
        KBLog.storage.kbDebug("Rendering PDF page index=\(pageIndex) targetSize=\(Int(targetSize.width))x\(Int(targetSize.height))")
        
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { ctx in
            UIColor.white.set()
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            
            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: 0, y: targetSize.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
            ctx.cgContext.restoreGState()
        }
    }
    
    func extractTextFromImage(at url: URL) async throws -> String {
        KBLog.storage.kbDebug("Loading image data path=\(url.path)")
        
        guard let data = try? Data(contentsOf: url) else {
            KBLog.storage.kbError("Failed reading image data path=\(url.path)")
            throw MedicalDocumentTextExtractorError.invalidImage
        }
        
        KBLog.storage.kbDebug("Loaded image bytes=\(data.count)")
        
        guard let image = UIImage(data: data) else {
            KBLog.storage.kbError("UIImage init failed path=\(url.path)")
            throw MedicalDocumentTextExtractorError.invalidImage
        }
        
        let text = try await recognizeText(in: image, sourceLabel: url.lastPathComponent)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            KBLog.storage.kbError("Image OCR produced empty text fileName=\(url.lastPathComponent)")
            throw MedicalDocumentTextExtractorError.extractionProducedEmptyText
        }
        
        KBLog.storage.kbDebug("Image OCR chars=\(trimmed.count) fileName=\(url.lastPathComponent)")
        return trimmed
    }
    
    func recognizeText(in image: UIImage, sourceLabel: String) async throws -> String {
        guard let cgImage = image.cgImage else {
            KBLog.storage.kbError("OCR failed: cgImage missing source=\(sourceLabel)")
            throw MedicalDocumentTextExtractorError.invalidImage
        }
        
        KBLog.storage.kbDebug("Starting Vision OCR source=\(sourceLabel) size=\(Int(image.size.width))x\(Int(image.size.height))")
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    KBLog.storage.kbError("Vision OCR failed source=\(sourceLabel): \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                KBLog.storage.kbDebug("Vision OCR observations source=\(sourceLabel) count=\(observations.count)")
                
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                
                KBLog.storage.kbDebug("Vision OCR completed source=\(sourceLabel) chars=\(text.count)")
                continuation.resume(returning: text)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["it-IT", "en-US"]
            
            do {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try handler.perform([request])
            } catch {
                KBLog.storage.kbError("Vision handler perform failed source=\(sourceLabel): \(error.localizedDescription)")
                continuation.resume(throwing: error)
            }
        }
    }
    
    func extractPlainText(from url: URL) throws -> String {
        
        KBLog.storage.kbDebug("Reading text file path=\(url.path)")
        
        let data = try Data(contentsOf: url)
        
        let text =
        String(data: data, encoding: .utf8) ??
        String(data: data, encoding: .isoLatin1) ??
        ""
        
        let cleaned = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        guard !cleaned.isEmpty else {
            throw MedicalDocumentTextExtractorError.extractionProducedEmptyText
        }
        
        return cleaned
    }
    
    func extractRTFText(from url: URL) throws -> String {
        
        KBLog.storage.kbDebug("Reading RTF file path=\(url.path)")
        
        let data = try Data(contentsOf: url)
        
        let attributed = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        
        let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !text.isEmpty else {
            throw MedicalDocumentTextExtractorError.extractionProducedEmptyText
        }
        
        return text
    }
    
    func extractDOCXText(from url: URL) throws -> String {
        
        KBLog.storage.kbDebug("Reading DOCX file path=\(url.path)")
        
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            KBLog.storage.kbError("DOCX archive open failed path=\(url.path) error=\(error.localizedDescription)")
            throw MedicalDocumentTextExtractorError.extractionProducedEmptyText
        }
        
        guard let entry = archive["word/document.xml"] else {
            KBLog.storage.kbError("DOCX missing word/document.xml path=\(url.path)")
            throw MedicalDocumentTextExtractorError.extractionProducedEmptyText
        }
        
        var xmlData = Data()
        _ = try archive.extract(entry) { chunk in
            xmlData.append(chunk)
        }
        
        guard let xml = String(data: xmlData, encoding: .utf8), !xml.isEmpty else {
            KBLog.storage.kbError("DOCX XML decode failed path=\(url.path)")
            throw MedicalDocumentTextExtractorError.extractionProducedEmptyText
        }
        
        let text = extractTextFromWordXML(xml)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        guard !text.isEmpty else {
            KBLog.storage.kbError("DOCX extraction produced empty text path=\(url.path)")
            throw MedicalDocumentTextExtractorError.extractionProducedEmptyText
        }
        
        KBLog.storage.kbDebug("DOCX extraction chars=\(text.count)")
        return text
    }
    
    func extractTextFromWordXML(_ xml: String) -> String {
        var output = xml
        
        // line breaks
        output = output.replacingOccurrences(of: "<w:tab/>", with: "\t", options: .regularExpression)
        output = output.replacingOccurrences(of: "<w:br\\s*/>", with: "\n", options: .regularExpression)
        output = output.replacingOccurrences(of: "</w:p>", with: "\n", options: .regularExpression)
        
        // keep only text nodes
        let pattern = "<w:t[^>]*>(.*?)</w:t>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        
        let matches = regex?.matches(in: output, options: [], range: range) ?? []
        let parts = matches.compactMap { match -> String? in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: output) else { return nil }
            return String(output[range])
        }
        
        return parts
            .joined(separator: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
