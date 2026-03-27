//
//  DragSelectOverlay.swift
//  KidBox
//
//  Created by vscocca on 27/03/26.
//

// MARK: - DragSelectOverlay.swift
// Sostituisce il Color.clear + DragGesture nelle griglie foto.
// Funzionalità:
//   • Drag per selezionare/deselezionare celle (non blocca lo scroll)
//   • Auto-scroll quando il dito si avvicina al bordo superiore/inferiore
//   • Tap singolo per toggle selezione

import SwiftUI
import UIKit

// MARK: - ViewModifier pubblico

struct DragSelectOverlay: ViewModifier {
    let isActive: Bool
    let cellSize: CGFloat
    let spacing: CGFloat
    let itemCount: Int
    let scrollView: UIScrollView?          // passato da ScrollViewProxy reader
    
    let onToggle: (Int) -> Void            // index dell'item
    let onDragStart: (Bool) -> Void        // true = stiamo aggiungendo
    let isAdding: Bool
    
    func body(content: Content) -> some View {
        content.overlay(
            Group {
                if isActive {
                    DragSelectUIView(
                        cellSize: cellSize,
                        spacing: spacing,
                        itemCount: itemCount,
                        scrollView: scrollView,
                        isAdding: isAdding,
                        onToggle: onToggle,
                        onDragStart: onDragStart
                    )
                }
            }
        )
    }
}

// MARK: - UIViewRepresentable

private struct DragSelectUIView: UIViewRepresentable {
    let cellSize: CGFloat
    let spacing: CGFloat
    let itemCount: Int
    let scrollView: UIScrollView?
    let isAdding: Bool
    let onToggle: (Int) -> Void
    let onDragStart: (Bool) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        // CHIAVE: permette al pan di coesistere con lo scroll
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }
    
    // MARK: Coordinator
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: DragSelectUIView
        private var lastToggledIndex: Int = -1
        private var autoScrollTimer: Timer?
        private var currentDragY: CGFloat = 0
        private var isAddingMode: Bool = true
        
        init(_ parent: DragSelectUIView) {
            self.parent = parent
        }
        
        // MARK: UIGestureRecognizerDelegate
        // Permette al pan di coesistere con lo UIScrollView sottostante.
        // Il pan viene riconosciuto solo se il movimento è prevalentemente orizzontale
        // oppure se siamo già in modalità selezione (isActive è garantito dall'overlay).
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            // Permetti scroll verticale e drag selezione contemporaneamente
            return other is UIPanGestureRecognizer
        }
        
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return false
        }
        
        // MARK: Pan handler
        
        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            guard let view = pan.view else { return }
            let location = pan.location(in: view)
            currentDragY = pan.location(in: pan.view?.superview).y
            
            switch pan.state {
            case .began:
                let index = indexAt(location, in: view)
                guard index >= 0 else { return }
                // Determina se stiamo aggiungendo o rimuovendo
                isAddingMode = true // sarà sovrascritta da onDragStart
                parent.onDragStart(isAddingMode)
                parent.onToggle(index)
                lastToggledIndex = index
                startAutoScroll()
                
            case .changed:
                let index = indexAt(location, in: view)
                guard index >= 0, index != lastToggledIndex else { return }
                parent.onToggle(index)
                lastToggledIndex = index
                
            case .ended, .cancelled, .failed:
                stopAutoScroll()
                lastToggledIndex = -1
                
            default:
                break
            }
        }
        
        @objc func handleTap(_ tap: UITapGestureRecognizer) {
            guard let view = tap.view else { return }
            let location = tap.location(in: view)
            let index = indexAt(location, in: view)
            guard index >= 0 else { return }
            parent.onToggle(index)
        }
        
        // MARK: Index calculation
        
        private func indexAt(_ location: CGPoint, in view: UIView) -> Int {
            let col = Int(location.x / (parent.cellSize + parent.spacing)).clamped(to: 0...2)
            let row = Int(location.y / (parent.cellSize + parent.spacing))
            let index = row * 3 + col
            guard index >= 0, index < parent.itemCount else { return -1 }
            return index
        }
        
        // MARK: Auto-scroll (stile Apple Foto)
        
        private func startAutoScroll() {
            stopAutoScroll()
            autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
                self?.performAutoScroll()
            }
        }
        
        private func stopAutoScroll() {
            autoScrollTimer?.invalidate()
            autoScrollTimer = nil
        }
        
        private func performAutoScroll() {
            guard let scrollView = parent.scrollView else { return }
            
            let viewportHeight = scrollView.bounds.height
            // Zona di trigger: ultimi/primi 80pt della viewport
            let edgeZone: CGFloat = 80
            // Velocità massima di scroll: 8pt per frame (≈480pt/sec a 60fps)
            let maxSpeed: CGFloat = 8
            
            // Posizione Y del dito rispetto alla scrollView
            let fingerY = currentDragY - scrollView.frame.minY
            
            var delta: CGFloat = 0
            
            if fingerY < edgeZone {
                // Vicino al bordo superiore → scroll verso l'alto
                let ratio = 1 - (fingerY / edgeZone)  // 0...1
                delta = -maxSpeed * ratio
            } else if fingerY > viewportHeight - edgeZone {
                // Vicino al bordo inferiore → scroll verso il basso
                let ratio = (fingerY - (viewportHeight - edgeZone)) / edgeZone
                delta = maxSpeed * ratio
            }
            
            guard abs(delta) > 0.5 else { return }
            
            let currentOffset = scrollView.contentOffset
            let maxY = scrollView.contentSize.height - scrollView.bounds.height
            let newY = (currentOffset.y + delta).clamped(to: 0...maxY)
            
            scrollView.setContentOffset(CGPoint(x: currentOffset.x, y: newY), animated: false)
        }
    }
}
