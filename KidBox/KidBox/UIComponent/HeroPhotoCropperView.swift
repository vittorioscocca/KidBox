//
//  HeroPhotoCropperView.swift
//  KidBox
//
//  Created by vscocca on 06/02/26.
//

import SwiftUI

struct HeroCrop: Codable {
    var scale: Double
    var offsetX: Double
    var offsetY: Double
}

struct HeroPhotoCropperView: View {
    let imageData: Data
    let initialCrop: HeroCrop
    
    /// 👇 lo passa il parent (ViewModel) mentre fa upload
    let isSaving: Bool
    
    let onCancel: () -> Void
    let onSave: (HeroCrop) -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    
    /// safety net UI: evita doppio tap ravvicinato
    @State private var didTapSave = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                    
                    if let uiImage = UIImage(data: imageData) {
                        GeometryReader { geo in
                            let size = geo.size
                            
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: size.width, height: size.height)
                                .scaleEffect(scale)
                                .offset(offset)
                                .clipped()
                                .contentShape(Rectangle())
                                .gesture(dragGesture)
                                .gesture(magnifyGesture)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        Text("Immagine non valida")
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack {
                        Spacer()
                        
                        HStack(spacing: 10) {
                            Image(systemName: "hand.draw")
                            Text("Trascina per spostare • Pinch per zoom")
                        }
                        .font(.subheadline).bold()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.bottom, 12)
                    }
                    
                    if isSaving {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.black.opacity(0.20))
                        
                        ProgressView()
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .frame(height: 220)
                .padding(.horizontal)
                
                HStack(spacing: 12) {
                    Button("Reset") {
                        guard !isSaving else { return }
                        withAnimation(.spring()) {
                            scale = 1.0
                            offset = .zero
                            lastScale = 1.0
                            lastOffset = .zero
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
                    
                    Spacer()
                    
                    Button(isSaving ? "Salvataggio…" : "Salva") {
                        guard !isSaving else { return }
                        guard !didTapSave else { return }
                        didTapSave = true
                        
                        onSave(HeroCrop(
                            scale: Double(scale),
                            offsetX: Double(offset.width),
                            offsetY: Double(offset.height)
                        ))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || didTapSave)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top, 16)
            .navigationTitle("Foto famiglia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") {
                        guard !isSaving else { return }
                        onCancel()
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                scale = CGFloat(initialCrop.scale)
                offset = CGSize(width: initialCrop.offsetX, height: initialCrop.offsetY)
                lastScale = scale
                lastOffset = offset
                didTapSave = false
            }
            .onChange(of: isSaving) { _, saving in
                // quando finisce il salvataggio, riabilita il bottone
                if !saving { didTapSave = false }
            }
        }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                guard !isSaving else { return }
                offset = CGSize(
                    width: lastOffset.width + v.translation.width,
                    height: lastOffset.height + v.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }
    
    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { v in
                guard !isSaving else { return }
                let next = lastScale * v
                scale = min(max(next, 1.0), 3.0)
            }
            .onEnded { _ in
                lastScale = scale
            }
    }
}
