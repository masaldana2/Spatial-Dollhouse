import CoreGraphics
import CoreImage
import UIKit

extension UIImage {
    var normalizedCGImage: CGImage? {
        if imageOrientation == .up, let cgImage {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let renderedImage = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return renderedImage.cgImage
    }
}
