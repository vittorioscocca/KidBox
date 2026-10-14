//
//  FitnessShoesView.swift
//  KidBox
//
//  Impostazioni delle sessioni del Piano Fitness: oggi contengono le scarpe da
//  corsa (marca, data d'acquisto, km massimi, foto) e i km che restano a
//  ciascuna paio. Si raggiungono dall'ingranaggio dell'elenco Sessioni.
//

import SwiftUI
import PhotosUI

// MARK: - Impostazioni

struct FitnessSessionsSettingsView: View {

    let childId: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var shoes: [FitnessShoe] = []
    @State private var editing: FitnessShoe?
    @State private var isNew = false
    @State private var shoeToDelete: FitnessShoe?

    private let tint = FitnessPlanTheme.tint

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Scarpe da corsa")
                    .font(.title3.bold())
                    .foregroundStyle(KBTheme.primaryText(colorScheme))

                Text("I km delle corse registrate dopo la data d'acquisto si scalano dai km massimi della scarpa più recente in uso.")
                    .font(.footnote)
                    .foregroundStyle(KBTheme.secondaryText(colorScheme))

                if shoes.isEmpty {
                    emptyState
                } else {
                    ForEach(shoes) { shoe in
                        ZStack(alignment: .topTrailing) {
                            Button {
                                isNew = false
                                editing = shoe
                            } label: {
                                shoeCard(shoe)
                            }
                            .buttonStyle(.plain)

                            quickMenu(shoe)
                        }
                    }
                }

                Button {
                    isNew = true
                    editing = FitnessShoe(childId: childId, brand: "", purchaseDate: Date(), maxKm: 0)
                } label: {
                    Label("Aggiungi scarpe", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(KBTheme.background(colorScheme).ignoresSafeArea())
        .navigationTitle("Impostazioni")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            shoes = FitnessShoeStore.load(childId: childId)
            shoes = await FitnessShoeStore.pull(childId: childId)
        }
        .alert("Eliminare le scarpe?", isPresented: Binding(
            get: { shoeToDelete != nil },
            set: { if !$0 { shoeToDelete = nil } }
        )) {
            Button("Elimina", role: .destructive) {
                if let shoe = shoeToDelete {
                    FitnessShoeStore.delete(shoe)
                    shoes = FitnessShoeStore.load(childId: childId)
                }
                shoeToDelete = nil
            }
            Button("Annulla", role: .cancel) { shoeToDelete = nil }
        } message: {
            Text("I km registrati su queste scarpe andranno persi.")
        }
        .sheet(item: $editing) { shoe in
            FitnessShoeEditView(shoe: shoe, isNew: isNew) {
                shoes = FitnessShoeStore.load(childId: childId)
            }
        }
    }

