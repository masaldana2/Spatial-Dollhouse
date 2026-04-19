//
//  AppModel.swift
//  Spatial-Dollhouse
//
//  Created by Dario Suarez on 14/04/2026.
//

import SwiftUI

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed
    var immersiveProject: ProjectSummary?
    var immersiveLoadErrorMessage: String?
    var isImmersiveModelLoading = false
}
