//
//  ClinicalRecordStructuredPDF.swift
//  KidBox
//

import UIKit

enum ClinicalRecordStructuredPDF {

    private static let pageSize = CGSize(width: 595, height: 842)
    private static let margin: CGFloat = 44
    private static let footerH: CGFloat = 28

    private static let sectionTitleColor = UIColor(red: 0x1c / 255, green: 0x3a / 255, blue: 0x5e / 255, alpha: 1)
    private static let bodyColor = UIColor(red: 0x2d / 255, green: 0x2d / 255, blue: 0x2d / 255, alpha: 1)
    private static let dividerColor = UIColor(red: 0xe0 / 255, green: 0xe0 / 255, blue: 0xe0 / 255, alpha: 1)
    private static let summaryFill = UIColor(red: 0xf0 / 255, green: 0xf7 / 255, blue: 0xff / 255, alpha: 1)

    private static let sectionTitleFont = UIFont.boldSystemFont(ofSize: 14)
    private static let bodyFont = UIFont.systemFont(ofSize: 11)
    private static let bodyLineSpacing: CGFloat = 6.6 // ~1.6 × 11pt

    static func render(report: ClinicalRecordReport) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { ctx in
            var y = margin
            var page = 0
            var drewFirstSection = false

            func startPage() {
                ctx.beginPage()
                page += 1
                y = margin
                drawHeader(report.subjectName, page: page, in: ctx.cgContext)
                y += 36
            }

            func ensureSpace(_ h: CGFloat) {
                if y + h > pageSize.height - margin - footerH {
                    drawFooter(page, in: ctx.cgContext)
                    startPage()
                }
            }

            func drawSectionDivider() {
                ensureSpace(14)
                y += 8
                let path = UIBezierPath()
                path.move(to: CGPoint(x: margin, y: y))
                path.addLine(to: CGPoint(x: pageSize.width - margin, y: y))
                dividerColor.setStroke()
                path.lineWidth = 0.5
                path.stroke()
                y += 12
            }

            func drawSummaryBox(_ paragraph: String) {
                let pad: CGFloat = 12
                let textW = pageSize.width - margin * 2 - pad * 2
                let textH = measuredHeight(paragraph, font: bodyFont, width: textW, lineSpacing: bodyLineSpacing)
                let boxH = textH + pad * 2
                ensureSpace(boxH + 8)
                let boxRect = CGRect(x: margin, y: y, width: pageSize.width - margin * 2, height: boxH)
                let boxPath = UIBezierPath(roundedRect: boxRect, cornerRadius: 8)
                summaryFill.setFill()
                boxPath.fill()
                dividerColor.setStroke()
                boxPath.lineWidth = 0.5
                boxPath.stroke()
                y += drawWrapped(
                    paragraph,
                    font: bodyFont,
                    color: bodyColor,
                    y: y + pad,
                    x: margin + pad,
                    maxWidth: textW,
                    lineSpacing: bodyLineSpacing
                ) + pad
            }

            startPage()

            y += drawLine("CARTELLA CLINICA", font: .boldSystemFont(ofSize: 22), y: y, color: sectionTitleColor)
            y += 8
            for line in report.headerLines.prefix(6) where !line.hasPrefix("CARTELLA CLINICA") {
                y += drawWrapped(line, font: bodyFont, color: bodyColor, y: y, x: margin, maxWidth: pageSize.width - margin * 2, lineSpacing: bodyLineSpacing)
            }

            var paragraphBuffer: [String] = []
            var currentSectionIsSummary = false

            func flushParagraph() {
                guard !paragraphBuffer.isEmpty else { return }
                let text = paragraphBuffer.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                paragraphBuffer = []
                guard !text.isEmpty else { return }
                if currentSectionIsSummary {
                    drawSummaryBox(text)
                } else {
                    ensureSpace(40)
                    y += drawWrapped(
                        text, font: bodyFont, color: bodyColor, y: y,
                        x: margin, maxWidth: pageSize.width - margin * 2, lineSpacing: bodyLineSpacing
                    )
                }
            }

            for line in report.fullDocumentLines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                if trimmed == "---" {
                    flushParagraph()
                    if drewFirstSection { drawSectionDivider() }
                    continue
                }
                if isSectionHeader(trimmed) {
                    flushParagraph()
                    if drewFirstSection { drawSectionDivider() }
                    drewFirstSection = true
                    ensureSpace(28)
                    y += 20
                    y += drawLine(trimmed, font: sectionTitleFont, y: y, color: sectionTitleColor)
                    y += 6
                    currentSectionIsSummary = isSummarySection(trimmed)
                    continue
                }
                paragraphBuffer.append(trimmed)
            }
            flushParagraph()

            drawFooter(page, in: ctx.cgContext)
        }
    }

    private static func isSectionHeader(_ line: String) -> Bool {
        if line.hasPrefix("CARTELLA CLINICA") { return false }
        if line.hasPrefix("•") || line.hasPrefix("-") { return false }
        if line.first?.isNumber == true { return false }
        if line.contains(":") && line != line.uppercased() { return false }
        return line == line.uppercased() && line.count > 6
    }

    private static func isSummarySection(_ title: String) -> Bool {
        let t = title.lowercased()
        return t.contains("riepilogo") || t.contains("valutazione generale")
    }

    private static func drawHeader(_ name: String, page: Int, in context: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.gray,
        ]
        ("\(name) — Cartella clinica" as NSString).draw(
            in: CGRect(x: margin, y: 18, width: pageSize.width - margin * 2, height: 14),
            withAttributes: attrs
        )
    }

    private static func drawFooter(_ page: Int, in context: CGContext) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8),
            .foregroundColor: UIColor.gray,
        ]
        let disclaimer = "Generato da KidBox — Non sostituisce il parere medico"
        (disclaimer as NSString).draw(
            in: CGRect(x: margin, y: pageSize.height - 22, width: pageSize.width - margin * 2 - 40, height: 12),
            withAttributes: attrs
        )
        ("pag. \(page)" as NSString).draw(
            in: CGRect(x: pageSize.width - margin - 40, y: pageSize.height - 22, width: 40, height: 12),
            withAttributes: attrs
        )
    }

    @discardableResult
    private static func drawLine(
        _ text: String,
        font: UIFont,
        y: CGFloat,
        color: UIColor = bodyColor
    ) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let h = (text as NSString).size(withAttributes: attrs).height + 4
        (text as NSString).draw(
            in: CGRect(x: margin, y: y, width: pageSize.width - margin * 2, height: h + 20),
            withAttributes: attrs
        )
        return h
    }

    @discardableResult
    private static func drawWrapped(
        _ text: String,
        font: UIFont,
        color: UIColor,
        y: CGFloat,
        x: CGFloat,
        maxWidth: CGFloat,
        lineSpacing: CGFloat
    ) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let box = CGRect(x: x, y: y, width: maxWidth, height: pageSize.height)
        let rect = attributed.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
        attributed.draw(in: CGRect(x: x, y: y, width: maxWidth, height: ceil(rect.height)))
        return ceil(rect.height) + 8
    }

    private static func measuredHeight(_ text: String, font: UIFont, width: CGFloat, lineSpacing: CGFloat) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style]
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: attrs,
            context: nil
        )
        return ceil(rect.height)
    }
}
