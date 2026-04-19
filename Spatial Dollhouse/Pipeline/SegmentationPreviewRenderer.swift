import CoreGraphics
import CoreImage
import CoreML
import CoreVideo
import Foundation

struct SegmentationPreviewRenderer {
    static func makeDemoPreview(width: Int, height: Int, legendItems: [SegmentationLegendItem]) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        let roomColor = legendItems[safe: 4]?.rgba ?? RGBAColor(red: 61, green: 168, blue: 118, alpha: 255)
        let wallColor = legendItems[safe: 1]?.rgba ?? RGBAColor(red: 226, green: 74, blue: 59, alpha: 255)
        let windowColor = legendItems[safe: 3]?.rgba ?? RGBAColor(red: 68, green: 145, blue: 255, alpha: 255)
        let doorColor = legendItems[safe: 2]?.rgba ?? RGBAColor(red: 244, green: 164, blue: 37, alpha: 255)

        for y in 0 ..< height {
            for x in 0 ..< width {
                let offset = (y * width + x) * 4
                var color = RGBAColor(red: 250, green: 250, blue: 252, alpha: 255)

                if x > width / 8 && x < (width * 7 / 8) && y > height / 8 && y < (height * 7 / 8) {
                    color = roomColor
                }
                if x < width / 10 || x > width * 9 / 10 || y < height / 10 || y > height * 9 / 10 {
                    color = wallColor
                }
                if y > height / 3 && y < height / 3 + max(8, height / 60) && x > width / 5 && x < width * 2 / 5 {
                    color = windowColor
                }
                if x > width * 3 / 5 && x < width * 3 / 5 + max(8, width / 60) && y > height / 2 && y < height * 3 / 4 {
                    color = doorColor
                }

                pixels[offset] = color.red
                pixels[offset + 1] = color.green
                pixels[offset + 2] = color.blue
                pixels[offset + 3] = color.alpha
            }
        }

        return try makeImage(fromRGBABytes: pixels, width: width, height: height)
    }

    static func makePreview(from pixelBuffer: CVPixelBuffer) throws -> CGImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw FloorplanAnalyzerError.unsupportedModelOutput
        }
        return cgImage
    }

    static func makePreview(from multiArray: MLMultiArray, legendItems: [SegmentationLegendItem]) throws -> CGImage {
        let mask = FloorplanSegmentationDecoder.decode(multiArray)
        return try makePreview(from: mask, legendItems: legendItems)
    }

    static func makePreview(from mask: FloorplanSegmentationMask, legendItems: [SegmentationLegendItem]) throws -> CGImage {
        let pixels = makeMaskPixels(from: mask, legendItems: legendItems)
        return try makeImage(fromRGBABytes: pixels, width: mask.width, height: mask.height)
    }

    static func makeOverlayPreview(
        from multiArray: MLMultiArray,
        over sourceImage: CGImage,
        legendItems: [SegmentationLegendItem],
        alpha: CGFloat
    ) throws -> CGImage {
        let mask = FloorplanSegmentationDecoder.decode(multiArray)
        return try makeOverlayPreview(from: mask, over: sourceImage, legendItems: legendItems, alpha: alpha)
    }

    static func makeOverlayPreview(
        from mask: FloorplanSegmentationMask,
        over sourceImage: CGImage,
        legendItems: [SegmentationLegendItem],
        alpha: CGFloat
    ) throws -> CGImage {
        let maskImage = try makePreview(from: mask, legendItems: legendItems)
        let scaledMask = try scale(image: maskImage, to: CGSize(width: sourceImage.width, height: sourceImage.height))
        return try blend(base: sourceImage, overlay: scaledMask, alpha: alpha)
    }

    private static func makeMaskPixels(from mask: FloorplanSegmentationMask, legendItems: [SegmentationLegendItem]) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: mask.width * mask.height * 4)

        for y in 0 ..< mask.height {
            for x in 0 ..< mask.width {
                let classID = Int(mask.classID(atX: x, y: y))
                let color = legendItems.first(where: { $0.id == classID })?.rgba ?? RGBAColor(red: 24, green: 24, blue: 27, alpha: 255)
                let offset = (y * mask.width + x) * 4
                pixels[offset] = color.red
                pixels[offset + 1] = color.green
                pixels[offset + 2] = color.blue
                pixels[offset + 3] = color.alpha
            }
        }

        return pixels
    }

    private static func scale(image: CGImage, to size: CGSize) throws -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FloorplanAnalyzerError.analysisFailed
        }

        context.interpolationQuality = .none
        context.draw(image, in: CGRect(origin: .zero, size: size))

        guard let scaledImage = context.makeImage() else {
            throw FloorplanAnalyzerError.analysisFailed
        }
        return scaledImage
    }

    private static func blend(base: CGImage, overlay: CGImage, alpha: CGFloat) throws -> CGImage {
        let width = base.width
        let height = base.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FloorplanAnalyzerError.analysisFailed
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(base, in: rect)
        context.saveGState()
        context.setAlpha(alpha)
        context.draw(overlay, in: rect)
        context.restoreGState()

        guard let image = context.makeImage() else {
            throw FloorplanAnalyzerError.analysisFailed
        }
        return image
    }

    private static func makeImage(fromRGBABytes pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw FloorplanAnalyzerError.analysisFailed
        }

        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw FloorplanAnalyzerError.analysisFailed
        }

        return image
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
