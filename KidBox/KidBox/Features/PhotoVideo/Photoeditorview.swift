//
//  PhotoEditorView.swift
//  KidBox
//
//  ╔══════════════════════════════════════════════════════════════════╗
//  ║  ARCHITETTURA MEMORIA                                            ║
//  ╠══════════════════════════════════════════════════════════════════╣
//  ║  Parametro: imagePath: String (path disco) invece di UIImage.    ║
//  ║  UIImage (~27MB bitmap non compresso).                          ║
//  ║                                                                  ║
//  ║  previewImage  ~4MB  — ridimensionata a 1170px, solo per UI     ║
//  ║  renderedCI    ~4MB  — filtri CI applicati a previewImage       ║
//  ║  flattenToJPEG ~27MB — bitmap originale allocato SOLO qui,      ║
//  ║                        rilasciato subito dopo jpegData()        ║
//  ║                                                                  ║
//  ║  Picco RAM nell'editor: ~8MB (vs ~54MB versione precedente)     ║
//  ╚══════════════════════════════════════════════════════════════════╝

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftData

// MARK: - Editor Tab

private enum EditorTab: String, CaseIterable {
    case crop    = "Crop"
    case adjust  = "Regola"
    case filters = "Filtri"
    case text    = "Testo"
    case sticker = "Sticker"
    
    var icon: String {
        switch self {
        case .crop:    return "crop"
        case .adjust:  return "slider.horizontal.3"
        case .filters: return "camera.filters"
        case .text:    return "textformat"
        case .sticker: return "face.smiling"
        }
    }
}

// MARK: - Overlay item

struct EditorOverlayItem: Identifiable {
    let id       = UUID()
    var text:     String
    var isEmoji:  Bool
    var position: CGSize  = .zero
    var scale:    CGFloat = 1.0
    var rotation: Angle   = .zero
    var color:    Color   = .white
    var fontSize: CGFloat = 36
}

// MARK: - Filter preset

struct PhotoFilterPreset: Identifiable, Equatable {
    let id:     String
    let name:   String
    let filter: ((CIImage) -> CIImage)?
    
    static func == (lhs: PhotoFilterPreset, rhs: PhotoFilterPreset) -> Bool { lhs.id == rhs.id }
    
    static let all: [PhotoFilterPreset] = [
        .init(id: "original", name: "Originale", filter: nil),
        .init(id: "vivid",    name: "Vivid",     filter: { img in
            let f = CIFilter.vibrance(); f.inputImage = img; f.amount = 0.6
            return f.outputImage ?? img
        }),
        .init(id: "fade",     name: "Fade",      filter: { img in
            let f = CIFilter.colorControls(); f.inputImage = img
            f.saturation = 0.6; f.brightness = 0.05; f.contrast = 0.85
            return f.outputImage ?? img
        }),
        .init(id: "noir",     name: "Noir",      filter: { img in
            let f = CIFilter.photoEffectNoir(); f.inputImage = img
            return f.outputImage ?? img
        }),
        .init(id: "chrome",   name: "Chrome",    filter: { img in
            let f = CIFilter.photoEffectChrome(); f.inputImage = img
            return f.outputImage ?? img
        }),
        .init(id: "tonal",    name: "Tonal",     filter: { img in
            let f = CIFilter.photoEffectTonal(); f.inputImage = img
            return f.outputImage ?? img
        }),
        .init(id: "transfer", name: "Transfer",  filter: { img in
            let f = CIFilter.photoEffectTransfer(); f.inputImage = img
            return f.outputImage ?? img
        }),
    ]
}

// MARK: - Main View

struct PhotoEditorView: View {
    
    let photo:     KBFamilyPhoto
    /// Path assoluto del JPEG originale su disco.
    /// Tenere il path invece di Data o UIImage nello @State minimizza la RAM:
    ///   - Data (34MB) non viene mai tenuta in @State/let costante
    ///   - UIImage (bitmap ~27MB) viene allocata solo in flattenToJPEG()
    ///   - previewImage (~4MB) è l'unico bitmap persistente nell'editor
    let imagePath: String
    let familyId:  String
    let userId:    String
    var onSaved:   (KBFamilyPhoto) -> Void
    
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var previewImage: UIImage? = nil  // ~4MB, solo per la UI
    
    // Adjustments
    @State private var brightness: Float  = 0
    @State private var contrast:   Float  = 1
    @State private var saturation: Float  = 1
    @State private var warmth:     Float  = 0
    
