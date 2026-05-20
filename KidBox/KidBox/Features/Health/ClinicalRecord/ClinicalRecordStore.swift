//
//  ClinicalRecordStore.swift
//  KidBox
//

import Foundation

/// Percorso locale della cartella clinica PDF per bambino/profilo.
enum ClinicalRecordStore {

    private static let folderName = "clinical_records"

    static func pdfURL(childId: String) -> URL {
        directory().appendingPathComponent("cartella_clinica_\(childId).pdf")
    }

    static func exists(childId: String) -> Bool {
        FileManager.default.fileExists(atPath: pdfURL(childId: childId).path)
    }

    static func generatedAt(childId: String) -> Date? {
        let url = pdfURL(childId: childId)
        guard exists(childId: childId),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date
        else { return nil }
        return date
    }

    static func delete(childId: String) {
        let url = pdfURL(childId: childId)
        try? FileManager.default.removeItem(at: url)
        UserDefaults.standard.removeObject(forKey: reportCacheKey(childId))
    }

    private static let reportCachePrefix = "kidbox.clinical.report."

    static func saveReport(_ report: ClinicalRecordReport, childId: String) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        UserDefaults.standard.set(data, forKey: reportCacheKey(childId))
    }

    static func loadReport(childId: String) -> ClinicalRecordReport? {
        guard let data = UserDefaults.standard.data(forKey: reportCacheKey(childId)) else { return nil }
        return try? JSONDecoder().decode(ClinicalRecordReport.self, from: data)
    }

    private static func reportCacheKey(_ childId: String) -> String {
        reportCachePrefix + childId
    }

    private static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KidBox/\(folderName)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
}
