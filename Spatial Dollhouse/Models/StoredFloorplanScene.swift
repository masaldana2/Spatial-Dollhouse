import CoreGraphics
import Foundation

struct StoredFloorplanScene: Codable {
    static let currentVersion = 1

    let version: Int
    let canvasSize: CGSize
    let geometrySummary: FloorplanGeometrySummary

    init(
        version: Int = Self.currentVersion,
        canvasSize: CGSize,
        geometrySummary: FloorplanGeometrySummary
    ) {
        self.version = version
        self.canvasSize = canvasSize
        self.geometrySummary = geometrySummary
    }
}