    @State private var selectedFilter = PhotoFilterPreset.all[0]
    
    // Crop / Rotate
    @State private var cropRotation: Double  = 0
    @State private var cropOffset:   CGSize  = .zero
    @State private var cropScale:    CGFloat = 1.0
    @State private var dragOffset:   CGSize  = .zero
    @State private var pinchScale:   CGFloat = 1.0
    
    // Overlays
    @State private var overlayItems:   [EditorOverlayItem] = []
    @State private var selectedItemId: UUID?               = nil
    
    // Text
    @State private var showTextInput = false
    @State private var newText       = ""
    @State private var newTextColor  = Color.white
    @State private var newFontSize:  CGFloat = 36
    
    // UI
    @State private var activeTab:   EditorTab = .adjust
    @State private var renderedCI:  UIImage?
    @State private var isSaving     = false
    @State private var saveError:   String?
    @State private var previewSize: CGSize = .zero
    @State private var renderTask:  Task<Void, Never>? = nil
    
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    private let stickers = ["❤️","😍","🎉","⭐️","🌈","🐣","🦋","🌸","🥳","🎂",
                            "🏖️","⛄️","🐶","🐱","🦁","🐸","🦊","🐼","🦄","🌻"]
    
    private var hasChanges: Bool {
        brightness != 0 || contrast != 1 || saturation != 1 || warmth != 0
        || selectedFilter.id != "original"
        || cropRotation != 0 || cropOffset != .zero || cropScale != 1.0
        || !overlayItems.isEmpty
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    previewArea
                    tabBar.padding(.top, 10)
                    controlArea
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.18), value: activeTab)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert("Errore salvataggio", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) { Button("OK") {} } message: { Text(saveError ?? "") }
                .sheet(isPresented: $showTextInput) { textInputSheet }
                .task {
                    let path = imagePath
                    await Task.detached(priority: .userInitiated) {
                        // Legge dal disco e decodifica direttamente alla dimensione preview.
                        // CGImageSourceCreateWithURL non carica il JPEG intero in RAM.
                        guard let src = CGImageSourceCreateWithURL(
                            URL(fileURLWithPath: path) as CFURL, nil
                        ) else { return }
                        let props   = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
                        let origW   = (props?[kCGImagePropertyPixelWidth]  as? CGFloat) ?? 0
                        let origH   = (props?[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0
                        let origMax = max(origW, origH)
                        let maxPx: CGFloat = 1170
                        let target  = origMax > 0 ? min(maxPx, origMax) : maxPx
                        let opts: [CFString: Any] = [
                            kCGImageSourceThumbnailMaxPixelSize:          target,
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform:   true
                        ]
                        guard let cgImg = CGImageSourceCreateThumbnailAtIndex(
                            src, 0, opts as CFDictionary
                        ) else { return }
                        let img = UIImage(cgImage: cgImg)
                        await MainActor.run { self.previewImage = img }
                    }.value
                }
        }
    }
    
    // MARK: - makePreviewImage (static, background-safe)
    
    static func makePreviewImage(from data: Data, maxPx: CGFloat = 1170) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let props   = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let origW   = (props?[kCGImagePropertyPixelWidth]  as? CGFloat) ?? 0
        let origH   = (props?[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0
        let origMax = max(origW, origH)
        let target  = origMax > 0 ? min(maxPx, origMax) : maxPx
        let opts: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize:          target,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform:   true
        ]
        guard let cgImg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImg)
    }
    
    // MARK: - Preview
    
    private var previewArea: some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: renderedCI ?? previewImage ?? UIImage())
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(cropScale * pinchScale)
                    .offset(x: cropOffset.width + dragOffset.width,
                            y: cropOffset.height + dragOffset.height)
                    .rotationEffect(.degrees(cropRotation))
                    .clipped()
                
                ForEach($overlayItems) { $item in
                    OverlayItemView(item: $item, isSelected: selectedItemId == item.id)
                        .onTapGesture { selectedItemId = item.id }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { if activeTab != .crop { selectedItemId = nil } }
            .gesture(activeTab == .crop ? cropGesture : nil)
            .onAppear { previewSize = geo.size }
        }
        .frame(maxWidth: .infinity)
        .frame(height: UIScreen.main.bounds.height * 0.46)
    }
    
    private var cropGesture: some Gesture {
        SimultaneousGesture(
            DragGesture()
                .onChanged { v in dragOffset = v.translation }
                .onEnded { v in
                    cropOffset = CGSize(width:  cropOffset.width  + v.translation.width,
                                        height: cropOffset.height + v.translation.height)
                    dragOffset = .zero
                },
            MagnificationGesture()
                .onChanged { v in pinchScale = v }
                .onEnded { v in
                    cropScale  = max(0.5, min(4.0, cropScale * v))
                    pinchScale = 1.0
                }
        )
    }
    
    // MARK: - Tab bar
    
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(EditorTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.snappy(duration: 0.18)) { activeTab = tab }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon).font(.system(size: 16))
                            Text(tab.rawValue).font(.system(size: 9, weight: .medium))
                        }
                        .frame(width: 62, height: 46)
                        .foregroundStyle(activeTab == tab ? .white : .gray)
                        .background(
                            activeTab == tab ? Color.white.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
        }
    }
    
    // MARK: - Controls
    
    @ViewBuilder
    private var controlArea: some View {
        switch activeTab {
        case .crop:    cropControls
        case .adjust:  adjustControls
        case .filters: filtersStrip
        case .text:    textControls
        case .sticker: stickerControls
        }
    }
    
    private var cropControls: some View {
        VStack(spacing: 14) {
            Text("Pizzica per zoomare · Trascina per riposizionare")
                .font(.caption).foregroundStyle(.gray)
            HStack(spacing: 0) {
                cropBtn(icon: "rotate.left",  label: "-90°") {
                    withAnimation(.snappy) { cropRotation -= 90 }
                }
                cropBtn(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                        label: "Specchia") {
                    withAnimation(.snappy) {
                        cropScale = cropScale > 0 ? -abs(cropScale) : abs(cropScale)
                    }
                }
                cropBtn(icon: "rotate.right", label: "+90°") {
                    withAnimation(.snappy) { cropRotation += 90 }
                }
                cropBtn(icon: "arrow.uturn.backward", label: "Reset") {
                    withAnimation(.snappy) {
                        cropRotation = 0; cropOffset = .zero; cropScale = 1.0
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 18)
    }
    
    private func cropBtn(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 22))
                Text(label).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
        }
    }
    
    private var adjustControls: some View {
        VStack(spacing: 13) {
            AdjustSlider(label: "Luminosità", icon: "sun.max",
                         value: $brightness, range: -0.5...0.5, neutral: 0)
            AdjustSlider(label: "Contrasto",  icon: "circle.lefthalf.filled",
                         value: $contrast,   range:  0.5...2.0, neutral: 1)
            AdjustSlider(label: "Saturazione",icon: "drop",
                         value: $saturation, range:  0.0...2.0, neutral: 1)
            AdjustSlider(label: "Calore",     icon: "thermometer.medium",
                         value: $warmth,     range: -1.0...1.0, neutral: 0)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .onChange(of: brightness)  { _, _ in scheduleRenderCI() }
        .onChange(of: contrast)    { _, _ in scheduleRenderCI() }
        .onChange(of: saturation)  { _, _ in scheduleRenderCI() }
        .onChange(of: warmth)      { _, _ in scheduleRenderCI() }
    }
    
    private var filtersStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(PhotoFilterPreset.all) { preset in
                    FilterThumb(preset: preset, imagePath: imagePath,
                                isSelected: selectedFilter == preset)
                    .onTapGesture {
                        withAnimation(.snappy(duration: 0.18)) { selectedFilter = preset }
                        scheduleRenderCI()
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
        }
    }
    
    private var textControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    newText = ""; newTextColor = .white; newFontSize = 36
                    showTextInput = true
                } label: {
                    Label("Aggiungi testo", systemImage: "plus")
                        .font(.subheadline.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.white.opacity(0.15), in: Capsule())
                }
                if selectedItemId != nil {
                    Button(role: .destructive) {
                        overlayItems.removeAll { $0.id == selectedItemId }
                        selectedItemId = nil
                    } label: {
                        Label("Elimina", systemImage: "trash")
                            .font(.subheadline).foregroundStyle(.red)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color.red.opacity(0.12), in: Capsule())
                    }
                }
            }
            Text(overlayItems.filter { !$0.isEmoji }.isEmpty
                 ? "Tap 'Aggiungi testo' e trascina sulla foto"
                 : "Trascina il testo · Pizzica per ridimensionare")
            .font(.caption).foregroundStyle(.gray)
        }
        .padding(.vertical, 16)
    }
    
    private var textInputSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("Scrivi qualcosa…", text: $newText)
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.secondary.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dimensione").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $newFontSize, in: 18...80).padding(.horizontal)
                }
                .padding(.horizontal)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Colore").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach([Color.white, .black, .red, .orange,
                                     .yellow, .green, .blue, .purple, .pink], id: \.self) { c in
                                         Circle().fill(c).frame(width: 32, height: 32)
                                             .overlay(Circle().strokeBorder(
                                                newTextColor == c ? Color.accentColor : Color.clear,
                                                lineWidth: 3))
                                             .onTapGesture { newTextColor = c }
                                     }
                        }.padding(.horizontal)
                    }
                }
                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("Aggiungi testo").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { showTextInput = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aggiungi") {
                        let t = newText.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        overlayItems.append(EditorOverlayItem(
                            text: t, isEmoji: false, color: newTextColor, fontSize: newFontSize
                        ))
                        showTextInput = false
                    }
                    .disabled(newText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private var stickerControls: some View {
        VStack(spacing: 8) {
            HStack {
                Text(overlayItems.filter { $0.isEmoji }.isEmpty
                     ? "Tap su uno sticker per aggiungerlo"
                     : "Trascina · Pizzica · Ruota con due dita")
                .font(.caption).foregroundStyle(.gray)
                Spacer()
                if selectedItemId != nil {
                    Button(role: .destructive) {
                        overlayItems.removeAll { $0.id == selectedItemId }
                        selectedItemId = nil
                    } label: { Image(systemName: "trash").foregroundStyle(.red) }
                }
            }
            .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(stickers, id: \.self) { emoji in
                        Button {
                            overlayItems.append(EditorOverlayItem(text: emoji, isEmoji: true, fontSize: 48))
                        } label: {
                            Text(emoji).font(.system(size: 34))
                                .frame(width: 52, height: 52)
                                .background(Color.white.opacity(0.1),
                                            in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
            }
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Annulla") { dismiss() }.foregroundStyle(.white)
        }
        ToolbarItem(placement: .principal) {
            if hasChanges {
                Button("Ripristina") {
                    withAnimation(.snappy) {
                        brightness = 0; contrast = 1; saturation = 1; warmth = 0
                        selectedFilter = PhotoFilterPreset.all[0]
                        cropRotation = 0; cropOffset = .zero; cropScale = 1.0
                        overlayItems = []; selectedItemId = nil
                        renderedCI = nil
                        renderTask?.cancel(); renderTask = nil
                    }
                }
                .font(.caption.bold()).foregroundStyle(.orange)
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            if isSaving {
                ProgressView().tint(.white)
            } else {
                Button("Salva copia") { Task { await saveNewPhoto() } }
                    .bold()
                    .foregroundStyle(hasChanges ? .white : .gray)
                    .disabled(!hasChanges)
            }
        }
    }
    
    // MARK: - CI render (debounced, su previewImage ~4MB)
    
    private func scheduleRenderCI() {
        renderTask?.cancel()
        renderTask = Task {
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled else { return }
            renderCI()
        }
    }
    
    private func renderCI() {
        guard let src = previewImage, let cgImg = src.cgImage else { return }
        var ci = CIImage(cgImage: cgImg)
        let controls = CIFilter.colorControls()
        controls.inputImage = ci
        controls.brightness = brightness; controls.contrast = contrast; controls.saturation = saturation
        if let out = controls.outputImage { ci = out }
        if warmth != 0 {
            let temp = CIFilter.temperatureAndTint()
            temp.inputImage    = ci
            temp.neutral       = CIVector(x: 6500, y: 0)
            temp.targetNeutral = CIVector(x: CGFloat(6500 - warmth * 3000), y: 0)
            if let out = temp.outputImage { ci = out }
        }
        if let fn = selectedFilter.filter { ci = fn(ci) }
        guard let out = ciContext.createCGImage(ci, from: ci.extent) else { return }
        renderedCI = UIImage(cgImage: out)
    }
    
    // MARK: - Helpers
    
    /// Ridisegna l'immagine con orientation=.up e scale=1.
    /// Con scale=1, size==pixel reali → flattenToJPEG() calcola le dimensioni correttamente.
    private func normalizeToUp(_ src: UIImage) -> UIImage {
        guard let cgImg = src.cgImage else { return src }
        let pw = CGFloat(cgImg.width); let ph = CGFloat(cgImg.height)
        let swapped = [UIImage.Orientation.left, .right, .leftMirrored, .rightMirrored]
            .contains(src.imageOrientation)
        let w = swapped ? ph : pw; let h = swapped ? pw : ph
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
            src.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        }
    }
    
    /// Applica i filtri CI correnti a piena risoluzione (per il salvataggio).
    private func applyFiltersCI(to src: UIImage) -> UIImage? {
        guard let cgImg = src.cgImage else { return nil }
        var ci = CIImage(cgImage: cgImg)
        let controls = CIFilter.colorControls()
        controls.inputImage = ci
        controls.brightness = brightness; controls.contrast = contrast; controls.saturation = saturation
        if let out = controls.outputImage { ci = out }
        if warmth != 0 {
            let temp = CIFilter.temperatureAndTint()
            temp.inputImage    = ci
            temp.neutral       = CIVector(x: 6500, y: 0)
            temp.targetNeutral = CIVector(x: CGFloat(6500 - warmth * 3000), y: 0)
            if let out = temp.outputImage { ci = out }
        }
        if let fn = selectedFilter.filter { ci = fn(ci) }
        guard let out = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: out)
    }
    
    // MARK: - flattenToJPEG (singolo pass, background-safe)
    
    private func flattenToJPEG(quality: CGFloat = 0.88) -> Data? {
        // Alloca il bitmap originale solo qui, lo rilascia dopo jpegData().
        // Legge i bytes dal disco solo in questo momento — mai prima.
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: imagePath)),
              let raw  = UIImage(data: data) else { return nil }
        let base     = normalizeToUp(raw)   // orientation=.up, scale=1
        let origSize = base.size
        guard origSize.width > 0, origSize.height > 0 else { return nil }
        
        // Applica filtri CI a piena risoluzione se necessario
        let finalBase: UIImage
        if brightness != 0 || contrast != 1 || saturation != 1 || warmth != 0
            || selectedFilter.id != "original" {
            finalBase = applyFiltersCI(to: base) ?? base
        } else {
            finalBase = base
        }
        
        // ── Strategia di compositing ────────────────────────────────────────────
        //
        // Il canvas di output è sempre origSize (risoluzione originale della foto).
        // cropScale NON viene mai usato come moltiplicatore del canvas — altrimenti
        // cropScale=4 su una foto 5724px produce un canvas da 22896px = ~2.8GB.
        //
        // Semantica corretta:
        //   cropScale > 1  →  l'utente ha zoomato nella preview = vuole vedere
        //                     una porzione più piccola della foto → noi disegniamo
        //                     la foto più grande del canvas (crop implicito).
        //   cropOffset      →  sposta il punto di vista nel canvas.
        //   cropRotation    →  ruota la foto nel canvas.
        //   mirror (scale<0)→  specchia orizzontalmente.
        //
        // In questo modo il canvas è sempre origSize indipendentemente da zoom/pan,
        // e la RAM usata dal renderer è ~28MB invece di ~2.8GB.
        
        let rad      = cropRotation * .pi / 180
        let cosA     = abs(cos(rad)); let sinA = abs(sin(rad))
        let absScale = abs(cropScale)
        let mirrorX  = cropScale < 0
        
        // Canvas = origSize ruotata (senza scala): dimensione dell'output finale.
        let canvasSize = CGSize(
            width:  origSize.width * cosA + origSize.height * sinA,
            height: origSize.width * sinA + origSize.height * cosA
        )
        guard canvasSize.width > 0, canvasSize.height > 0,
              canvasSize.width.isFinite, canvasSize.height.isFinite else { return nil }
        
        // Fattore di conversione offset/scala: dalla coordinata preview (punti)
        // alla coordinata canvas (pixel originali).
        let px = max(previewSize.width, 1); let py = max(previewSize.height, 1)
        let fitScale      = min(px / origSize.width, py / origSize.height)
        let imgW          = origSize.width  * fitScale
        let imgH          = origSize.height * fitScale
        let offX          = (px - imgW) / 2
        let offY          = (py - imgH) / 2
        // pixelPerPoint: quanti pixel originali corrispondo a 1 punto della preview
        let pixelPerPoint = fitScale > 0 ? 1.0 / fitScale : 1.0
        // offset in pixel originali (cropOffset è in punti preview)
        let offsetPx = CGSize(width:  cropOffset.width  * pixelPerPoint,
                              height: cropOffset.height * pixelPerPoint)
        // scaleToCanvas per gli overlay: 1 punto preview → N pixel canvas
        let scaleToCanvas = canvasSize.width / max(imgW, 1)
        
        // fmt.scale=1: bitmap esattamente canvasSize.width×height pixel (no @3x)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: fmt)
        let composed = renderer.image { rendCtx in
            let ctx = rendCtx.cgContext
            ctx.saveGState()
            // Sposta al centro del canvas + offset utente (in pixel originali)
            ctx.translateBy(x: canvasSize.width  / 2 + offsetPx.width,
                            y: canvasSize.height / 2 + offsetPx.height)
            ctx.rotate(by: CGFloat(rad))
            // absScale > 1 → la foto viene disegnata più grande del canvas → crop
            // absScale < 1 → la foto viene disegnata più piccola (zoom out)
            ctx.scaleBy(x: mirrorX ? -absScale : absScale, y: absScale)
            // UIImage.draw(in:) gestisce la conversione UIKit↔CG — nessun flip Y
            finalBase.draw(in: CGRect(x: -origSize.width  / 2, y: -origSize.height / 2,
                                      width: origSize.width,   height: origSize.height))
            ctx.restoreGState()
            
            for item in overlayItems {
                let px2 = (previewSize.width  / 2 + item.position.width  - offX) * scaleToCanvas
                let py2 = (previewSize.height / 2 + item.position.height - offY) * scaleToCanvas
                let fs  = item.fontSize * item.scale * scaleToCanvas
                let attrs: [NSAttributedString.Key: Any] = item.isEmoji
                ? [.font: UIFont.systemFont(ofSize: fs)]
                : [.font: UIFont.boldSystemFont(ofSize: fs),
                   .foregroundColor: UIColor(item.color),
                   .strokeColor: UIColor.black,
                   .strokeWidth: NSNumber(value: -2.0)]
                let str  = NSString(string: item.text)
                let sz   = str.size(withAttributes: attrs)
                ctx.saveGState()
                ctx.translateBy(x: px2, y: py2)
                ctx.rotate(by: CGFloat(item.rotation.radians))
                str.draw(at: CGPoint(x: -sz.width / 2, y: -sz.height / 2),
                         withAttributes: attrs)
                ctx.restoreGState()
            }
        }
        return composed.jpegData(compressionQuality: quality)
    }
    
    // MARK: - Save
    
    private func saveNewPhoto() async {
        guard let jpegData = await Task.detached(priority: .userInitiated) { [self] in
            self.flattenToJPEG(quality: 0.88)
        }.value else {
            saveError = "Impossibile generare l'immagine."
            return
        }
        isSaving = true; saveError = nil
        
        let newId   = UUID().uuidString; let now = Date()
        let fileName    = "photo_\(newId).jpg"
        let storagePath = "families/\(familyId)/photos/\(newId)/original.enc"
        let thumbB64    = PhotoRemoteStore.makeThumbnail(from: jpegData)?.base64EncodedString()
        
        let newPhoto = KBFamilyPhoto(
            id: newId, familyId: familyId, fileName: fileName,
            mimeType: "image/jpeg", fileSize: Int64(jpegData.count),
            storagePath: storagePath, thumbnailBase64: thumbB64,
            caption: photo.caption, takenAt: photo.takenAt,
            createdAt: now, updatedAt: now,
            createdBy: userId, updatedBy: userId,
            albumIdsRaw: photo.albumIdsRaw
        )
        newPhoto.syncState = .synced
        
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KBPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cachedURL = cacheDir.appendingPathComponent("\(newId).jpg")
        try? jpegData.write(to: cachedURL, options: .atomic)
        newPhoto.localPath = cachedURL.path
        
        await MainActor.run { modelContext.insert(newPhoto); try? modelContext.save() }
        
        do {
            let dto = try await SyncCenter.photoRemote.upload(
                photoId: newId, familyId: familyId, userId: userId,
                imageData: jpegData, fileName: fileName,
                mimeType: "image/jpeg", takenAt: photo.takenAt,
                caption: photo.caption, albumIds: photo.albumIds,
                precomputedThumbnailB64: thumbB64,
                precomputedVideoDurationSeconds: nil, onProgress: nil
            )
            await MainActor.run {
                newPhoto.downloadURL = dto.downloadURL
                newPhoto.syncState   = .synced
                try? modelContext.save()
            }
            KBLog.sync.kbInfo("PhotoEditor.saveNewPhoto: OK newId=\(newId) from=\(photo.id)")
            isSaving = false; onSaved(newPhoto); dismiss()
        } catch {
            await MainActor.run {
                newPhoto.syncState = .pendingUpsert
                newPhoto.lastSyncError = error.localizedDescription
                try? modelContext.save()
                isSaving = false; saveError = error.localizedDescription
            }
            KBLog.sync.kbError("PhotoEditor.saveNewPhoto: FAILED err=\(error.localizedDescription)")
        }
    }
}

