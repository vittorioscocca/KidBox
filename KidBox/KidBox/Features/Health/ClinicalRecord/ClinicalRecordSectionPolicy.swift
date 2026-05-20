//
//  ClinicalRecordSectionPolicy.swift
//  KidBox
//

import Foundation

/// Regole sezioni cartella clinica (template nativo + AI).
enum ClinicalRecordSectionPolicy {

    /// Non generare mai come sezione standalone (dati incorporati altrove).
    static let standaloneExcludedIds: Set<String> = [
        ClinicalRecordTopicBuilder.TopicId.bloodPressure.rawValue,
        "pressione_arteriosa",
    ]

    /// Aree cliniche generate dinamicamente da TrendAnalyzer.
    static let dynamicSpecialtyTopics: [ClinicalRecordTopicBuilder.TopicId] = [
        .cardiology,
        .gastroenterology,
        .urology,
        .metabolism,
    ]

    static func shouldGenerateStandaloneSection(id: String) -> Bool {
        !standaloneExcludedIds.contains(id)
    }
}
