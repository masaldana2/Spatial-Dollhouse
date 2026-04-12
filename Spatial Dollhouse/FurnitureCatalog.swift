//
//  FurnitureCatalog.swift
//  Spatial Dollhouse
//

import Foundation

struct FurnitureCatalogItem: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let entityName: String

    static let all: [FurnitureCatalogItem] = [
        .init(id: "boisvert_chair", displayName: "Boisvert Chair", entityName: "boisvert_chair"),
        .init(id: "chair_JIMI", displayName: "Chair JIMI", entityName: "chair_JIMI"),
        .init(id: "mykonos_chair", displayName: "Mykonos Chair", entityName: "mykonos_chair"),
        .init(id: "myrick_chair", displayName: "Myrick Chair", entityName: "myrick_chair"),
        .init(id: "table_AGAMA", displayName: "Table AGAMA", entityName: "table_AGAMA"),
        .init(id: "table_Crueso", displayName: "Table Crueso", entityName: "table_Crueso")
    ]

    static func named(_ entityName: String) -> FurnitureCatalogItem? {
        all.first { $0.entityName == entityName }
    }
}