// MARK: - OverlayItemView

private struct OverlayItemView: View {
    @Binding var item: EditorOverlayItem
    let isSelected: Bool
    @State private var dragBase:  CGSize  = .zero
    @State private var scaleBase: CGFloat = 1.0
    
    var body: some View {
        Group {
            if item.isEmoji {
                Text(item.text).font(.system(size: item.fontSize * item.scale))
            } else {
                Text(item.text)
                    .font(.system(size: item.fontSize * item.scale, weight: .bold))
                    .foregroundStyle(item.color)
                    .shadow(color: .black.opacity(0.55), radius: 1, x: 1, y: 1)
            }
        }
        .padding(6)
        .overlay(
            isSelected
            ? RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.white.opacity(0.75),
                              style: StrokeStyle(lineWidth: 1.2, dash: [5]))
                .padding(-2)
            : nil
        )
        .rotationEffect(item.rotation)
        .offset(item.position)
        .gesture(
            SimultaneousGesture(
                DragGesture()
                    .onChanged { v in
                        item.position = CGSize(
                            width:  dragBase.width  + v.translation.width,
                            height: dragBase.height + v.translation.height)
                    }
                    .onEnded { _ in dragBase = item.position },
                SimultaneousGesture(
                    MagnificationGesture()
                        .onChanged { v in item.scale = max(0.3, min(4.0, scaleBase * v)) }
                        .onEnded   { _ in scaleBase = item.scale },
                    RotationGesture()
                        .onChanged { a in item.rotation = item.rotation + a }
                )
            )
        )
    }
}

