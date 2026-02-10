//
//  QuickLookPreview.swift
//  KidBox
//
//  Created by vscocca on 09/02/26.
//

import SwiftUI
import QuickLook

struct QuickLookPreview: UIViewControllerRepresentable {
    let urls: [URL]
    let initialIndex: Int
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let ql = QLPreviewController()
        ql.dataSource = context.coordinator
        ql.delegate = context.coordinator
        ql.currentPreviewItemIndex = max(0, min(initialIndex, urls.count - 1))
        
        let nav = UINavigationController(rootViewController: ql)
        
        // ✅ Questo aiuta a vedere sempre la barra (Done/Share) in sheet su iOS recenti
        nav.modalPresentationStyle = .fullScreen
        
        return nav
    }
    
    func updateUIViewController(_ nav: UINavigationController, context: Context) {
        context.coordinator.urls = urls
        
        guard let ql = nav.viewControllers.first as? QLPreviewController else { return }
        ql.reloadData()
        
        let idx = max(0, min(initialIndex, urls.count - 1))
        if ql.currentPreviewItemIndex != idx {
            ql.currentPreviewItemIndex = idx
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(urls: urls)
    }
    
    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        var urls: [URL]
        init(urls: [URL]) { self.urls = urls }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { urls.count }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            urls[index] as NSURL
        }
    }
}
