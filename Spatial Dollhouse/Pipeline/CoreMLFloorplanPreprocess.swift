import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

/// Core ML input must match `export_coreml.py`: RGB 8-bit, square `imageSize×imageSize`,
/// values 0…255. The mlpackage ImageType uses `scale=1/255`; normalization is inside the model.
///
/// **Most common mismatch with Python:** this pipeline uses the same **letterbox** as
/// `scripts/run_inference.py` (centered, bilinear resize, pad with ImageNet mean in RGB).
/// Stretching the bitmap to a square without letterbox matches `run_inference --stretch` only.
public enum FloorplanCoreMLInput {
    public struct Layout: Sendable {
        public let imageSize: Int
        public let originalWidth: Int
        public let originalHeight: Int
        public let scaledWidth: Int
        public let scaledHeight: Int
        public let padLeft: Int
        public let padTop: Int
    }

    /// `round(ImageNet_mean * 255)` — must match `run_inference.py` / `export_coreml.py`.
    public static let letterboxFillRGB: (UInt8, UInt8, UInt8) = (124, 116, 103)

    #if canImport(UIKit)
    /// Pixels: `format.scale = 1`, top-left origin (same convention as Python PIL).
    public static func letterboxedUIImage(from image: UIImage, imageSize: Int) -> UIImage {
        precondition(imageSize > 0)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let sz = CGSize(width: imageSize, height: imageSize)
        let renderer = UIGraphicsImageRenderer(size: sz, format: format)
        return renderer.image { ctx in
            let c = letterboxFillRGB
            UIColor(
                red: CGFloat(c.0) / 255,
                green: CGFloat(c.1) / 255,
                blue: CGFloat(c.2) / 255,
                alpha: 1
            ).setFill()
            ctx.fill(CGRect(origin: .zero, size: sz))

            guard let cg = image.cgImage else { return }
            let w = CGFloat(cg.width) // pixel size; avoids confusion with UIImage.size in points
            let h = CGFloat(cg.height)
            guard w > 0, h > 0 else { return }
            let scale = min(CGFloat(imageSize) / w, CGFloat(imageSize) / h)
            let newW = max(1, (w * scale).rounded())
            let newH = max(1, (h * scale).rounded())
            let padLeft = (CGFloat(imageSize) - newW) / 2
            let padTop = (CGFloat(imageSize) - newH) / 2
            ctx.cgContext.interpolationQuality = .medium
            // Use UIImage.draw so UIImage.imageOrientation is applied (raw CGImage alone can look rotated).
            image.draw(in: CGRect(x: padLeft, y: padTop, width: newW, height: newH))
        }
    }

    public static func letterboxedUIImageAndLayout(from image: UIImage, imageSize: Int) -> (image: UIImage, layout: Layout) {
        precondition(imageSize > 0)
        guard let cg = image.cgImage else {
            let rendered = letterboxedUIImage(from: image, imageSize: imageSize)
            return (
                rendered,
                Layout(
                    imageSize: imageSize,
                    originalWidth: imageSize,
                    originalHeight: imageSize,
                    scaledWidth: imageSize,
                    scaledHeight: imageSize,
                    padLeft: 0,
                    padTop: 0
                )
            )
        }

        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let scale = min(CGFloat(imageSize) / w, CGFloat(imageSize) / h)
        let newW = max(1, Int((w * scale).rounded()))
        let newH = max(1, Int((h * scale).rounded()))
        let padLeft = max(0, (imageSize - newW) / 2)
        let padTop = max(0, (imageSize - newH) / 2)
        let rendered = letterboxedUIImage(from: image, imageSize: imageSize)

        return (
            rendered,
            Layout(
                imageSize: imageSize,
                originalWidth: cg.width,
                originalHeight: cg.height,
                scaledWidth: newW,
                scaledHeight: newH,
                padLeft: padLeft,
                padTop: padTop
            )
        )
    }
    #endif
}

/*
 Post-output (optional): Python `run_inference` warps the class map back to the original
 resolution by cropping padding and resizing with nearest-neighbour. Store
 `padLeft`, `padTop`, `newW`, `newH`, `origW`, `origH` from the letterbox step and mirror
 `warp_pred_to_original` if overlays must align with the source photo at full size.

 Other Swift pitfalls:
 - **UIImage.size** is in points; use **cgImage?.width/height** for pixel math.
 - **CIContext** render: ensure color space is sRGB if your plan uses color.
 - **Float16** Core ML vs fp32 PyTorch: tiny differences; should not “look wrong” globally.
 - **Orientation:** `UIImage.imageOrientation` — normalize to `.up` before letterboxing
   if CGImage pixels don’t match what you see on screen.
*/
