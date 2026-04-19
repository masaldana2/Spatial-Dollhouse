import SwiftUI

struct SegmentationLegendItem: Identifiable, Hashable {
    let id: Int
    let name: String
    let color: Color
    let rgba: RGBAColor

    init(id: Int, name: String, rgba: RGBAColor) {
        self.id = id
        self.name = name
        self.rgba = rgba
        self.color = Color(
            red: Double(rgba.red) / 255.0,
            green: Double(rgba.green) / 255.0,
            blue: Double(rgba.blue) / 255.0,
            opacity: Double(rgba.alpha) / 255.0
        )
    }

    static let defaults: [SegmentationLegendItem] = [
        SegmentationLegendItem(id: 0, name: "Background", rgba: RGBAColor(red: 24, green: 24, blue: 27, alpha: 255)),
        SegmentationLegendItem(id: 1, name: "Walls", rgba: RGBAColor(red: 226, green: 74, blue: 59, alpha: 255)),
        SegmentationLegendItem(id: 2, name: "Doors", rgba: RGBAColor(red: 244, green: 164, blue: 37, alpha: 255)),
        SegmentationLegendItem(id: 3, name: "Windows", rgba: RGBAColor(red: 68, green: 145, blue: 255, alpha: 255)),
        SegmentationLegendItem(id: 4, name: "Rooms", rgba: RGBAColor(red: 61, green: 168, blue: 118, alpha: 255)),
        SegmentationLegendItem(id: 5, name: "Fixed Objects", rgba: RGBAColor(red: 167, green: 88, blue: 222, alpha: 255)),
        SegmentationLegendItem(id: 6, name: "Text / Symbols", rgba: RGBAColor(red: 235, green: 210, blue: 77, alpha: 255)),
    ]
}

struct RGBAColor: Hashable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
}
