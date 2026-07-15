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
        static let pendingCrashReport = "kb_crash_report_pending"
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

    /// Impostato al crash (handler segnali / test) — fino a upload riuscito non applicare throttle.
    static func markPendingCrashReport() {
        UserDefaults.standard.set(true, forKey: Keys.pendingCrashReport)
    }

    static var hasPendingCrashReport: Bool {
        UserDefaults.standard.bool(forKey: Keys.pendingCrashReport)
    }

    /// Solo per test / toggle report: rimuove il throttle delle 6 ore.
    static func clearAnalysisThrottle() {
        UserDefaults.standard.removeObject(forKey: Keys.lastRun)
    }

    // MARK: - Entry point

    /// - Parameter force: ignora il throttle (es. toggle report appena attivato).
    static func analyzeIfNeeded(force: Bool = false) async {
        guard Auth.auth().currentUser != nil else {
            KBLog.app.kbDebug("CrashAnalyzer: skip (utente non autenticato)")
            return
        }

        let rawLogs = KBFileLogger.shared.readLogs()
        let logBytes = rawLogs.utf8.count
        let crashInLogs = containsCrashMarkers(rawLogs)

        guard logBytes >= minLogBytes else {
            KBLog.app.kbDebug("CrashAnalyzer: skip (log file \(logBytes) B < \(minLogBytes) B)")
            return
        }

        let pending = hasPendingCrashReport
        let shouldUploadCrash = (crashInLogs || pending) && isAutomaticReportingEnabled
        let bypassThrottle = force || shouldUploadCrash

        if !bypassThrottle,
           let lastRun = UserDefaults.standard.object(forKey: Keys.lastRun) as? Date,
           Date().timeIntervalSince(lastRun) < throttleInterval {
            KBLog.app.kbInfo(
                "CrashAnalyzer: skip throttle (ultima=\(lastRun), pending=\(pending), crashInLogs=\(crashInLogs), reporting=\(isAutomaticReportingEnabled))"
            )
            return
        }

        KBLog.app.kbInfo(
            "CrashAnalyzer: avvio analisi (\(logBytes) B, reporting=\(isAutomaticReportingEnabled), crashInLogs=\(crashInLogs), pending=\(pending))"
        )

        if shouldUploadCrash {
            KBLog.app.kbInfo("CrashAnalyzer: crash pending → upload diretto (senza FM)")
            let issues = crashInLogs
                ? buildFallbackIssues(from: rawLogs)
                : [pendingCrashIssue()]
            await uploadToFirestore(issues: issues, rawLogs: rawLogs)
            return
        }

        if #available(iOS 18.1, *) {
            await analyzeWithFoundationModels(rawLogs: rawLogs, allowCrashFallback: false)
        } else {
            KBLog.app.kbWarning("CrashAnalyzer: skip upload (iOS < 18.1, Foundation Models non disponibile)")
            markAnalysisRun()
        }
    }

    // MARK: - Foundation Models

    @available(iOS 18.1, *)
    private static func analyzeWithFoundationModels(rawLogs: String, allowCrashFallback: Bool) async {
        #if canImport(FoundationModels)
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: buildPrompt(rawLogs: rawLogs))
            let parsed = try parseAnalysisResponse(response.content)
            if parsed.hasIssues {
                await requestPermissionAndUpload(issues: parsed.issues, rawLogs: rawLogs)
                return
            }
            if allowCrashFallback && isAutomaticReportingEnabled {
                KBLog.app.kbInfo("CrashAnalyzer: FM senza issues → upload fallback (crash nei log)")
                await uploadToFirestore(issues: buildFallbackIssues(from: rawLogs), rawLogs: rawLogs)
                return
            }
            KBLog.app.kbInfo("CrashAnalyzer: nessun problema rilevato nei log")
            markAnalysisRun()
        } catch {
            if allowCrashFallback && isAutomaticReportingEnabled {
                KBLog.app.kbWarning(
                    "CrashAnalyzer: FM fallita (\(error.localizedDescription)) → upload fallback (crash nei log)"
                )
                await uploadToFirestore(issues: buildFallbackIssues(from: rawLogs), rawLogs: rawLogs)
            } else {
                KBLog.app.kbWarning("CrashAnalyzer: analisi on-device non riuscita: \(error.localizedDescription)")
                markAnalysisRun()
            }
        }
        #else
        markAnalysisRun()
        #endif
    }

    @available(iOS 18.1, *)
    private static func buildPrompt(rawLogs: String) -> String {
        // Only feed WARNING/ERROR/CRASH lines to reduce LLM false positives on INFO entries.
        let filtered = filterSignificantLines(rawLogs)
        let tail = truncateLogs(filtered, maxBytes: 32 * 1024)
        return """
        Sei un analizzatore di log per l'app KidBox.
        Regole IMPORTANTI prima di analizzare:
        - I log hanno formato: [timestamp] [LEVEL] [category] [module] messaggio
        - Solo le righe [ERROR], [CRASH], [FATAL] indicano problemi reali
        - Le righe [INFO], [DEBUG], [WARNING] sono normali anche se menzionano operazioni come "flushGlobal", "startAutoFlush", "sync", ecc.
        - Se una sequenza INFO mostra "requested" → "ops=0" → "completed" è un'esecuzione RIUSCITA, NON un errore
        - Segna hasIssues:true SOLO se ci sono righe [ERROR] o [CRASH] concrete
        Rispondi SOLO con JSON valido, nessun testo aggiuntivo:
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
        Log da analizzare (solo righe significative):
        \(tail)
        """
    }

    private static func filterSignificantLines(_ logs: String) -> String {
        let lines = logs.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let significant = lines.filter { line in
            line.contains("[ERROR]") || line.contains("[CRASH]") ||
            line.contains("[FATAL]") || line.contains("[WARNING]") ||
            line.contains("Fatal error") || line.contains("SIGABRT")
        }
        // If nothing significant, fall back to tail of all logs so FM can still detect anomalies
        if significant.isEmpty { return logs }
        return significant.joined(separator: "\n")
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

        if hasBeenAskedForReporting && !isAutomaticReportingEnabled {
            KBLog.app.kbDebug("CrashAnalyzer: skip upload (report automatici disattivati)")
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
            "platform": KBDeviceInfo.platform,
            "appVersion": version,
            "osVersion": KBDeviceInfo.osVersionDescription,
            "device": KBDeviceInfo.deviceDescription,
            "deviceMachine": KBDeviceInfo.machineIdentifier,
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
            clearPendingCrashReport()
            KBLog.app.kbInfo("Crash report inviato: \(issues.count) issues")
        } catch {
            KBLog.app.kbError("CrashAnalyzer: upload Firestore fallito: \(error.localizedDescription)")
            // Non impostare throttle: al prossimo avvio si riprova.
        }
    }

    // MARK: - Helpers

    private static func containsCrashMarkers(_ logs: String) -> Bool {
        logs.contains("[CRASH]") ||
        logs.contains("Fatal error") ||
        logs.contains("TEST: crash") ||
        logs.contains("SIGABRT")
    }

    private static func pendingCrashIssue() -> IssueReport {
        IssueReport(
            type: "crash",
            severity: "critical",
            category: "ui",
            affectedModule: "unknown",
            summary: "Crash segnalato; log locali già troncati",
            detail: "kb_crash_report_pending era attivo ma i marker non erano più nel file di log",
            firstOccurrence: "",
            occurrences: 1
        )
    }

    private static func clearPendingCrashReport() {
        UserDefaults.standard.removeObject(forKey: Keys.pendingCrashReport)
    }

    private static func buildFallbackIssues(from rawLogs: String) -> [IssueReport] {
        let crashLines = rawLogs
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                line.contains("[CRASH]") ||
                line.contains("Fatal error") ||
                line.contains("TEST: crash")
            }
        let excerpt = crashLines.suffix(5).joined(separator: " | ")
        let module = crashLines.last.flatMap { line -> String? in
            if let open = line.range(of: "["),
               let close = line.range(of: ":", range: open.upperBound..<line.endIndex) {
                return String(line[open.upperBound..<close.lowerBound])
            }
            return nil
        } ?? "unknown"

        return [
            IssueReport(
                type: "crash",
                severity: "critical",
                category: "ui",
                affectedModule: module,
                summary: "Crash rilevato nei log dell'app",
                detail: excerpt.isEmpty ? "Segnale di crash presente nel file di log" : excerpt,
                firstOccurrence: "",
                occurrences: max(1, crashLines.count)
            ),
        ]
    }

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
