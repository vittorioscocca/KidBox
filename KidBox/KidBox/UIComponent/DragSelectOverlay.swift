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
//
//  ┌─────────────────────────────────────────────────────────────────┐
//  │  BUG SCROLL (06/11)                                             │
//  │  L'overlay copre tutta la griglia con un DragGesture da 4 pt:   │
//  │  ogni trascinamento, anche verticale, veniva preso dalla        │
//  │  selezione e lo ScrollView non scorreva più (impossibile        │
//  │  raggiungere altre foto da selezionare).                        │
//  │                                                                 │
//  │  FIX                                                            │
//  │  Riconoscitore UIKit che parte SOLO se il trascinamento è       │
//  │  orizzontale (come Foto di iOS); quelli verticali falliscono e  │
//  │  passano allo scroll. A selezione iniziata lo scroll è sospeso, │
//  │  così si può continuare in ogni direzione senza che la pagina   │
//  │  si muova. Su Mac Catalyst il mouse non scorre trascinando:     │
//  │  qui il drag parte in ogni direzione.                           │
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
                DragSelectSurface(
                    onTap: { point in
                        // Tap singolo: sempre bidirezionale (toggle puro)
                        guard let index = cellIndex(at: point) else { return }
                        onToggle(index)
                    },
                    onDragBegan: { point in
                        directionSet = false
                        draggedIndices.removeAll()
                        handleDrag(at: point)
                    },
                    onDragChanged: { point in handleDrag(at: point) },
                    onDragEnded: {
                        directionSet   = false
                        draggedIndices.removeAll()
                    }
                )
            }
        }
    }
    
    // MARK: Drag
    
    private func handleDrag(at point: CGPoint) {
        guard let index = cellIndex(at: point) else { return }
        
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

// MARK: - DragSelectSurface

/// Superficie trasparente con tap e pan UIKit. Il pan comincia solo se il
/// movimento è prevalentemente orizzontale: i trascinamenti verticali falliscono
/// e vanno allo ScrollView che contiene la griglia.
private struct DragSelectSurface: UIViewRepresentable {
    
    var onTap:         (CGPoint) -> Void
    var onDragBegan:   (CGPoint) -> Void
    var onDragChanged: (CGPoint) -> Void
    var onDragEnded:   () -> Void
    
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }
    
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: DragSelectSurface
        private weak var pausedScrollView: UIScrollView?
        
        init(parent: DragSelectSurface) { self.parent = parent }
        
        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended else { return }
            parent.onTap(g.location(in: g.view))
        }
        
        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            let point = g.location(in: g.view)
            switch g.state {
            case .began:
                pauseScroll(from: g.view)
                parent.onDragBegan(point)
            case .changed:
                parent.onDragChanged(point)
            case .ended, .cancelled, .failed:
                resumeScroll()
                parent.onDragEnded()
            default:
                break
            }
        }
        
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            #if targetEnvironment(macCatalyst)
            return true
            #else
            guard let pan = g as? UIPanGestureRecognizer else { return true }
            let t = pan.translation(in: pan.view)
            return abs(t.x) > abs(t.y)
            #endif
        }
        
        /// Sospende lo scroll mentre si seleziona trascinando, per non muovere la pagina.
        private func pauseScroll(from view: UIView?) {
            var v = view?.superview
            while let current = v, !(current is UIScrollView) { v = current.superview }
            guard let scroll = v as? UIScrollView, scroll.isScrollEnabled else { return }
            scroll.isScrollEnabled = false
            pausedScrollView = scroll
        }
        
        private func resumeScroll() {
            pausedScrollView?.isScrollEnabled = true
            pausedScrollView = nil
        }
    }
}
