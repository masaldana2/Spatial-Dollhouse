//
//  FurnitureWindowView.swift
//  Spatial Dollhouse
//

import SwiftUI

struct FurnitureWindowView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Furniture Menu")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Drag a furniture card into immersive space to place it on the floor.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            FurniturePaletteView()
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 520)
    }
}

#Preview {
    FurnitureWindowView()
}
