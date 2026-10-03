//
//  KBTabBarScrollObserver.swift
//  KidBox
//
//  La barra in basso si rimpicciolisce quando si scorre per leggere oltre
//  (dito verso l'alto) e torna grande quando si torna indietro o si arriva in
//  cima, come le barre di sistema di iOS 26 (`tabBarMinimizeBehavior`, che però
//  vale solo per la TabView di sistema).
//
//  Un osservatore solo, sulla finestra, invece di un modificatore in ognuna
//  delle 15 schermate con la barra (ScrollView, List e Form diversi): un pan
//  che riconosce insieme a tutti gli altri, non annulla i tocchi e non ritarda
//  niente, quindi le schermate scorrono come prima. Conta solo se sotto il dito
//  c'è un contenuto che scorre in verticale: un carosello orizzontale o una
//  pagina corta non rimpiccioliscono niente.
//

import SwiftUI
import Combine
import UIKit

/// Lo stato condiviso fra l'osservatore e la barra.
@MainActor
final class KBTabBarScrollState: ObservableObject {
    static let shared = KBTabBarScrollState()
    @Published private(set) var isMinimized = false

    func set(_ minimized: Bool) {
        guard minimized != isMinimized else { return }
        isMinimized = minimized
    }
}

/// La barra che segue lo stato da sola: a ogni rimpicciolimento si ridisegna
/// lei, non la radice con tutta la pila.
struct ScrollAwareTabBar: View {
    @ObservedObject private var scroll = KBTabBarScrollState.shared
    let selected: KBRootTab
    let onSelect: (KBRootTab) -> Void
    let onAssistant: () -> Void

    var body: some View {
        KBLiquidTabBar(selected: selected, isMinimized: scroll.isMinimized,
                       onSelect: onSelect, onAssistant: onAssistant)
    }
}

struct KBTabBarScrollObserver: UIViewRepresentable {

    /// Falso quando la barra non c'è: niente da rimpicciolire, e si riparte grande.
    let isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: ObserverView, context: Context) {
        context.coordinator.isActive = isActive
        if !isActive { KBTabBarScrollState.shared.set(false) }
    }

    static func dismantleUIView(_ view: ObserverView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class ObserverView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.attach(to: window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        var isActive = false

        private weak var window: UIWindow?
        private var pan: UIPanGestureRecognizer?
        private weak var scrollView: UIScrollView?
        private var offsetObservation: NSKeyValueObservation?
        private var lastY: CGFloat = 0
        private var travel: CGFloat = 0
        /// Punti di trascinamento nella stessa direzione prima di cambiare stato:
        /// sotto, un tremolio del dito farebbe pulsare la barra.
        private let threshold: CGFloat = 28

        func attach(to window: UIWindow?) {
            guard let window, window !== self.window else { return }
            detach()
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.delegate = self
            window.addGestureRecognizer(pan)
            self.window = window
            self.pan = pan
        }

        func detach() {
            if let pan { pan.view?.removeGestureRecognizer(pan) }
            pan = nil
            window = nil
            offsetObservation = nil
        }

        // Riconosce insieme a tutti, non aspetta nessuno e nessuno lo aspetta.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer) -> Bool { false }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }

        @objc private func handle(_ g: UIPanGestureRecognizer) {
            guard isActive, let window else { return }
            switch g.state {
            case .began:
                let found = verticalScrollView(at: g.location(in: window), in: window)
                if found !== scrollView { observe(found) }
                scrollView = found
                lastY = g.translation(in: window).y
                travel = 0
            case .changed:
                guard scrollView != nil else { return }
                let y = g.translation(in: window).y
                let dy = y - lastY
                lastY = y
                if (dy < 0) != (travel < 0) { travel = 0 }
                travel += dy
                if travel < -threshold {
                    KBTabBarScrollState.shared.set(true)
                    travel = 0
                } else if travel > threshold {
                    KBTabBarScrollState.shared.set(false)
                    travel = 0
                }
            default:
                break
            }
        }

        /// In cima la barra torna grande, anche quando ci si arriva per inerzia
        /// o col tocco sulla barra di stato. Solo a dito sollevato e salendo:
        /// mentre il titolo grande si richiude, iOS toglie margine in alto alla
        /// stessa velocità con cui cresce l'offset, e la pagina sembra «in cima»
        /// per i primi cento punti di scorrimento (visto nel banco il 03/10/2026:
        /// la barra si rimpiccioliva e tornava subito grande).
        private func observe(_ sv: UIScrollView?) {
            offsetObservation = sv?.observe(\.contentOffset, options: [.old, .new]) { sv, change in
                MainActor.assumeIsolated {
                    guard !sv.isDragging,
                          let old = change.oldValue, let new = change.newValue, new.y < old.y else { return }
                    if new.y <= -sv.adjustedContentInset.top + 8 {
                        KBTabBarScrollState.shared.set(false)
                    }
                }
            }
        }

        private func verticalScrollView(at point: CGPoint, in window: UIWindow) -> UIScrollView? {
            var view = window.hitTest(point, with: nil)
            while let v = view {
                if let sv = v as? UIScrollView, sv.isScrollEnabled,
                   sv.contentSize.height + sv.adjustedContentInset.top + sv.adjustedContentInset.bottom > sv.bounds.height + 1 {
                    return sv
                }
                view = v.superview
            }
            return nil
        }
    }
}
