//
//  ClinicalRecordPDFService.swift
//  KidBox
//

import UIKit

enum ClinicalRecordPDFService {

    private static let pageSize = CGSize(width: 595, height: 842)
    private static let margin: CGFloat = 48
    private static let lineSpacing: CGFloat = 4

    static func renderPDF(lines: [String]) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            var y = margin
            var pageStarted = false

            func beginPageIfNeeded() {
                if !pageStarted {
                    context.beginPage()
                    pageStarted = true
                    y = margin
                }
            }

            func newPage() {
                context.beginPage()
                y = margin
            }

            for rawLine in lines {
                let line = rawLine.trimmingCharacters(in: .newlines)
                let isSection = line.hasPrefix("---") || line.hasPrefix("CARTELLA")
                    || line.hasPrefix("VISITA ")
                let font: UIFont = {
                    if line == "CARTELLA CLINICA" {
                        return .boldSystemFont(ofSize: 22)
                    }
                    if isSection {
                        return .boldSystemFont(ofSize: 14)
                    }
                    return .systemFont(ofSize: 11)
                }()

                let attrs: [NSAttributedString.Key: Any] = [.font: font]
                let maxWidth = pageSize.width - margin * 2
                let wrapped = wrap(line.isEmpty ? " " : line, font: font, maxWidth: maxWidth)

                for segment in wrapped {
                    let height = segment.height(withConstrainedWidth: maxWidth, font: font) + lineSpacing
                    if y + height > pageSize.height - margin {
                        newPage()
                    }
                    beginPageIfNeeded()
                    segment.draw(
                        in: CGRect(x: margin, y: y, width: maxWidth, height: height),
                        withAttributes: attrs
                    )
                    y += height
                }
            }
            if !pageStarted {
                context.beginPage()
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]
                "Nessun dato disponibile.".draw(
                    in: CGRect(x: margin, y: margin, width: pageSize.width - margin * 2, height: 24),
                    withAttributes: attrs
                )
            }
        }
    }

    private static func wrap(_ text: String, font: UIFont, maxWidth: CGFloat) -> [NSString] {
        guard !text.isEmpty else { return ["" as NSString] }
        var result: [NSString] = []
        var current = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            let candidate = current.isEmpty ? String(word) : "\(current) \(word)"
            let size = (candidate as NSString).size(withAttributes: [.font: font])
            if size.width <= maxWidth {
                current = candidate
            } else {
                if !current.isEmpty { result.append(current as NSString) }
                current = String(word)
            }
        }
        if !current.isEmpty { result.append(current as NSString) }
        if result.isEmpty { result.append(text as NSString) }
        return result
    }
}

private extension NSString {
    func height(withConstrainedWidth width: CGFloat, font: UIFont) -> CGFloat {
        let rect = boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(rect.height)
    }
}
