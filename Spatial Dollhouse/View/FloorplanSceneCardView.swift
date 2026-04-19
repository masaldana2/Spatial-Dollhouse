import RealityKit
import SwiftUI

struct FloorplanSceneCardView: View {
    let summary: FloorplanGeometrySummary
    let canvasSize: CGSize
    @State private var cameraPreset: FloorplanCameraPreset = .isometric
    @State private var sceneResetSeed = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("3D Preview")
                    .font(.headline)

                Spacer()

                Button {
                    sceneResetSeed += 1
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .labelStyle(.iconOnly)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: Circle())
                .accessibilityLabel("Reset camera")
            }

            if summary.wallSegments.isEmpty, summary.segmentationMask == nil {
                ContentUnavailableView(
                    "No 3D preview yet",
                    systemImage: "cube.transparent",
                    description: Text("Run analysis to generate wall geometry before building the 3D preview.")
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 280)
            } else {
                cameraPresetPicker

                FloorplanRealityView(
                    summary: summary,
                    canvasSize: canvasSize,
                    cameraPreset: cameraPreset
                )
                    .id("\(cameraPreset.rawValue)-\(sceneResetSeed)")
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Text("Use presets to inspect the model")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .foregroundStyle(.secondary)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(14)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Label("RealityKit prototype extrusion", systemImage: "cube.fill")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .foregroundStyle(.white)
                            .background(.black.opacity(0.58), in: Capsule())
                            .padding(14)
                    }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var cameraPresetPicker: some View {
        HStack(spacing: 10) {
            ForEach(FloorplanCameraPreset.allCases) { preset in
                Button {
                    cameraPreset = preset
                    sceneResetSeed += 1
                } label: {
                    Label(preset.title, systemImage: preset.systemImage)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(cameraPreset == preset ? .white : .primary)
                .background {
                    if cameraPreset == preset {
                        Capsule()
                            .fill(Color.accentColor)
                    } else {
                        Capsule()
                            .fill(.thinMaterial)
                    }
                }
            }
        }
    }
}

private struct FloorplanRealityView: View {
    let summary: FloorplanGeometrySummary
    let canvasSize: CGSize
    let cameraPreset: FloorplanCameraPreset
    @State private var preparedScene: PreparedRealityScene?
    @State private var isPreparingScene = false
    @State private var appliedGeometryKey = ""
    @State private var appliedCameraPreset: FloorplanCameraPreset?

    var body: some View {
        RealityView { content in
            configure(content: &content)
        } update: { content in
            configure(content: &content)
        } placeholder: {
            placeholderView
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .task(id: geometryBuildKey) {
            await prepareScene()
        }
    }

    private func configure(content: inout RealityViewContent) {
        guard let preparedScene else {
            if !appliedGeometryKey.isEmpty {
                content.entities.removeAll()
                appliedGeometryKey = ""
                appliedCameraPreset = nil
            }
            return
        }

        if appliedGeometryKey != preparedScene.geometryKey {
            content.entities.replaceAll([preparedScene.anchor])
            appliedGeometryKey = preparedScene.geometryKey
            appliedCameraPreset = nil
        }

        if appliedCameraPreset != cameraPreset {
            preparedScene.root.transform = FloorplanSceneBuilder.presentationTransform(for: canvasSize, preset: cameraPreset)
            appliedCameraPreset = cameraPreset
        }
    }

    @MainActor
    private func prepareScene() async {
        guard preparedScene?.geometryKey != geometryBuildKey else { return }
        preparedScene = nil
        isPreparingScene = true
        let anchor = AnchorEntity(world: .zero)
        let root = FloorplanSceneBuilder.makeRootEntity(summary: summary, canvasSize: canvasSize)
        anchor.addChild(root)
        let scene = PreparedRealityScene(anchor: anchor, root: root, geometryKey: geometryBuildKey)
        preparedScene = scene
        isPreparingScene = false
    }

    private var geometryBuildKey: String {
        let wallSignature = summary.wallSegments.map(\.id).joined(separator: "|")
        let openingSignature = summary.openings.map(\.id).joined(separator: "|")
        let regionSignature = summary.regions.map(\.id).joined(separator: "|")
        return [
            "\(Int(canvasSize.width.rounded()))x\(Int(canvasSize.height.rounded()))",
            wallSignature,
            openingSignature,
            regionSignature,
            "\(summary.wallCoverage)"
        ].joined(separator: "#")
    }

    @ViewBuilder
    private var placeholderView: some View {
        if isPreparingScene {
            ProgressView("Building 3D preview...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.secondary.opacity(0.08))
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.secondary.opacity(0.08))
        }
    }
}

private struct PreparedRealityScene {
    let anchor: AnchorEntity
    let root: Entity
    let geometryKey: String
}
