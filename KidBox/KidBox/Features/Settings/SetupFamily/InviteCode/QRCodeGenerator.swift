//
//  QRCodeGenerator.swift
//  KidBox
//
//  Created by vscocca on 13/02/26.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import OSLog

/// QR code utilities (pure helper).
///
/// - Note: The generator intentionally does not log the full payload to avoid leaking secrets
///   (your QR payload can contain sensitive crypto material).
enum QRCodeGenerator {
    
    /// Generates a QR code image from a UTF-8 string.
    ///
    /// - Parameters:
    ///   - string: The payload to encode (UTF-8).
    ///   - scale: Pixel scaling factor applied to the CI output image.
    /// - Returns: A rendered `UIImage` or `nil` if generation fails.
    static func image(from string: String, scale: CGFloat = 10) -> UIImage? {
        // Local CI objects are cheap enough for this usage.
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.correctionLevel = "M" // medium error correction (balanced density/resilience)
        
        guard let output = filter.outputImage else {
            KBLog.ui.error("QRCodeGenerator: outputImage is nil")
            return nil
        }
        
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
            KBLog.ui.error("QRCodeGenerator: createCGImage failed extent=\(String(describing: transformed.extent), privacy: .public)")
            return nil
        }
        
        KBLog.ui.debug("QRCodeGenerator: generated image scale=\(scale, privacy: .public)")
        return UIImage(cgImage: cgImage)
    }
}

/// Renders a QR code for the given payload.
///
/// - Important: Avoid logging `payload` directly; it may include secrets (e.g., encrypted invite data).
struct QRCodeView: View {
    let payload: String
    
    var body: some View {
        if let img = QRCodeGenerator.image(from: payload) {
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220, maxHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel("Codice QR")
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.secondary.opacity(0.2))
                .frame(width: 220, height: 220)
                .overlay(
                    Text("QR non disponibile")
                        .foregroundStyle(.secondary)
                )
                .accessibilityLabel("Codice QR non disponibile")
        }
    }
}
