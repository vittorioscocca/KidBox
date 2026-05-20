//
//  CrashAnalyzer.swift
//  KidBox
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import UIKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Analisi on-device dei log tramite Apple Intelligence (iOS 18.1+) e upload opzionale su Firestore.
enum CrashAnalyzer {

    // MARK: - Models

    struct IssueReport: Codable, Sendable {
        let type: String
        let severity: String
        let category: String
        let affectedModule: String
        let summary: String
        let detail: String
        let firstOccurrence: String
        let occurrences: Int
    }

    private struct AnalysisResponse: Codable {
        let hasIssues: Bool
        let issues: [IssueReport]
    }

    private enum Keys {
        static let lastRun = "kb_crash_analysis_last_run"
        static let reportingEnabled = "kb_log_reporting_enabled"
        static let reportingAsked = "kb_log_reporting_asked"
    }

    private static let minLogBytes = 2 * 1024
    private static let maxUploadLogBytes = 50 * 1024
    private static let throttleInterval: TimeInterval = 6 * 60 * 60

    // MARK: - Public preferences

    static var isAutomaticReportingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.reportingEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.reportingEnabled) }
    }

    static var hasBeenAskedForReporting: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.reportingAsked) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.reportingAsked) }
    }

    // MARK: - Entry point

    static func analyzeIfNeeded() async {
        guard Auth.auth().currentUser != nil else { return }

        let rawLogs = KBFileLogger.shared.readLogs()
        let logBytes = rawLogs.utf8.count
        guard logBytes >= minLogBytes else { return }

        if let lastRun = UserDefaults.standard.object(forKey: Keys.lastRun) as? Date,
           Date().timeIntervalSince(lastRun) < throttleInterval {
            return
        }

        if #available(iOS 18.1, *) {
            await analyzeWithFoundationModels(rawLogs: rawLogs)
        } else {
            markAnalysisRun()
        }
    }

    // MARK: - Foundation Models

    @available(iOS 18.1, *)
    private static func analyzeWithFoundationModels(rawLogs: String) async {
        #if canImport(FoundationModels)
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: buildPrompt(rawLogs: rawLogs))
            let parsed = try parseAnalysisResponse(response.content)
            if !parsed.hasIssues {
                markAnalysisRun()
                return
            }
            await requestPermissionAndUpload(issues: parsed.issues, rawLogs: rawLogs)
        } catch {
            KBLog.app.kbWarning("CrashAnalyzer: analisi on-device non riuscita: \(error.localizedDescription)")
            markAnalysisRun()
        }
        #else
        markAnalysisRun()
        #endif
    }

    @available(iOS 18.1, *)
    private static func buildPrompt(rawLogs: String) -> String {
        """
        Sei un analizzatore di log per l'app KidBox. Analizza i log e \
        rispondi SOLO con JSON valido, nessun testo aggiuntivo:
        {
          "hasIssues": true/false,
          "issues": [
            {
              "type": "crash|error|malfunction|warning",
              "severity": "critical|high|medium|low",
              "category": "sync|auth|data|ui|ai|storage|navigation",
              "affectedModule": "nome file o funzione",
              "summary": "descrizione breve max 120 caratteri in italiano",
              "detail": "causa tecnica probabile",
              "firstOccurrence": "timestamp prima occorrenza",
              "occurrences": numero
            }
          ]
        }
        Log da analizzare:
        \(rawLogs)
        """
    }

    private static func parseAnalysisResponse(_ text: String) throws -> AnalysisResponse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            throw NSError(domain: "CrashAnalyzer", code: 1, userInfo: [NSLocalizedDescriptionKey: "JSON non trovato"])
        }
        let json = String(trimmed[start...end])
        let data = Data(json.utf8)
        return try JSONDecoder().decode(AnalysisResponse.self, from: data)
    }

    // MARK: - Permission flow

    @MainActor
    private static func requestPermissionAndUpload(issues: [IssueReport], rawLogs: String) async {
        if isAutomaticReportingEnabled {
            await uploadToFirestore(issues: issues, rawLogs: rawLogs)
            return
        }

        if hasBeenAskedForReporting {
            markAnalysisRun()
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            CrashReportPromptCenter.shared.present(
                issueCount: issues.count,
                onSend: {
                    isAutomaticReportingEnabled = true
                    hasBeenAskedForReporting = true
                    CrashReportPromptCenter.shared.dismiss()
                    Task {
                        await uploadToFirestore(issues: issues, rawLogs: rawLogs)
                        continuation.resume()
                    }
                },
                onDecline: {
                    isAutomaticReportingEnabled = false
                    hasBeenAskedForReporting = true
                    CrashReportPromptCenter.shared.dismiss()
                    markAnalysisRun()
                    continuation.resume()
                }
            )
        }
    }

    // MARK: - Firestore upload

    private static func uploadToFirestore(issues: [IssueReport], rawLogs: String) async {
        let truncatedLogs = truncateLogs(rawLogs, maxBytes: maxUploadLogBytes)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        var payload: [String: Any] = [
            "platform": "ios",
            "appVersion": version,
            "osVersion": UIDevice.current.systemVersion,
            "device": UIDevice.current.model,
            "issues": issues.map { issue in
                [
                    "type": issue.type,
                    "severity": issue.severity,
                    "category": issue.category,
                    "affectedModule": issue.affectedModule,
                    "summary": issue.summary,
                    "detail": issue.detail,
                    "firstOccurrence": issue.firstOccurrence,
                    "occurrences": issue.occurrences,
                ] as [String: Any]
            },
            "rawLogs": truncatedLogs,
            "createdAt": FieldValue.serverTimestamp(),
            "status": "new",
            "userId": Auth.auth().currentUser?.uid ?? "anonymous",
        ]

        do {
            try await Firestore.firestore().collection("crash_reports").addDocument(data: payload)
            KBFileLogger.shared.clearLogs()
            markAnalysisRun()
            KBLog.app.kbInfo("Crash report inviato: \(issues.count) issues")
        } catch {
            KBLog.app.kbError("CrashAnalyzer: upload Firestore fallito: \(error.localizedDescription)")
            markAnalysisRun()
        }
    }

    // MARK: - Helpers

    private static func markAnalysisRun() {
        UserDefaults.standard.set(Date(), forKey: Keys.lastRun)
    }

    private static func truncateLogs(_ raw: String, maxBytes: Int) -> String {
        guard raw.utf8.count > maxBytes else { return raw }
        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while !lines.isEmpty {
            let candidate = lines.joined(separator: "\n")
            if candidate.utf8.count <= maxBytes { return candidate }
            lines.removeFirst()
        }
        return String(raw.prefix(maxBytes))
    }
}
