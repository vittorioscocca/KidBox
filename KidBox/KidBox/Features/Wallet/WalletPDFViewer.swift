//
//  WalletPDFViewer.swift
//  KidBox
//
//  Created by vscocca on 20/04/26.
//

import SwiftUI
import PDFKit

struct WalletPDFViewer: View {
    let pdfData: Data

    var body: some View {
        WalletPDFKitView(pdfData: pdfData)
            .ignoresSafeArea(edges: .bottom)
    }
}

private struct WalletPDFKitView: UIViewRepresentable {
    let pdfData: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document == nil {
            uiView.document = PDFDocument(data: pdfData)
        }
    }
}
