//
//  KBSearchBarHiddenUntilPulled.swift
//  KidBox
//
//  Come nelle app di sistema (Messaggi, Note): la barra di ricerca di
//  `.searchable` sta nascosta sotto il titolo grande e compare tirando giù la
//  lista. SwiftUI la mostra aperta alla prima apertura e non ha un'API per
//  partire chiusa: qui si scorre la lista di quanto è alta la barra, una volta
//  sola per schermata, così UIKit la fa rientrare da sé.
//
//  Da applicare alla vista che ha `.searchable(... .navigationBarDrawer)`.
//  Perché UIKit agganci la barra alla scroll, la lista deve essere il primo
//  elemento del contenuto (niente selettori o pillole sopra: vanno in
//  `safeAreaInset(edge: .top)`).
//

import SwiftUI
import UIKit

extension View {
    /// La barra di ricerca parte nascosta e si rivela con il gesto di pull-down.
    func kbSearchBarHiddenUntilPulled() -> some View {
        background(KBSearchBarHiddenProbe().frame(width: 0, height: 0))
    }

    /// `.searchable` nel drawer della barra, nascosto sotto il titolo finché non si tira giù la lista.
    /// Con `enabled == false` la barra non c'è proprio (viste senza lista da tirare giù, come il calendario).
    /// `hiddenAtStart` va a `false` dopo il primo cambio di modalità: la barra torna normale, senza ri-nasconderla.
    @ViewBuilder
    func kbSearchable(text: Binding<String>, prompt: LocalizedStringKey, enabled: Bool = true, hiddenAtStart: Bool = true) -> some View {
        if enabled {
            searchable(text: text, placement: .navigationBarDrawer(displayMode: .automatic), prompt: prompt)
                .background { if hiddenAtStart { KBSearchBarHiddenProbe().frame(width: 0, height: 0) } }
        } else {
            self
        }
    }
}

private struct KBSearchBarHiddenProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) {}

    /// Per qualche secondo dopo l'apertura tiene la barra chiusa: le righe con le loro @Query
    /// (cure, vaccini) si impaginano dopo, e quel re-layout riporta la lista in cima rivelando
    /// la barra. Smette al primo tocco dell'utente sulla lista.
    final class Probe: UIView {
        private var started = false
        private var timer: Timer?
        private var startedAt = Date()
        private var userTouched = false
        private var collapsedOffset: CGFloat?
        private weak var observedScroll: UIScrollView?

        private static let duration: TimeInterval = 4

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { stop(); return }
            guard !started else { return }
            started = true
            startedAt = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        }

        deinit { timer?.invalidate() }

        private func stop() {
            timer?.invalidate()
            timer = nil
            observedScroll?.panGestureRecognizer.removeTarget(self, action: #selector(userPan(_:)))
            observedScroll = nil
        }

        @objc private func userPan(_ g: UIPanGestureRecognizer) {
            if g.state == .began { userTouched = true }
        }

        private func tick() {
            guard window != nil else { return }
            if Date().timeIntervalSince(startedAt) > Self.duration || userTouched { stop(); return }
            guard let host = owningViewController(),
                  let search = host.navigationItem.searchController
                    ?? host.parent?.navigationItem.searchController
                    ?? host.navigationController?.topViewController?.navigationItem.searchController,
                  let scroll = largestScrollView(in: host.view)
            else { return }
            if observedScroll !== scroll {
                observedScroll?.panGestureRecognizer.removeTarget(self, action: #selector(userPan(_:)))
                scroll.panGestureRecognizer.addTarget(self, action: #selector(userPan(_:)))
                observedScroll = scroll
            }
            // L'utente sta cercando: non si tocca nulla.
            if search.isActive || !(search.searchBar.text ?? "").isEmpty { stop(); return }
            let h = search.searchBar.bounds.height
            guard scroll.bounds.height > 0, h > 0, !scroll.isTracking, !scroll.isDragging, !scroll.isDecelerating else { return }
            let top = -scroll.adjustedContentInset.top
            if let collapsed = collapsedOffset {
                // La lista è tornata in cima da sola (re-layout): si richiude.
                if scroll.contentOffset.y < collapsed - h / 2 { collapse(scroll, top: top, height: h) }
            } else if abs(scroll.contentOffset.y - top) < 2 {
                collapse(scroll, top: top, height: h)
            }
        }

        private func collapse(_ scroll: UIScrollView, top: CGFloat, height: CGFloat) {
            let y = top + height
            collapsedOffset = y
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: false)
        }

        private func owningViewController() -> UIViewController? {
            var r: UIResponder? = self
            while let n = r?.next {
                if let vc = n as? UIViewController { return vc }
                r = n
            }
            return nil
        }

        private func largestScrollView(in root: UIView) -> UIScrollView? {
            var best: UIScrollView?
            var bestArea: CGFloat = 0
            var stack: [UIView] = [root]
            while let v = stack.popLast() {
                if let s = v as? UIScrollView, !(v is UITextView), s.window != nil {
                    let a = s.bounds.width * s.bounds.height
                    if a > bestArea { best = s; bestArea = a }
                }
                stack.append(contentsOf: v.subviews)
            }
            return best
        }
    }
}