    /// Azioni rapide sulla scheda, senza aprirla: ritirare o eliminare.
    private func quickMenu(_ shoe: FitnessShoe) -> some View {
        Menu {
            Button {
                var updated = shoe
                updated.retiredAt = shoe.isRetired ? nil : Date()
                FitnessShoeStore.upsert(updated)
                shoes = FitnessShoeStore.load(childId: childId)
            } label: {
                if shoe.isRetired {
                    Label("Riattiva scarpa", systemImage: "arrow.uturn.backward")
                } else {
                    Label("Ritira scarpa", systemImage: "archivebox")
                }
            }
            Button(role: .destructive) {
                shoeToDelete = shoe
            } label: {
                Label("Elimina", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Altre azioni")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "shoe.2")
                .font(.largeTitle)
                .foregroundStyle(tint)
            Text("Nessuna scarpa registrata")
                .font(.headline)
                .foregroundStyle(KBTheme.primaryText(colorScheme))
            Text("Aggiungi un paio per sapere quanti km gli restano.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func shoeCard(_ shoe: FitnessShoe) -> some View {
        let barColor: Color = shoe.isWornOut ? .red : (shoe.progress >= 0.85 ? .orange : tint)

        return HStack(alignment: .top, spacing: 12) {
            FitnessShoeThumbnail(data: shoe.photo, size: 64)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(shoe.displayName)
                        .font(.headline)
                        .foregroundStyle(KBTheme.primaryText(colorScheme))
                        .lineLimit(1)
                    if shoe.isRetired {
                        Text("Ritirata")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(KBTheme.secondaryText(colorScheme).opacity(0.15)))
                            .foregroundStyle(KBTheme.secondaryText(colorScheme))
                    }
                }
                Text(
                    String(
                        format: NSLocalizedString("Acquistata il %@", comment: "Shoe purchase date"),
                        shoe.purchaseDate.formatted(date: .abbreviated, time: .omitted)
                    )
                )
                .font(.footnote)
                .foregroundStyle(KBTheme.secondaryText(colorScheme))

                ProgressView(value: shoe.progress)
                    .tint(barColor)

                HStack {
                    Text(
                        String(
                            format: NSLocalizedString("%@ percorsi", comment: "Shoe km used"),
                            FitnessShoeFormat.km(shoe.usedKm)
                        )
                    )
                    Spacer(minLength: 8)
                    if shoe.isWornOut {
                        Text("Da sostituire")
                            .foregroundStyle(.red)
                    } else {
                        Text(
                            String(
                                format: NSLocalizedString("%@ rimasti", comment: "Shoe km remaining"),
                                FitnessShoeFormat.km(shoe.remainingKm)
                            )
                        )
                        .foregroundStyle(barColor)
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(KBTheme.secondaryText(colorScheme))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(KBTheme.secondaryText(colorScheme).opacity(0.08))
        )
        .opacity(shoe.isRetired ? 0.7 : 1)
        .contentShape(Rectangle())
    }
}

// MARK: - Formato

enum FitnessShoeFormat {
    /// «312,4 km», anche sotto i 10 m (a differenza di `FitnessDistanceFormatter`,
    /// qui lo zero è un dato vero).
    static func km(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        let text = formatter.string(from: NSNumber(value: value)) ?? "-"
        return String(format: NSLocalizedString("%@ km", comment: "Distance in kilometers"), text)
    }
}

// MARK: - Miniatura

struct FitnessShoeThumbnail: View {
    let data: Data?
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    FitnessPlanTheme.tint.opacity(0.15)
                    Image(systemName: "shoe.2")
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(FitnessPlanTheme.tint)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Modifica

struct FitnessShoeEditView: View {

    let shoe: FitnessShoe
    let isNew: Bool
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var brand = ""
    @State private var model = ""
    @State private var purchaseDate = Date()
    @State private var maxKmText = ""
    @State private var photo: Data?
    @State private var retired = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var confirmDelete = false

    private var maxKm: Double? {
        let normalized = maxKmText.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        !brand.trimmingCharacters(in: .whitespaces).isEmpty && maxKm != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        Menu {
                            Button {
                                showCamera = true
                            } label: {
                                Label("Scatta una foto", systemImage: "camera")
                            }
                            Button {
                                showLibrary = true
                            } label: {
                                Label("Scegli dalla libreria", systemImage: "photo.on.rectangle")
                            }
                            if photo != nil {
                                Button(role: .destructive) {
                                    photo = nil
                                } label: {
                                    Label("Rimuovi foto", systemImage: "trash")
                                }
                            }
                        } label: {
                            VStack(spacing: 8) {
                                FitnessShoeThumbnail(data: photo, size: 110)
                                Group {
                                    if photo == nil {
                                        Text("Aggiungi foto")
                                    } else {
                                        Text("Cambia foto")
                                    }
                                }
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(FitnessPlanTheme.tint)
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Marca", text: $brand)
                        .textInputAutocapitalization(.words)
                    TextField("Modello (facoltativo)", text: $model)
                        .textInputAutocapitalization(.words)
                    DatePicker("Data di acquisto", selection: $purchaseDate, in: ...Date(), displayedComponents: .date)
                    HStack {
                        Text("Km massimi")
                        Spacer()
                        TextField("es. 700", text: $maxKmText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 110)
                        Text(verbatim: "km").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Le scarpe da corsa durano di solito tra 500 e 800 km.")
                }

                if !isNew {
                    Section {
                        Toggle("Ritirata", isOn: $retired)
                    } footer: {
                        Text("Una scarpa ritirata non riceve più corse: quelle nuove vanno alla scarpa più recente in uso.")
                    }

                    Section {
                        Button("Elimina scarpa", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(LocalizedStringKey(isNew ? "Nuove scarpe" : "Scarpe"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }.disabled(!canSave)
                }
            }
            .photosPicker(isPresented: $showLibrary, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        photo = FitnessShoePhoto.compressed(data)
                    }
                    pickerItem = nil
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCaptureView(mediaTypes: ["public.image"]) { result in
                    showCamera = false
                    if case .photo(let data) = result { photo = FitnessShoePhoto.compressed(data) }
                }
                .ignoresSafeArea()
            }
            .alert("Eliminare le scarpe?", isPresented: $confirmDelete) {
                Button("Elimina", role: .destructive) {
                    FitnessShoeStore.delete(shoe)
                    onSaved()
                    dismiss()
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("I km registrati su queste scarpe andranno persi.")
            }
        }
        .onAppear {
            brand = shoe.brand
            model = shoe.model
            purchaseDate = shoe.purchaseDate
            photo = shoe.photo
            retired = shoe.isRetired
            if shoe.maxKm > 0 {
                maxKmText = shoe.maxKm.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(shoe.maxKm))
                    : String(shoe.maxKm)
            }
        }
    }

    private func save() {
        guard let maxKm else { return }
        var updated = shoe
        updated.brand = brand.trimmingCharacters(in: .whitespaces)
        updated.model = model.trimmingCharacters(in: .whitespaces)
        updated.purchaseDate = Calendar.current.startOfDay(for: purchaseDate)
        updated.maxKm = maxKm
        updated.photo = photo
        if retired != shoe.isRetired { updated.retiredAt = retired ? Date() : nil }
        FitnessShoeStore.upsert(updated)
        onSaved()
        dismiss()
    }
}

// MARK: - Foto

enum FitnessShoePhoto {
    /// Lato lungo 480 px, JPEG 75%: sta nel documento Firestore (qualche decina di KB).
    static func compressed(_ data: Data, maxSide: CGFloat = 480) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.75)
    }
}
