//
//  FitnessCopilotView.swift
//  KidBox
//
//  "Fitness Copilot": chat libera dentro il modulo, con il piano e lo stato di
//  salute allegati in modo invisibile a ogni domanda.
//
//  Segue la stessa impronta delle altre chat askAI (badge provider, bolle
//  `AIChatBubbleView`, indicatore di scrittura, barra di input con contatore
//  messaggi, toast delle azioni eseguite): per l'utente è lo stesso assistente,
//  cambia solo il contesto.
//
//  La conversazione vive in memoria per la durata della sessione: a differenza
//  delle chat Salute non ha una cronologia sincronizzata, perché il suo valore
//  sta nel contesto del piano corrente, che cambia in continuazione.
//

import SwiftUI
import SwiftData

// MARK: - Messaggio

private struct FitnessCopilotMessage: Identifiable, Equatable {
    let id = UUID().uuidString
    let text: String
    let isUser: Bool
    let date = Date()
}

// MARK: - View

struct FitnessCopilotView: View {

    let familyId: String
    let childId: String
    let subjectName: String
    let plan: FitnessPlanDocument
    let treatments: [KBTreatment]
    let vaccines: [KBVaccine]
    let visits: [KBMedicalVisit]
    let exams: [KBMedicalExam]
    let onPlanUpdated: (FitnessPlanDocument) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var messages: [FitnessCopilotMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var streamingMessageId: String?
    @State private var systemPrompt = ""
    @State private var workingPlan: FitnessPlanDocument
    @State private var usageToday = 0
    @State private var dailyLimit = 0
    @State private var errorMessage: String?
    @State private var actionExecutionSummary: String?
    @FocusState private var isInputFocused: Bool

    private let accent = FitnessPlanTheme.tint

    init(
        familyId: String,
        childId: String,
        subjectName: String,
        plan: FitnessPlanDocument,
        treatments: [KBTreatment],
        vaccines: [KBVaccine],
        visits: [KBMedicalVisit],
        exams: [KBMedicalExam],
        onPlanUpdated: @escaping (FitnessPlanDocument) -> Void
    ) {
        self.familyId = familyId
        self.childId = childId
        self.subjectName = subjectName
        self.plan = plan
        self.treatments = treatments
        self.vaccines = vaccines
        self.visits = visits
        self.exams = exams
        self.onPlanUpdated = onPlanUpdated
        _workingPlan = State(initialValue: plan)
    }

    var body: some View {
        ModalNavContainer {
            VStack(spacing: 0) {
                providerBadge
                Divider()
                messageList
                if messages.isEmpty { suggestionsRow }
                if let errorMessage { errorBanner(errorMessage) }
                Divider()
                inputBar
            }
            .aiActionExecutionToast(
                summary: $actionExecutionSummary,
                tint: accent
            )
            .navigationTitle("Fitness Copilot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if !targetEnvironment(macCatalyst)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
                #endif
            }
            .task {
                buildSystemPrompt()
                await loadUsage()
            }
            .onAppear { AppAnalytics.screenView(name: "salute_piano_fitness_ai") }
        }
    }

    // MARK: - Badge provider

    private var providerBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(accent)
            Text("Assistente AI KidBox — Fitness")
                .font(.caption.bold())
            Text("· Solo informativo, non sostituisce il medico")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.06))
    }

    // MARK: - Lista messaggi

    private var messageList: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty && !isLoading {
                            introBubble
                        }
                        ForEach(messages) { message in
                            AIChatBubbleView(
                                text: message.text,
                                isUser: message.isUser,
                                date: message.date,
                                streamReveal: streamingMessageId == message.id && !message.isUser,
                                onStreamingTick: { scrollToBottom(proxy, animated: false) },
                                onStreamingComplete: {
                                    if streamingMessageId == message.id { streamingMessageId = nil }
                                }
                            )
                            .id(message.id)
                        }
                        if isLoading {
                            AIChatTypingIndicator()
                                .id("typing-indicator")
                                .transition(.opacity)
                        }
                        Color.clear.frame(height: 1).id("scroll-bottom")
                    }
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in scrollToBottom(proxy, animated: false) }
                .onChange(of: isLoading) { _, loading in
                    if loading { scrollToBottom(proxy, animated: true) }
                }

                if !messages.isEmpty {
                    Button {
                        scrollToBottom(proxy, animated: true)
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(accent))
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { isInputFocused = false }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("scroll-bottom", anchor: .bottom) }
        } else {
            proxy.scrollTo("scroll-bottom", anchor: .bottom)
        }
    }

    // MARK: - Bolla introduttiva

    private var introBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "figure.run")
                .foregroundStyle(accent)
                .padding(8)
                .background(accent.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text("Ciao! Sono il tuo personal trainer per il piano di \(subjectName).")
                    .font(.subheadline.bold())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Ho accesso a:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    infoRow(
                        icon: "calendar",
                        text: String(
                            format: NSLocalizedString(
                                "%d sedute del piano e il loro stato",
                                comment: "Fitness copilot intro sessions"
                            ),
                            workingPlan.allSessions.count
                        ),
                        color: accent
                    )
                    if !workingPlan.safetyNotes.isEmpty {
                        infoRow(
                            icon: "cross.case.fill",
                            text: String(
                                format: NSLocalizedString(
                                    "%d adattamenti clinici del piano",
                                    comment: "Fitness copilot intro safety notes"
                                ),
                                workingPlan.safetyNotes.count
                            ),
                            color: Color(red: 0.6, green: 0.45, blue: 0.85)
                        )
                    }
                    infoRow(
                        icon: "heart.text.square.fill",
                        text: NSLocalizedString(
                            "referti, cure e parametri di Salute",
                            comment: "Fitness copilot intro health data"
                        ),
                        color: Color(red: 0.95, green: 0.55, blue: 0.45)
                    )
                }

                Text("Posso spiegarti un esercizio, dirti come adattarlo e modificare il piano quando serve: se oggi non puoi allenarti come previsto, dimmelo e lo riorganizzo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 12)
    }

    private func infoRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2).foregroundStyle(color)
            Text(text).font(.caption).foregroundStyle(.primary)
        }
    }

    // MARK: - Suggerimenti

    private var suggestionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        send(text: suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(accent.opacity(0.12)))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var suggestions: [String] {
        var items = [
            NSLocalizedString("Come si esegue l'esercizio di oggi?", comment: "Fitness copilot suggestion"),
            NSLocalizedString("Oggi piove, non posso correre", comment: "Fitness copilot suggestion"),
            NSLocalizedString("Ho dolore al ginocchio, è normale?", comment: "Fitness copilot suggestion"),
        ]
        if todaySession == nil {
            items[0] = NSLocalizedString(
                "Cosa mi conviene fare oggi?",
                comment: "Fitness copilot suggestion rest day"
            )
        }
        return items
    }

    private var todaySession: FitnessSession? {
        workingPlan.sessions(on: Date()).first
    }

    // MARK: - Barra di input

    private var inputBar: some View {
        VStack(spacing: 4) {
            if dailyLimit > 0 {
                HStack {
                    Spacer()
                    Text("\(usageToday)/\(dailyLimit)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            HStack(spacing: 10) {
                TextField("Fai una domanda…", text: $inputText, axis: .vertical)
                    .focused($isInputFocused)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 20))

                Button {
                    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    inputText = ""
                    send(text: text)
                } label: {
                    Image(systemName: isLoading ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? .secondary : KBTheme.aiFabOrange
                        )
                }
                .disabled(
                    inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
                )
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button { errorMessage = nil } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.1))
    }

    // MARK: - Contesto

    /// Costruisce il prompt di sistema: piano, avanzamento e dati sanitari
    /// viaggiano allegati a ogni domanda senza che l'utente li veda.
    private func buildSystemPrompt() {
        let payload = FitnessPlanGenerator.buildPayload(
            modelContext: modelContext,
            familyId: familyId,
            childId: childId,
            subjectName: subjectName,
            birthDate: nil,
            input: workingPlan.input,
            treatments: treatments,
            vaccines: vaccines,
            visits: visits,
            exams: exams,
            startDate: workingPlan.startDate
        )
        systemPrompt = FitnessCopilotPrompt.systemPrompt(
            subjectName: subjectName,
            plan: workingPlan,
            profileSummary: payload.profileSummary,
            healthContext: payload.healthContext
        )
        KBLog.ai.kbInfo("FitnessCopilot: contesto pronto chars=\(systemPrompt.count)")
    }

    @MainActor
    private func loadUsage() async {
        guard let usage = try? await AIService.shared.fetchUsage() else { return }
        usageToday = usage.usageToday
        dailyLimit = usage.dailyLimit
    }

    // MARK: - Invio

    private func send(text: String) {
        guard !isLoading else { return }
        isInputFocused = false
        messages.append(FitnessCopilotMessage(text: text, isUser: true))
        Task { await performSend() }
    }

    @MainActor
    private func performSend() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if systemPrompt.isEmpty { buildSystemPrompt() }

        // La cronologia viaggia intera: il copilota ragiona su una manciata di
        // scambi, e troncarli renderebbe incoerenti le modifiche al piano.
        let history = messages.map {
            KBAIMessage(role: $0.isUser ? .user : .assistant, content: $0.text)
        }

        do {
            let response = try await AIService.shared.sendMessage(
                messages: history,
                systemPrompt: systemPrompt,
                purpose: "fitnessCopilot"
            )
            AppAnalytics.aiMessageSent(
                agentType: "fitness",
                plan: KBSubscriptionManager.shared.currentPlan.rawValue
            )
            usageToday = response.usageToday
            dailyLimit = response.dailyLimit

            let processed = FitnessCopilotActionExecutor.process(
                response.reply,
                plan: workingPlan
            )
            if let summary = processed.executionSummary {
                workingPlan = processed.plan
                onPlanUpdated(processed.plan)
                buildSystemPrompt()
                actionExecutionSummary = summary
            }
            let reply = FitnessCopilotMessage(text: processed.displayText, isUser: false)
            messages.append(reply)
            streamingMessageId = reply.id
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Prompt del copilota

enum FitnessCopilotPrompt {

    static func systemPrompt(
        subjectName: String,
        plan: FitnessPlanDocument,
        profileSummary: [String],
        healthContext: String
    ) -> String {
        let today = FitnessPlanFormat.mediumDate(Date())
        let language = FitnessPlanPromptBuilder.responseLanguageName()

        var lines: [String] = []
        lines.append("""
        Sei il personal trainer digitale di \(subjectName) dentro l'app KidBox. Rispondi come un
        preparatore competente: concreto, breve, mai generico. LINGUA: \(language).

        Oggi è \(today).

        COSA PUOI FARE:
        Spiegare come si esegue un esercizio del piano, correggere la tecnica, valutare un sintomo in
        termini di allenamento (senza mai fare diagnosi) e adattare il piano quando l'utente non può
        allenarsi come previsto.

        SICUREZZA:
        Rispetta sempre gli adattamenti clinici già stabiliti per questo piano, elencati sotto.
        Se l'utente riferisce dolore acuto, dolore al petto, vertigini, febbre o un sintomo che non è
        normale affaticamento, dì di fermarsi e di sentire un medico: non proporre di continuare.
        Non formuli diagnosi e non modifichi terapie.

        AZIONI SUL PIANO:
        Quando la richiesta implica un cambiamento (es. "oggi piove, non posso correre", "sposta la
        seduta di giovedì", "l'ho già fatta"), NON limitarti a proporlo: applicalo, allegando in fondo
        alla risposta un blocco di azioni fra questi marcatori esatti:

        \(FitnessCopilotActionMarkers.start)
        [{"type": "replace_session", "sessionId": "…", "title": "…", "activityType": "…", "durationMinutes": 40, "intensity": "media", "exercises": [{"name": "…", "detail": "…"}], "targets": ["…"], "targetKcal": 300, "notes": "…"}]
        \(FitnessCopilotActionMarkers.end)

        Tipi ammessi:
        - "replace_session": sostituisce il contenuto di una seduta (es. allenamento indoor al posto
          della corsa) mantenendo il carico e l'obiettivo settimanale;
        - "move_session": sposta una seduta, con "date" in formato AAAA-MM-GG;
        - "mark_session": aggiorna lo stato, con "status" fra "done", "skipped", "planned".
        Usa SEMPRE il "sessionId" esatto preso dall'elenco delle sedute qui sotto.
        Nel testo della risposta spiega in una riga cosa hai cambiato e perché; il blocco JSON non
        viene mostrato all'utente. Se non serve modificare nulla, non allegare alcun blocco.
        """)

        lines.append("")
        lines.append("--- PIANO ATTUALE ---")
        lines.append("Obiettivo: \(plan.input.goal.promptLabel)")
        let sports = plan.input.sortedSports
        if !sports.isEmpty {
            lines.append("Sport praticati: " + sports.map(\.promptLabel).joined(separator: ", "))
        }
        lines.append("Giorni di allenamento: \(FitnessPlanPromptBuilder.weekdayNames(plan.input.sortedWeekdays))")
        lines.append("Inizio del piano: \(FitnessPlanFormat.mediumDate(plan.startDate))")
        if !plan.summary.isEmpty {
            lines.append("Sintesi: \(plan.summary)")
        }

        if !plan.safetyNotes.isEmpty {
            lines.append("")
            lines.append("--- ADATTAMENTI CLINICI DEL PIANO (vincolanti) ---")
            lines.append(contentsOf: plan.safetyNotes.map { "• \($0)" })
        }

        lines.append("")
        lines.append("--- SEDUTE E STATO DI COMPLETAMENTO ---")
        lines.append(contentsOf: FitnessPlanGenerator.sessionLines(
            plan.allSessions,
            startDate: plan.startDate
        ))

        lines.append("")
        lines.append("--- DATI ANTROPOMETRICI E ALLENAMENTI (app Salute) ---")
        lines.append(contentsOf: profileSummary)

        lines.append("")
        lines.append("--- DATI CLINICI (visite, cure, analisi, referti) ---")
        lines.append(healthContext)

        return lines.joined(separator: "\n")
    }
}
