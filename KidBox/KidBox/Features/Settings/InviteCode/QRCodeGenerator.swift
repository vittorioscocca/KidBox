//
//  QRCodeGenerator.swift
//  KidBox
//
//  Created by vscocca on 13/02/26.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

enum QRCodeGenerator {
    static func image(from string: String, scale: CGFloat = 10) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.correctionLevel = "M"
        
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct QRCodeView: View {
    let payload: String
    
    var body: some View {
        if let img = QRCodeGenerator.image(from: payload) {
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220, maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(.secondary.opacity(0.2))
                .frame(width: 220, height: 220)
                .overlay(Text("QR non disponibile").foregroundStyle(.secondary))
        }
    }
}
