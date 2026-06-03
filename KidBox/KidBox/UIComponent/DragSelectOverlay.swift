//
//  DragSelectOverlay.swift
//  KidBox
//
//  ViewModifier che gestisce la selezione/deselezione multipla nella griglia
//  foto tramite DragGesture + SpatialTapGesture simultanei.
//
//  ┌─────────────────────────────────────────────────────────────────┐
//  │  BUG ORIGINALE                                                  │
//  │  Il vecchio Color.clear + DragGesture inline ricalcolava        │
//  │  dragSelectIsAdding a ogni onChanged, anche sulle celle già     │
//  │  visitate. Se l'utente trascinava su una cella già selezionata  │
//  │  il flag si ribaltava da "rimuovi" → "aggiungi", rendendo       │
//  │  impossibile deselezionare con il drag.                         │
//  │                                                                 │
//  │  FIX                                                            │
//  │  • dragAdding viene calcolato UNA SOLA VOLTA per drag,          │
//  │    leggendo isSelected(index) sulla prima cella toccata.        │
//  │  • draggedIndices (Set<Int>) impedisce di rielaborare la stessa │
//  │    cella più di una volta nello stesso drag.                    │
//  │  • SpatialTapGesture chiama sempre onToggle (bidirezionale),    │
//  │    indipendente dal drag.                                       │
//  └─────────────────────────────────────────────────────────────────┘

import SwiftUI

// MARK: - DragSelectOverlay

struct DragSelectOverlay: ViewModifier {
    
    // MARK: Input
    
    /// Attiva l'overlay solo in modalità selezione.
    let isActive:   Bool
    /// Larghezza/altezza di ogni cella quadrata.
    let cellSize:   CGFloat
    /// Gap tra le celle.
    let spacing:    CGFloat
    /// Numero di colonne della griglia.
    var columns:    Int = 3
    /// Numero totale di elementi nella griglia.
    let itemCount:  Int
    /// Chiede al parent se l'elemento all'indice dato è selezionato.
    /// Usato per determinare la direzione del drag alla prima cella toccata.
    let isSelected: (Int) -> Bool
    /// Il parent esegue insert o remove in base alla propria logica.
    let onToggle:   (Int) -> Void
    
    // MARK: Private state
    
    /// true  → questo drag sta aggiungendo selezioni
    /// false → questo drag sta rimuovendo selezioni
    @State private var dragAdding:     Bool     = true
    /// La direzione è già stata determinata per il drag corrente.
    @State private var directionSet:   Bool     = false
    /// Indici già processati nel drag corrente: evita il flip su celle già visitate.
    @State private var draggedIndices: Set<Int> = []
    
    // MARK: Body
    
    func body(content: Content) -> some View {
        content.overlay {
            if isActive {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(combinedGesture)
            }
        }
    }
    
    // MARK: Gesture
    
    private var combinedGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                guard let index = cellIndex(at: value.location) else { return }
                
                // ── Determina la direzione UNA SOLA VOLTA per drag ────────
                if !directionSet {
                    dragAdding   = !isSelected(index)  // non sel → aggiungi; sel → rimuovi
                    directionSet = true
                    draggedIndices.removeAll()
                }
                
                // ── Ogni cella viene processata al più una volta per drag ──
                guard !draggedIndices.contains(index) else { return }
                draggedIndices.insert(index)
                
                // Applica solo se la cella è nello stato atteso
                let sel = isSelected(index)
                guard (dragAdding && !sel) || (!dragAdding && sel) else { return }
                onToggle(index)
            }
            .onEnded { _ in
                directionSet   = false
                draggedIndices.removeAll()
            }
            .simultaneously(with:
                                SpatialTapGesture()
                .onEnded { value in
                    // Tap singolo: sempre bidirezionale (toggle puro)
                    guard let index = cellIndex(at: value.location) else { return }
                    onToggle(index)
                }
            )
    }
    
    // MARK: Helpers
    
    /// Converte un punto nell'overlay nell'indice piatto della griglia (0-based).
    private func cellIndex(at point: CGPoint) -> Int? {
        let lastCol = max(0, columns - 1)
        let col   = Int(point.x / (cellSize + spacing)).clamped(to: 0...lastCol)
        let row   = Int(point.y / (cellSize + spacing))
        let index = row * columns + col
        guard index >= 0, index < itemCount else { return nil }
        return index
    }
}
