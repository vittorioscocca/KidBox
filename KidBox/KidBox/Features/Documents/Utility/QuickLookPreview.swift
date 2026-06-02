//
//  QuickLookPreview.swift
//  KidBox
//
//  Created by vscocca on 09/02/26.
//

import SwiftUI
import QuickLook
import OSLog

/// SwiftUI wrapper for `QLPreviewController` to preview one or more local file URLs.
///
/// - Important: `QuickLook` expects **local file URLs**. If you pass remote URLs,
///   download them first and provide a local temporary/cache URL.
/// - Note: The controller is embedded in a `UINavigationController` so the
///   Done/Share bar is reliably visible when presented as a sheet on recent iOS versions.
struct QuickLookPreview: UIViewControllerRepresentable {
    
    // MARK: - Input
    let urls: [URL]
    let initialIndex: Int
    /// Chiamato quando l'utente tocca "Fine" in QuickLook. Necessario quando il preview è
    /// presentato in `fullScreenCover` per riportare a `nil` il binding di presentazione
    /// (altrimenti la cover si chiude ma lo stato resta "presentato").
    var onFinished: (() -> Void)? = nil

    // MARK: - UIViewControllerRepresentable
    
    func makeUIViewController(context: Context) -> UINavigationController {
        KBLog.ui.kbDebug("QuickLookPreview makeUIViewController urls=\(urls.count) initialIndex=\(initialIndex)")
        
        let ql = QLPreviewController()
        ql.dataSource = context.coordinator
        ql.delegate = context.coordinator
        ql.currentPreviewItemIndex = clampIndex(initialIndex, count: urls.count)
        
        let nav = UINavigationController(rootViewController: ql)
        
        // ✅ Keeps navigation bar (Done/Share) visible in sheet presentation on newer iOS versions
        nav.modalPresentationStyle = .fullScreen
        
        return nav
    }
    
    func updateUIViewController(_ nav: UINavigationController, context: Context) {
        guard let ql = nav.viewControllers.first as? QLPreviewController else {
            KBLog.ui.kbError("QuickLookPreview updateUIViewController: missing QLPreviewController")
            return
        }
        
        let idx = clampIndex(initialIndex, count: urls.count)
        
        // Avoid redundant `reloadData()` when SwiftUI re-renders with the same URLs — that reload
        // can flash the sheet / re-run layout as if the preview opened twice.
        if context.coordinator.urls == urls {
            if ql.currentPreviewItemIndex != idx {
                ql.currentPreviewItemIndex = idx
                KBLog.ui.kbDebug("QuickLookPreview updated index only index=\(idx)")
            }
            return
        }
        
        context.coordinator.urls = urls
        ql.reloadData()
        if ql.currentPreviewItemIndex != idx {
            ql.currentPreviewItemIndex = idx
        }
        
        KBLog.ui.kbDebug("QuickLookPreview updated urls=\(urls.count) index=\(idx)")
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(urls: urls, onFinished: onFinished)
    }
    
    // MARK: - Helpers
    
    private func clampIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return max(0, min(index, count - 1))
    }
    
    // MARK: - Coordinator
    
    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        var urls: [URL]
        let onFinished: (() -> Void)?

        init(urls: [URL], onFinished: (() -> Void)? = nil) {
            self.urls = urls
            self.onFinished = onFinished
            super.init()
            KBLog.ui.kbDebug("QuickLookPreview.Coordinator init urls=\(urls.count)")
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            urls.count
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            guard index >= 0, index < urls.count else {
                KBLog.ui.kbError("QuickLookPreview previewItemAt out-of-bounds index=\(index) count=\(self.urls.count)")
                return NSURL(fileURLWithPath: "/") // defensive fallback; should never happen
            }
            return urls[index] as NSURL
        }
        
        // Optional delegate hooks (kept minimal, useful for tracing lifecycle)
        func previewControllerWillDismiss(_ controller: QLPreviewController) {
            KBLog.ui.kbDebug("QuickLookPreview willDismiss")
        }
        
        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            KBLog.ui.kbDebug("QuickLookPreview didDismiss")
            onFinished?()
        }
    }
}
