//
//  FloorplanDollhouseBuilderError.swift
//  Spatial Dollhouse
//

import Foundation

enum FloorplanDollhouseBuilderError: LocalizedError {
    case parseFailure
    case noWallsDetected

    var errorDescription: String? {
        switch self {
            case .parseFailure:
                return "The floorplan image could not be parsed."
            case .noWallsDetected:
                return "No wall pixels were detected. Check that walls are colored red."
        }
    }
}
