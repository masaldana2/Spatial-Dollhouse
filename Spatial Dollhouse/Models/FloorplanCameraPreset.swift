enum FloorplanCameraPreset: String, CaseIterable, Identifiable {
    case isometric
    case top
    case front

    var id: String { rawValue }

    var title: String {
        switch self {
        case .isometric:
            "Iso"
        case .top:
            "Top"
        case .front:
            "Front"
        }
    }

    var systemImage: String {
        switch self {
        case .isometric:
            "cube.transparent"
        case .top:
            "square.split.2x2"
        case .front:
            "rectangle.portrait"
        }
    }
}
