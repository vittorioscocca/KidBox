//
//  SupportImageEncoder.swift
//  KidBox
//

import UIKit

enum SupportImageEncoder {
    static let maxImages = 5
    static let maxDimension: CGFloat = 1024
    static let jpegQuality: CGFloat = 0.85
    static let maxDecodedBytes = 5_000_000

    static func jpegBase64(from data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        guard let jpeg = jpegData(from: image) else { return nil }
        guard jpeg.count <= maxDecodedBytes else { return nil }
        return jpeg.base64EncodedString()
    }

    static func jpegData(from image: UIImage) -> Data? {
        let scaled = scale(image: image, maxDimension: maxDimension)
        return scaled.jpegData(compressionQuality: jpegQuality)
    }

    private static func scale(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1)
        guard scale < 1 else { return image }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
