//
//  ContentView.swift
//  Spatial Dollhouse
//
//  Created by Miguel Saldana on 4/3/26.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    @State private var isImporterPresented = false
    @State private var importError: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Spatial Dollhouse")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Load a color-coded floorplan and open immersive mode to generate 3D walls, doors, and windows.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            legend

            GroupBox("Current Floorplan") {
                VStack(spacing: 12) {
                    if let previewImage = appModel.previewImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Text(appModel.activeFloorplanLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 12) {
                Button("Choose Floorplan Image") {
                    isImporterPresented = true
                }

                Button("Use Bundled Test Image") {
                    appModel.resetToBundledFloorplan()
                    importError = nil
                }

                Spacer()
            }

            if let importError {
                Text(importError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ToggleImmersiveSpaceButton()
        }
        .padding(28)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        try appModel.loadFloorplan(from: url)
                        importError = nil
                    } catch {
                        importError = "Could not load image: \(error.localizedDescription)"
                    }

                case .failure(let error):
                    importError = "Could not pick image: \(error.localizedDescription)"
            }
        }
    }

    private var legend: some View {
        GroupBox("Legend") {
            HStack(spacing: 18) {
                legendItem(color: .red, label: "Walls")
                legendItem(color: .green, label: "Doors")
                legendItem(color: .blue, label: "Windows")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 24, height: 14)
            Text(label)
                .font(.subheadline)
        }
    }
}
//
//#Preview(windowStyle: .automatic) {
//    ContentView()
//        .environment(AppModel())
//}
