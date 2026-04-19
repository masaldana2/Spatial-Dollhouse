enum FloorplanAnalyzerFactory {
    static func makeDefault() -> any FloorplanAnalyzing {
        if let analyzer = try? CoreMLFloorplanAnalyzer() {
            return analyzer
        }
        return DemoFloorplanAnalyzer()
    }
}
