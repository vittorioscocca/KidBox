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
    
    // MARK: - UIViewControllerRepresentable
    
    func makeUIViewController(context: Context) -> UINavigationController {
        KBLog.ui.debug("QuickLookPreview makeUIViewController urls=\(urls.count) initialIndex=\(initialIndex)")
        
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
        context.coordinator.urls = urls
        
        guard let ql = nav.viewControllers.first as? QLPreviewController else {
            KBLog.ui.error("QuickLookPreview updateUIViewController: missing QLPreviewController")
            return
        }
        
        ql.reloadData()
        
        let idx = clampIndex(initialIndex, count: urls.count)
        if ql.currentPreviewItemIndex != idx {
            ql.currentPreviewItemIndex = idx
        }
        
        KBLog.ui.debug("QuickLookPreview updated urls=\(urls.count) index=\(idx)")
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(urls: urls)
    }
    
    // MARK: - Helpers
    
    private func clampIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return max(0, min(index, count - 1))
    }
    
    // MARK: - Coordinator
    
    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        var urls: [URL]
        
        init(urls: [URL]) {
            self.urls = urls
            super.init()
            KBLog.ui.debug("QuickLookPreview.Coordinator init urls=\(urls.count)")
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            urls.count
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            guard index >= 0, index < urls.count else {
                KBLog.ui.error("QuickLookPreview previewItemAt out-of-bounds index=\(index) count=\(self.urls.count)")
                return NSURL(fileURLWithPath: "/") // defensive fallback; should never happen
            }
            return urls[index] as NSURL
        }
        
        // Optional delegate hooks (kept minimal, useful for tracing lifecycle)
        func previewControllerWillDismiss(_ controller: QLPreviewController) {
            KBLog.ui.debug("QuickLookPreview willDismiss")
        }
        
        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            KBLog.ui.debug("QuickLookPreview didDismiss")
        }
    }
}
