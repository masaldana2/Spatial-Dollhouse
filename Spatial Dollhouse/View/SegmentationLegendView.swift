import SwiftUI

struct SegmentationLegendView: View {
    let items: [SegmentationLegendItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Legend")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(item.color)
                            .frame(width: 16, height: 16)
                        Text(item.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
