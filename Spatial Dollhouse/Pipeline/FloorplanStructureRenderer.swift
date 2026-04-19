import CoreGraphics

enum FloorplanStructureRenderer {
    static func render(
        over sourceImage: CGImage,
        summary: FloorplanGeometrySummary,
        legendItems: [SegmentationLegendItem],
        mask: FloorplanSegmentationMask? = nil
    ) throws -> CGImage {
        let width = sourceImage.width
        let height = sourceImage.height

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
        context.draw(sourceImage, in: rect)
        if let mask {
            let canvasSize = CGSize(width: width, height: height)
            drawWallContours(from: mask, in: context, canvasSize: canvasSize)
            drawDetectedRegions(from: summary.regions, legendItems: legendItems, in: context, canvasSize: canvasSize)
        }
        if mask == nil {
            for region in summary.regions where region.kind == .room {
                let color = legendItems.first { $0.id == region.kind.legendClassID }?.rgba ?? RGBAColor(red: 61, green: 168, blue: 118, alpha: 255)
                context.setStrokeColor(color.cgColor(alpha: 0.35))
                context.setLineWidth(1.5)
                context.stroke(region.boundingBox.insetBy(dx: 1, dy: 1))
            }

            for segment in summary.wallSegments {
                let color = legendItems.first { $0.id == 1 }?.rgba ?? RGBAColor(red: 226, green: 74, blue: 59, alpha: 255)
                let strokeWidth = min(max(2.5, segment.thickness * 0.45), 6.5)
                context.setStrokeColor(color.cgColor(alpha: 0.9))
                context.setLineCap(.round)
                context.setLineWidth(strokeWidth)
                context.move(to: segment.start)
                context.addLine(to: segment.end)
                context.strokePath()
            }

            for junction in summary.junctions {
                let dotRect = CGRect(x: junction.point.x - 2.5, y: junction.point.y - 2.5, width: 5, height: 5)
                context.setFillColor(CGColor(gray: 1.0, alpha: 0.92))
                context.fillEllipse(in: dotRect)
                context.setStrokeColor(CGColor(gray: 0.1, alpha: 0.25))
                context.setLineWidth(0.8)
                context.strokeEllipse(in: dotRect)
            }

            for opening in summary.openings {
                let color = legendItems.first { $0.id == opening.kind.legendClassID }?.rgba ?? RGBAColor(red: 255, green: 255, blue: 255, alpha: 255)
                context.setStrokeColor(color.cgColor(alpha: opening.attachedWallID == nil ? 0.55 : 0.95))
                context.setLineCap(.round)
                context.setLineWidth(opening.kind == .door ? 3.5 : 3)

                if let snappedStart = opening.snappedStart, let snappedEnd = opening.snappedEnd {
                    context.move(to: snappedStart)
                    context.addLine(to: snappedEnd)
                    context.strokePath()

                    if let snappedCenter = opening.snappedCenter {
                        let dot = CGRect(x: snappedCenter.x - 2.5, y: snappedCenter.y - 2.5, width: 5, height: 5)
                        context.setFillColor(color.cgColor(alpha: 1.0))
                        context.fillEllipse(in: dot)
                    }
                } else {
                    let halfSpan = opening.span / 2
                    switch opening.axis {
                    case .horizontal:
                        context.move(to: CGPoint(x: opening.center.x - halfSpan / 2, y: opening.center.y))
                        context.addLine(to: CGPoint(x: opening.center.x + halfSpan / 2, y: opening.center.y))
                    case .vertical:
                        context.move(to: CGPoint(x: opening.center.x, y: opening.center.y - halfSpan / 2))
                        context.addLine(to: CGPoint(x: opening.center.x, y: opening.center.y + halfSpan / 2))
                    }
                    context.strokePath()
                }
            }
        }

        guard let image = context.makeImage() else {
            throw FloorplanAnalyzerError.analysisFailed
        }
        return image
    }
}

private extension FloorplanStructureRenderer {
    static func drawDetectedRegions(
        from regions: [FloorplanDetectedRegion],
        legendItems: [SegmentationLegendItem],
        in context: CGContext,
        canvasSize: CGSize
    ) {
        for region in regions {
            let color = legendItems.first { $0.id == region.kind.legendClassID }?.rgba ?? RGBAColor(red: 255, green: 255, blue: 255, alpha: 255)
            let alpha: CGFloat
            let lineWidth: CGFloat

            switch region.kind {
            case .room:
                alpha = 0.28
                lineWidth = 1.2
            case .door, .window:
                alpha = 0.85
                lineWidth = 2.2
            }

            context.setStrokeColor(color.cgColor(alpha: alpha))
            context.setLineWidth(lineWidth)
            context.stroke(flipped(region.boundingBox.insetBy(dx: 1, dy: 1), in: canvasSize))
        }
    }

    static func drawWallContours(from mask: FloorplanSegmentationMask, in context: CGContext, canvasSize: CGSize) {
        let scaleX = canvasSize.width / CGFloat(mask.width)
        let scaleY = canvasSize.height / CGFloat(mask.height)
        let contourColor = CGColor(red: 0.10, green: 0.45, blue: 0.18, alpha: 0.72)

        context.setFillColor(contourColor)

        for y in 0 ..< mask.height {
            for x in 0 ..< mask.width where mask.classID(atX: x, y: y) == 1 {
                guard isContourPixel(atX: x, y: y, in: mask) else { continue }

                let rect = CGRect(
                    x: CGFloat(x) * scaleX,
                    y: canvasSize.height - (CGFloat(y + 1) * scaleY),
                    width: max(1, scaleX),
                    height: max(1, scaleY)
                )
                context.fill(rect)
            }
        }
    }

    static func isContourPixel(atX x: Int, y: Int, in mask: FloorplanSegmentationMask) -> Bool {
        let neighbors = [
            (x - 1, y),
            (x + 1, y),
            (x, y - 1),
            (x, y + 1)
        ]

        for neighbor in neighbors {
            guard neighbor.0 >= 0, neighbor.0 < mask.width, neighbor.1 >= 0, neighbor.1 < mask.height else {
                return true
            }

            let classID = mask.classID(atX: neighbor.0, y: neighbor.1)
            if classID != 1 {
                return true
            }
        }

        return false
    }

    static func flipped(_ rect: CGRect, in canvasSize: CGSize) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: canvasSize.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

private extension RGBAColor {
    func cgColor(alpha: CGFloat) -> CGColor {
        CGColor(
            red: CGFloat(red) / 255.0,
            green: CGFloat(green) / 255.0,
            blue: CGFloat(blue) / 255.0,
            alpha: alpha
        )
    }
}
