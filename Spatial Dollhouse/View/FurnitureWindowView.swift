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

            FurniturePaletteView()
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 520)
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
