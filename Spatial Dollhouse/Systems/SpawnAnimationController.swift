//
//  SpawnAnimationController.swift
//  Spatial Dollhouse
//

import Foundation
import RealityKit

enum SpawnAnimationController {
    private static let dropHeight: Float = 10.0
    private static let baseDelay: TimeInterval = 0.04
    private static let delayBetweenEntities: TimeInterval = 0.07
    private static let fallDuration: TimeInterval = 0.45
    private static let fadeStepCount = 12

    static func animateIfNeeded(_ entity: Entity) {
        guard let spawn = entity.components[SpawnAnimationComponent.self] else { return }

        let parent = entity.parent
        let finalTransform = entity.transform
        var startTransform = finalTransform
        startTransform.translation.y += dropHeight

        entity.transform = startTransform
        entity.components.set(OpacityComponent(opacity: 0))
        entity.isEnabled = false

        let delay = baseDelay + (Double(spawn.sequenceIndex) * delayBetweenEntities)
        let duration = fallDuration

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard entity.parent != nil else { return }

            entity.isEnabled = true
            fadeIn(entity, duration: duration)
            entity.move(
                to: finalTransform,
                relativeTo: parent,
                duration: duration,
                timingFunction: .easeIn
            )
            entity.components.remove(SpawnAnimationComponent.self)
        }
    }

    private static func fadeIn(_ entity: Entity, duration: TimeInterval) {
        let clampedStepCount = max(fadeStepCount, 1)
        let stepDuration = duration / Double(clampedStepCount)

        for step in 1...clampedStepCount {
            let opacity = Float(step) / Float(clampedStepCount)
            let stepDelay = stepDuration * Double(step)

            DispatchQueue.main.asyncAfter(deadline: .now() + stepDelay) {
                guard entity.parent != nil else { return }
                entity.components.set(OpacityComponent(opacity: opacity))
            }
        }
    }
}
