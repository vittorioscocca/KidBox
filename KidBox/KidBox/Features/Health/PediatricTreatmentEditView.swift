//
//  PediatricTreatmentEditView.swift
//  KidBox
//
//  Restyled: dynamic light/dark theme matching LoginView.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import UserNotifications
import UniformTypeIdentifiers

struct PediatricTreatmentEditView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let familyId: String
    let childId: String
    let childName: String
    let treatmentId: String?
    @State private var reminderEnabled = false
    
    // Step 1 - Farmaco
    @State private var drugName         = ""
    @State private var activeIngredient = ""
    
    // Step 2 - Dose e frequenza
    @State private var dosageValue    = 0.0
    @State private var dosageUnit     = "ml"
    @State private var isLongTerm     = false
    @State private var durationDays   = 5
    @State private var dailyFrequency = 1
    @State private var notifGranted   = false
    @State private var pendingAttachmentURLs: [URL] = []
    
    // Step 3 - Orari e data inizio
    @State private var startDate = Date()
    @State private var times: [String] = ["08:00"]
    
    // Step 4 - Conferma e note
    @State private var notes = ""
    
    @State private var currentStep = 0
    private let totalSteps = 4
    
    @State private var showAttachmentDialog   = false
    @State private var showAttachmentImporter = false
    @State private var showAttachmentGallery  = false
    @State private var showAttachmentCamera   = false
    
    private let tint        = KBTheme.tint
    private let units       = ["ml", "mg", "gocce", "compresse", "bustine"]
    private let freqOptions = [(1, "1 volta al giorno",   "mattina"),
                               (2, "2 volte al giorno",   "mattina, sera"),
                               (3, "3 volte al giorno",   "mattina, pranzo, sera"),
                               (4, "4 volte al giorno",   "mattina, pranzo, sera, notte")]
    
    private var defaultTimes: [String] {
        switch dailyFrequency {
        case 1:  return ["08:00"]
        case 2:  return ["08:00", "20:00"]
        case 3:  return ["08:00", "14:00", "20:00"]
        case 4:  return ["08:00", "13:00", "18:00", "23:00"]
        default: return ["08:00"]
        }
    }
    
    private var endDate: Date {
        Calendar.current.date(byAdding: .day, value: durationDays - 1, to: startDate) ?? startDate
    }
    
    private var totalDoses: Int { dailyFrequency * durationDays }
    private var isEditing: Bool { treatmentId != nil }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar
                    .background(KBTheme.background(colorScheme))
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch currentStep {
                        case 0:  step0_drug
                        case 1:  step1_dose
                        case 2:  step2_schedule
                        default: step3_confirm
                        }
                    }
                    .padding()
                }
                .background(KBTheme.background(colorScheme))
                
                bottomBar
                    .background(KBTheme.background(colorScheme))
            }
            .background(KBTheme.background(colorScheme).ignoresSafeArea())
            .navigationTitle(isEditing ? "Modifica Cura" : "Nuova Cura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annulla") { dismiss() } }
            }
            .onAppear {
                loadIfEditing()
                Task {
                    let s = await UNUserNotificationCenter.current().notificationSettings()
                    notifGranted = s.authorizationStatus == .authorized
                }
            }
            .sheet(isPresented: $showAttachmentDialog) {
                AttachmentSourcePickerSheet(
                    onCamera:   { showAttachmentDialog = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showAttachmentCamera   = true } },
                    onGallery:  { showAttachmentDialog = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showAttachmentGallery  = true } },
                    onDocument: { showAttachmentDialog = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showAttachmentImporter = true } }
                )
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
            }
            .fileImporter(isPresented: $showAttachmentImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if let urls = try? result.get() { pendingAttachmentURLs.append(contentsOf: urls) }
            }
            .sheet(isPresented: $showAttachmentGallery) {
                ImagePickerView(sourceType: .photoLibrary) { image in
                    if let url = saveImageToTemp(image) { pendingAttachmentURLs.append(url) }
                }
            }
            .sheet(isPresented: $showAttachmentCamera) {
                ImagePickerView(sourceType: .camera) { image in
                    if let url = saveImageToTemp(image) { pendingAttachmentURLs.append(url) }
                }
            }
        }
    }
    
    // MARK: - Progress bar
    
    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= currentStep ? tint : KBTheme.inputBackground(colorScheme))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
    
    // MARK: - Step 0 — Farmaco
    
    private var step0_drug: some View {
        DrugSelectorStep(drugName: $drugName, activeIngredient: $activeIngredient)
    }
    
    // MARK: - Step 1 — Dose e frequenza
    
    private var step1_dose: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Configura dose")
                .font(.title3.bold())
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            
            // Farmaco header
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.red.opacity(0.1)).frame(width: 44, height: 44)
                    Image(systemName: "thermometer.medium").foregroundStyle(.red)
                }
                VStack(alignment: .leading) {
                    Text(drugName.isEmpty ? "Farmaco" : drugName).font(.subheadline.bold())
                    if !activeIngredient.isEmpty {
                        Text(activeIngredient).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.red.opacity(0.10) : Color.red.opacity(0.05))
            )
            
            // Dosaggio
            styledGroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Dosaggio", systemImage: "drop.fill")
                        .font(.subheadline.bold()).foregroundStyle(.blue)
                    HStack(spacing: 8) {
                        TextField("0", value: $dosageValue, format: .number)
                            .keyboardType(.decimalPad)
                            .frame(width: 80)
                            .padding(10)
                            .background(KBTheme.inputBackground(colorScheme))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Picker("Unità", selection: $dosageUnit) {
                            ForEach(units, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            
            // Durata
            styledGroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Durata", systemImage: "calendar")
                        .font(.subheadline.bold()).foregroundStyle(.orange)
                    Toggle("Cura a lungo termine", isOn: $isLongTerm)
                    if !isLongTerm {
                        HStack {
                            Button { if durationDays > 1 { durationDays -= 1 } } label: {
                                Image(systemName: "minus.circle.fill").font(.title2).foregroundStyle(tint)
                            }
                            Text("\(durationDays)")
                                .font(.title2.bold()).foregroundStyle(tint).frame(width: 40)
                            Button { durationDays += 1 } label: {
                                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(tint)
                            }
                            Text("giorni").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            // Frequenza
            styledGroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Frequenza", systemImage: "clock")
                        .font(.subheadline.bold()).foregroundStyle(tint)
                    ForEach(freqOptions, id: \.0) { (freq, label, sub) in
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(dailyFrequency == freq ? tint : KBTheme.inputBackground(colorScheme))
                                    .frame(width: 30, height: 30)
                                Text("\(freq)x")
                                    .font(.caption.bold())
                                    .foregroundStyle(dailyFrequency == freq ? .white : .secondary)
                            }
                            VStack(alignment: .leading) {
                                Text(label).font(.subheadline)
                                Text(sub).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if dailyFrequency == freq {
                                Image(systemName: "checkmark").foregroundStyle(tint)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dailyFrequency = freq
                            times = defaultTimes
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
    
    // MARK: - Step 2 — Orari
    
    private var step2_schedule: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Configura orari")
                .font(.title3.bold())
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            
            styledGroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    DatePicker("Data inizio", selection: $startDate, displayedComponents: .date)
                    Divider()
                    Text("Orari somministrazione").font(.subheadline.bold())
                    Text("Imposta gli orari per \(dailyFrequency) dos\(dailyFrequency == 1 ? "e" : "i") giornalier\(dailyFrequency == 1 ? "a" : "e")")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(times.indices, id: \.self) { i in
                        let label = ["Mattina", "Pranzo", "Sera", "Notte"][safe: i] ?? "Dose \(i+1)"
                        HStack {
                            Text(label)
                            Spacer()
                            TimePickerField(timeString: $times[i])
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            styledGroupBox(title: "Riepilogo") {
                VStack(spacing: 6) {
                    summaryRow(label: "Durata",      value: isLongTerm ? "A lungo termine" : "\(durationDays) giorni")
                    summaryRow(label: "Data inizio", value: startDate.formatted(.dateTime.day().month(.abbreviated).year()))
                    if !isLongTerm {
                        summaryRow(label: "Data fine",   value: endDate.formatted(.dateTime.day().month(.abbreviated).year()))
                        summaryRow(label: "Dosi totali", value: "\(totalDoses)")
                    }
                }
            }
        }
    }
    
    // MARK: - Step 3 — Conferma
    
    private var step3_confirm: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Conferma cura")
                .font(.title3.bold())
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            
            styledGroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(tint.opacity(0.12)).frame(width: 44, height: 44)
                            Image(systemName: "pills.fill").foregroundStyle(tint)
                        }
                        VStack(alignment: .leading) {
                            Text(drugName.isEmpty ? "Farmaco" : drugName).font(.subheadline.bold())
                            if !activeIngredient.isEmpty {
                                Text(activeIngredient).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Divider()
                    summaryRow(label: "Dosaggio",  value: "\(dosageValue, default: "%.0f") \(dosageUnit)")
                    if !isLongTerm { summaryRow(label: "Durata", value: "\(durationDays) giorni") }
                    summaryRow(label: "Frequenza", value: "\(dailyFrequency) volt\(dailyFrequency == 1 ? "a" : "e") al giorno")
                    Divider()
                    Text("Orari somministrazione:").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(zip(["Mattina","Pranzo","Sera","Notte"], times)), id: \.0) { label, time in
                        HStack {
                            Text(label)
                            Spacer()
                            Text(time).foregroundStyle(tint).bold()
                        }
                        .font(.subheadline)
                    }
                    if !isLongTerm {
                        Divider()
                        summaryRow(label: "Prima dose", value: "\(startDate.formatted(.dateTime.day().month(.abbreviated).year())), \(times.first ?? "")")
                        summaryRow(label: "Ultima dose", value: "\(endDate.formatted(.dateTime.day().month(.abbreviated).year())), \(times.last ?? "")")
                        summaryRow(label: "Dosi totali", value: "\(totalDoses)")
                    }
                }
            }
            
            // Promemoria
            styledGroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Promemoria", systemImage: "bell.fill")
                        .font(.subheadline.bold()).foregroundStyle(tint)
                    
                    if !notifGranted {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notifiche disabilitate").font(.caption.bold())
                                Text("Abilita le notifiche nelle Impostazioni per ricevere i promemoria.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.08)))
                        Button("Apri Impostazioni") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.caption).foregroundStyle(tint)
                    } else {
                        Toggle(isOn: $reminderEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Attiva promemoria")
                                Text("Riceverai una notifica per ogni dose")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(tint)
                        
                        if reminderEnabled {
                            Divider()
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notifiche schedulate per:").font(.caption).foregroundStyle(.secondary)
                                ForEach(times, id: \.self) { t in
                                    HStack(spacing: 6) {
                                        Image(systemName: "bell.fill").font(.caption2).foregroundStyle(tint)
                                        Text(t).font(.caption.bold())
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            GroupBox("Note") {
                TextField("Note aggiuntive (opzionale)", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
            
            TreatmentAttachmentPicker(
                pendingURLs: $pendingAttachmentURLs,
                onAddTapped: { showAttachmentDialog = true }
            )
        }
    }
    
    // MARK: - Bottom bar
    
    private var bottomBar: some View {
        HStack(spacing: 12) {
            if currentStep > 0 {
                Button { currentStep -= 1 } label: {
                    Label("Indietro", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity).padding()
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(KBTheme.separator(colorScheme))
                        )
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                }
                .buttonStyle(.plain)
            }
            
            if currentStep < totalSteps - 1 {
                Button { currentStep += 1 } label: {
                    HStack { Text("Avanti"); Image(systemName: "chevron.right") }
                        .frame(maxWidth: .infinity).padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(canAdvance ? tint : KBTheme.inputBackground(colorScheme)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!canAdvance)
            } else {
                Button { save() } label: {
                    Label("Inizio", systemImage: "checkmark")
                        .frame(maxWidth: .infinity).padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(tint))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
    
    private var canAdvance: Bool {
        switch currentStep {
        case 0: return !drugName.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }
    
    // MARK: - Reusable styled GroupBox
    
    @ViewBuilder
    private func styledGroupBox<Content: View>(title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            content()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(KBTheme.cardBackground(colorScheme))
                .shadow(color: KBTheme.shadow(colorScheme), radius: 5, x: 0, y: 2)
        )
    }
    
    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold()
        }
        .font(.subheadline)
    }
    
    // MARK: - Helpers
    
    private func saveImageToTemp(_ image: UIImage) -> URL? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try? data.write(to: url)
        return url
    }
    
    // MARK: - Load & Save
    
    private func loadIfEditing() {
        guard let tid = treatmentId else { return }
        let desc = FetchDescriptor<KBTreatment>(predicate: #Predicate { $0.id == tid })
        guard let t = try? modelContext.fetch(desc).first else { return }
        drugName         = t.drugName
        activeIngredient = t.activeIngredient ?? ""
        dosageValue      = t.dosageValue
        dosageUnit       = t.dosageUnit
        isLongTerm       = t.isLongTerm
        durationDays     = t.durationDays
        dailyFrequency   = t.dailyFrequency
        startDate        = t.startDate
        times            = t.scheduleTimes.isEmpty ? defaultTimes : t.scheduleTimes
        notes            = t.notes ?? ""
        currentStep      = 0
    }
    
    @MainActor
    private func save() {
        let uid = Auth.auth().currentUser?.uid ?? "local"
        let now = Date()
        let ed  = isLongTerm ? nil : endDate
        
        let treatment: KBTreatment
        
        if let tid = treatmentId {
            let desc = FetchDescriptor<KBTreatment>(predicate: #Predicate { $0.id == tid })
            guard let t = try? modelContext.fetch(desc).first else { return }
            applyFields(to: t, uid: uid, now: now, endDate: ed)
            treatment = t
        } else {
            let t = KBTreatment(
                familyId: familyId, childId: childId,
                drugName: drugName,
                activeIngredient: activeIngredient.isEmpty ? nil : activeIngredient,
                dosageValue: dosageValue, dosageUnit: dosageUnit,
                isLongTerm: isLongTerm, durationDays: durationDays,
                startDate: startDate, endDate: ed,
                dailyFrequency: dailyFrequency, scheduleTimes: times,
                isActive: true, notes: notes.isEmpty ? nil : notes,
                reminderEnabled: false,
                createdAt: now, updatedAt: now, updatedBy: uid, createdBy: uid
            )
            modelContext.insert(t)
            treatment = t
        }
        
        do {
            try modelContext.save()
            SyncCenter.shared.enqueueTreatmentUpsert(treatmentId: treatment.id, familyId: familyId, modelContext: modelContext)
            SyncCenter.shared.flushGlobal(modelContext: modelContext)
        } catch { return }
        
        treatment.reminderEnabled = reminderEnabled
        try? modelContext.save()
        
        if reminderEnabled {
            Task {
                let granted = await TreatmentNotificationManager.requestAuthorization()
                if granted { TreatmentNotificationManager.schedule(treatment: treatment, childName: childName) }
            }
        } else {
            TreatmentNotificationManager.cancel(treatmentId: treatment.id)
        }
        
        if !pendingAttachmentURLs.isEmpty {
            KBEventBus.shared.emit(.treatmentAttachmentPending(
                urls: pendingAttachmentURLs,
                treatmentId: treatment.id,
                familyId: familyId,
                childId: childId
            ))
        }
        dismiss()
    }
    
    private func applyFields(to t: KBTreatment, uid: String, now: Date, endDate: Date?) {
        t.drugName         = drugName
        t.activeIngredient = activeIngredient.isEmpty ? nil : activeIngredient
        t.dosageValue      = dosageValue
        t.dosageUnit       = dosageUnit
        t.isLongTerm       = isLongTerm
        t.durationDays     = durationDays
        t.startDate        = startDate
        t.endDate          = endDate
        t.dailyFrequency   = dailyFrequency
        t.scheduleTimes    = times
        t.notes            = notes.isEmpty ? nil : notes
        t.updatedBy        = uid
        t.updatedAt        = now
    }
}

// MARK: - TimePickerField

struct TimePickerField: View {
    @Binding var timeString: String
    
    private var date: Binding<Date> {
        Binding(
            get: {
                let comps = timeString.split(separator: ":").compactMap { Int($0) }
                var dc = DateComponents()
                dc.hour   = comps[safe: 0] ?? 8
                dc.minute = comps[safe: 1] ?? 0
                return Calendar.current.date(from: dc) ?? Date()
            },
            set: { d in
                let h = Calendar.current.component(.hour, from: d)
                let m = Calendar.current.component(.minute, from: d)
                timeString = String(format: "%02d:%02d", h, m)
            }
        )
    }
    
    var body: some View {
        DatePicker("", selection: date, displayedComponents: .hourAndMinute)
            .labelsHidden()
    }
}

// MARK: - Safe subscript

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
