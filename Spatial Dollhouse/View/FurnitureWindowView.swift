//
//  FurnitureWindowView.swift
//  Spatial Dollhouse
//

import SwiftUI

struct FurnitureWindowView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Furniture Menu")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("Drag a furniture card into immersive space to place it on the floor.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Close Immersive") {
                    closeImmersive()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appModel.immersiveSpaceState != .open)
            }

            floorplanControls

            FurniturePaletteView()
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 520)
    }

    private var floorplanControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Floorplan")
                        .font(.headline)

                    Text("Move and scale")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                xzPanControls

                Divider()
                    .frame(height: 58)

                yAxisControls
            }

            HStack(spacing: 10) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                Slider(value: floorplanScaleBinding, in: floorplanScaleRange)
                    .accessibilityLabel("Floorplan scale")
                    .help("Floorplan scale")

                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                Text(floorplanScalePercentage)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.secondary.opacity(0.22), lineWidth: 1)
        )
        .disabled(appModel.immersiveSpaceState != .open)
    }

    private var xzPanControls: some View {
        VStack(spacing: 4) {
            floorplanButton(
                systemName: "arrow.up",
                accessibilityLabel: "Pan floorplan forward"
            ) {
                appModel.panFloorplan(.up)
            }

            HStack(spacing: 4) {
                floorplanButton(
                    systemName: "arrow.left",
                    accessibilityLabel: "Pan floorplan left"
                ) {
                    appModel.panFloorplan(.left)
                }

                floorplanButton(
                    systemName: "arrow.down",
                    accessibilityLabel: "Pan floorplan backward"
                ) {
                    appModel.panFloorplan(.down)
                }

                floorplanButton(
                    systemName: "arrow.right",
                    accessibilityLabel: "Pan floorplan right"
                ) {
                    appModel.panFloorplan(.right)
                }
            }
        }
    }

    private var yAxisControls: some View {
        VStack(spacing: 4) {
            floorplanButton(
                systemName: "arrow.up.to.line",
                accessibilityLabel: "Raise floorplan"
            ) {
                appModel.panFloorplan(.yUp)
            }

            floorplanButton(
                systemName: "arrow.down.to.line",
                accessibilityLabel: "Lower floorplan"
            ) {
                appModel.panFloorplan(.yDown)
            }
        }
    }

    private var floorplanScaleBinding: Binding<Double> {
        Binding {
            Double(appModel.floorplanScale)
        } set: { scale in
            appModel.setFloorplanScale(Float(scale))
        }
    }

    private var floorplanScaleRange: ClosedRange<Double> {
        Double(appModel.floorplanScaleRange.lowerBound)...Double(appModel.floorplanScaleRange.upperBound)
    }

    private var floorplanScalePercentage: String {
        "\(Int((appModel.floorplanScale * 100).rounded()))%"
    }

    private func floorplanButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }

    private func closeImmersive() {
        guard appModel.immersiveSpaceState == .open else { return }

        Task { @MainActor in
            appModel.immersiveSpaceState = .inTransition
            await dismissImmersiveSpace()
            dismissWindow(id: appModel.furnitureWindowID)
        }
    }
}

#Preview {
    FurnitureWindowView()
}
