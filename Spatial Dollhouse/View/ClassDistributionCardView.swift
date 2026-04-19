import SwiftUI

struct ClassDistributionCardView: View {
    let distribution: [FloorplanClassDistribution]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Class Distribution")
                .font(.headline)

            if distribution.isEmpty {
                ContentUnavailableView(
                    "No class map yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Run analysis to inspect the pixel distribution per class.")
                )
                .frame(maxWidth: .infinity)
                .frame(minHeight: 180)
            } else {
                ForEach(distribution) { item in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(color(for: item.classID))
                            .frame(width: 10, height: 10)

                        Text(item.name)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("\(Int((item.percentage * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.primary)

                        Text("\(item.pixelCount)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func color(for classID: Int) -> Color {
        SegmentationLegendItem.defaults.first(where: { $0.id == classID })?.color ?? .secondary
    }
}
