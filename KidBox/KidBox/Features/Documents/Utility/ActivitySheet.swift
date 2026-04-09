//
//  ActivitySheet.swift
//  KidBox
//
//  Created by vscocca on 09/04/26.
//


import SwiftUI
import UIKit

/// SwiftUI wrapper for `UIActivityViewController`.
///
/// Usage:
/// ```swift
/// .sheet(item: $shareURLs) { urls in
///     ActivitySheet(items: urls.value)
/// }
/// ```
///
/// - Note: Wrap the URL array in an `Identifiable` container so it can be
///   used with `.sheet(item:)` and replaced atomically.
struct ActivitySheet: UIViewControllerRepresentable {
    
    let items: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: items,
            applicationActivities: applicationActivities
        )
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Identifiable wrapper for URL arrays

/// Lets us drive `.sheet(item:)` with a list of URLs.
struct ShareURLsPayload: Identifiable {
    let id = UUID()
    let urls: [URL]
}
