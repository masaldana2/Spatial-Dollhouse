//
//  FurniturePaletteView.swift
//  Spatial Dollhouse
//

import SwiftUI
import RealityKit
import Spatial

struct FurniturePaletteView: View {
    private let columns = [
        GridItem(.adaptive(minimum: 170), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Drag a furniture card to place it and align it with your palm orientation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(FurnitureCatalogItem.all) { item in
                        FurnitureMenuCard(item: item)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            .padding(18)
        }
    }
}

private struct FurnitureMenuCard: View {
    @Environment(AppModel.self) private var appModel
    @State private var isDraggingFromCard = false

    let item: FurnitureCatalogItem

    var body: some View {
        cardBody
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .immersiveSpace)
                    .onChanged { value in
                        if isDraggingFromCard {
                            appModel.updateFurnitureMenuDrag(
                                at: value.location3D,
                                inputDevicePose: value.inputDevicePose3D
                            )
                        } else {
                            isDraggingFromCard = true
                            appModel.beginFurnitureMenuDrag(
                                named: item.entityName,
                                at: value.location3D,
                                inputDevicePose: value.inputDevicePose3D
                            )
                        }
                    }
                    .onEnded { value in
                        guard isDraggingFromCard else { return }
                        appModel.updateFurnitureMenuDrag(
                            at: value.location3D,
                            inputDevicePose: value.inputDevicePose3D
                        )
                        appModel.endFurnitureMenuDrag()
                        isDraggingFromCard = false
                    }
            )
            .onDisappear {
                guard isDraggingFromCard else { return }
                appModel.endFurnitureMenuDrag()
                isDraggingFromCard = false
            }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            FurnitureRealityPreview(assetName: item.entityName)
                .frame(maxHeight: .infinity)
                .background(.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.headline)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.secondary.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct FurnitureRealityPreview: View {
    let assetName: String
    @State private var didFailToLoad = false
    private let previewTargetExtent: Float = 0.1
    private let previewDepthPadding: Float = 0.14
    private let previewFloorInset: Float = -0.01
    private let debugCubeSize: Float = 0.1

    var body: some View {
        RealityView { content in
            let previewRoot = Entity()
            previewRoot.position = .zero
            content.add(previewRoot)

            Task { @MainActor in
                do {
                    previewRoot.children.removeAll()
                    previewRoot.scale = .one
                    let preview = try await FurnitureSceneRepository.shared.makePreviewFurniture(named: assetName)
                    previewRoot.addChild(preview)
                    fitPreviewRoot(previewRoot)
                    didFailToLoad = false
                } catch {
                    didFailToLoad = true
                    print("Could not render preview for \(assetName): \(error.localizedDescription)")
                }
            }
        }
        .overlay {
            if didFailToLoad {
                Image(systemName: "cube.transparent")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
    }

    private func fitPreviewRoot(_ previewRoot: Entity) {
        let bounds = previewRoot.visualBounds(relativeTo: previewRoot)
        guard !bounds.isEmpty else { return }

        // 1. Calculate and apply the scale
        let maxExtent = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        let scale = previewTargetExtent / max(maxExtent, 0.0001)
        previewRoot.scale = SIMD3<Float>(repeating: scale)

        // 2. Fix: Scale the local bounding box mathematically.
        // (Local bounds don't change when you scale the node itself)
        let scaledCenter = bounds.center * scale
        previewRoot.position = [
            0,
            -bounds.extents.y / 2,
            -scaledCenter.z
        ]
    }
}
