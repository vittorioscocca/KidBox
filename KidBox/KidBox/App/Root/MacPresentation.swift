//
//  MacPresentation.swift
//  KidBox
//
//  Helpers to adapt modal presentations to a desktop experience on Mac Catalyst.
//
//  On iPhone/iPad some secondary screens (AI chats, the chat media/links/docs
//  gallery) are presented as sheets. On Mac that feels wrong: a desktop app
//  navigates in place. These helpers keep the iOS behavior untouched while,
//  on Mac Catalyst, pushing the same view into the surrounding NavigationStack.
//

import SwiftUI

extension View {
    /// iOS/iPadOS: presents `content` as a sheet.
    /// Mac Catalyst: pushes `content` onto the enclosing `NavigationStack`
    /// (desktop-style — no modal sheet).
    ///
    /// - Parameter hideMacNavBar: when the destination already draws its own
    ///   header/close affordance (e.g. the chat media gallery), set this to
    ///   `true` so the pushed navigation bar is hidden on Mac.
    ///
    /// The call site must live inside a `NavigationStack` for the Mac push.
    @ViewBuilder
    func sheetOrMacPush<C: View>(
        isPresented: Binding<Bool>,
        hideMacNavBar: Bool = false,
        @ViewBuilder content: @escaping () -> C
    ) -> some View {
        #if targetEnvironment(macCatalyst)
        navigationDestination(isPresented: isPresented) {
            if hideMacNavBar {
                content().toolbar(.hidden, for: .navigationBar)
            } else {
                content()
            }
        }
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }
}

/// Wraps content in a `NavigationStack` on iOS/iPadOS (where the view is shown
/// modally and needs its own navigation context), but NOT on Mac Catalyst,
/// where the view is pushed into the existing detail `NavigationStack` and a
/// nested stack would produce a duplicate navigation bar.
struct ModalNavContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if targetEnvironment(macCatalyst)
        content
        #else
        NavigationStack { content }
        #endif
    }
}