// MARK: - AdjustSlider

private struct AdjustSlider: View {
    let label: String; let icon: String
    @Binding var value: Float
    let range: ClosedRange<Float>; let neutral: Float
    private var isNeutral: Bool { abs(value - neutral) < 0.01 }
    private var formatted: String {
        let d = value - neutral
        if abs(d) < 0.01 { return "0" }
        return d > 0 ? "+\(Int(d * 100))" : "\(Int(d * 100))"
    }
    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(formatted).font(.caption2.monospacedDigit())
                    .foregroundStyle(isNeutral ? .gray : .white)
            }
            HStack(spacing: 8) {
                Slider(value: $value, in: range).tint(isNeutral ? .gray : .white)
                if !isNeutral {
                    Button { withAnimation(.snappy) { value = neutral } } label: {
                        Image(systemName: "arrow.counterclockwise").font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
        }
    }
}

// MARK: - FilterThumb

private struct FilterThumb: View {
    let preset:    PhotoFilterPreset
    let imagePath: String
    let isSelected: Bool
    @State private var thumb: UIImage?
    private let size: CGFloat = 70
    private static let sharedCIContext = CIContext(options: [.useSoftwareRenderer: false])
    
    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08)).frame(width: size, height: size)
                if let t = thumb {
                    Image(uiImage: t).resizable().scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ProgressView().tint(.white).scaleEffect(0.7)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 2.5))
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.spring(duration: 0.2), value: isSelected)
            Text(preset.name)
                .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? .white : .gray)
        }
        .task(id: preset.id) {
            // Usa CGImageSourceCreateWithURL per non caricare i 34MB in RAM
            guard let src = CGImageSourceCreateWithURL(
                URL(fileURLWithPath: imagePath) as CFURL, nil),
                  let cgImg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                    kCGImageSourceThumbnailMaxPixelSize:          200 as CFNumber,
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform:   true
                  ] as CFDictionary) else { return }
            let ci       = CIImage(cgImage: cgImg)
            let filtered = preset.filter?(ci) ?? ci
            guard let out = Self.sharedCIContext.createCGImage(filtered, from: filtered.extent) else { return }
            await MainActor.run { self.thumb = UIImage(cgImage: out) }
        }
    }
}
