import Foundation
import simd

enum FloorplanOBJExporter {
    static func writeOBJ(primitives: [FloorplanScenePrimitive], to url: URL) throws {
        var lines: [String] = [
            "# Spatial Dollhouse OBJ export",
            "# Generated from floorplan primitives"
        ]
        var vertexOffset = 1

        for primitive in primitives {
            lines.append("o \(sanitizeObjectName(primitive.name))")
            let vertices = boxVertices(size: primitive.size, center: primitive.position)
            vertices.forEach { vertex in
                lines.append("v \(format(vertex.x)) \(format(vertex.y)) \(format(vertex.z))")
            }

            let faces = [
                [1, 2, 3, 4],
                [5, 8, 7, 6],
                [1, 5, 6, 2],
                [2, 6, 7, 3],
                [3, 7, 8, 4],
                [5, 1, 4, 8]
            ]

            for face in faces {
                let indices = face.map { String(vertexOffset + $0 - 1) }.joined(separator: " ")
                lines.append("f \(indices)")
            }

            vertexOffset += vertices.count
        }

        let contents = lines.joined(separator: "\n") + "\n"
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func boxVertices(size: SIMD3<Float>, center: SIMD3<Float>) -> [SIMD3<Float>] {
        let half = size / 2
        return [
            SIMD3(center.x - half.x, center.y - half.y, center.z - half.z),
            SIMD3(center.x + half.x, center.y - half.y, center.z - half.z),
            SIMD3(center.x + half.x, center.y + half.y, center.z - half.z),
            SIMD3(center.x - half.x, center.y + half.y, center.z - half.z),
            SIMD3(center.x - half.x, center.y - half.y, center.z + half.z),
            SIMD3(center.x + half.x, center.y - half.y, center.z + half.z),
            SIMD3(center.x + half.x, center.y + half.y, center.z + half.z),
            SIMD3(center.x - half.x, center.y + half.y, center.z + half.z)
        ]
    }

    private static func sanitizeObjectName(_ name: String) -> String {
        let allowed = name.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return character
            }
            return "_"
        }
        return String(allowed)
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.6f", value)
    }
}
