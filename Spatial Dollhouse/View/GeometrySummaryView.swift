import SwiftUI

struct GeometrySummaryView: View {
    let summary: FloorplanGeometrySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Detected Structures")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                MetricTile(title: "Rooms", value: "\(summary.roomCount)")
                MetricTile(title: "Doors", value: "\(summary.doorCount)")
                MetricTile(title: "Windows", value: "\(summary.windowCount)")
                MetricTile(title: "Wall Segments", value: "\(summary.wallSegments.count)")
                MetricTile(title: "Junctions", value: "\(summary.junctions.count)")
                MetricTile(title: "Wall Coverage", value: "\(Int(summary.wallCoverage * 100))%")
            }

            if !summary.wallSegments.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Refined Walls")
                        .font(.subheadline.weight(.semibold))

                    ForEach(summary.wallSegments.prefix(6)) { segment in
                        HStack {
                            Text("\(segment.axis.title) \(segment.id)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(segment.lengthSummary) | t=\(segment.thicknessSummary)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !summary.junctions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Wall Junctions")
                        .font(.subheadline.weight(.semibold))

                    ForEach(summary.junctions.prefix(6)) { junction in
                        HStack {
                            Text(junction.id)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(junction.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !summary.openings.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Anchored Openings")
                        .font(.subheadline.weight(.semibold))

                    ForEach(summary.openings.prefix(6)) { opening in
                        HStack {
                            Text(opening.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(opening.axis.title) | \(opening.anchorSummary)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title3.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
