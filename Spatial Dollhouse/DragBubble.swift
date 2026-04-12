//
//  DragBubble.swift
//  Spatial Dollhouse
//

import Foundation
import QuartzCore
import RealityKit
import UIKit
import AVFoundation

@MainActor
final class DragBubble {
    private(set) var entity: ModelEntity?
    private var wobbleTask: Task<Void, Never>?
    private var popCleanupTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var popAudioPlayer: AVAudioPlayer?

    func ensureAttached(to root: Entity) -> ModelEntity {
        if let existing = entity {
            if existing.parent == nil {
                root.addChild(existing)
            }
            startWobbleIfNeeded(for: existing)
            return existing
        }

        let bubble = ModelEntity(
            mesh: MeshResource.generateSphere(radius: 1.5),
            materials: [makeBubbleMaterial()]
        )
        bubble.name = "DragBubbleSphere"
        root.addChild(bubble)
        entity = bubble
        startWobbleIfNeeded(for: bubble)
        return bubble
    }

    func remove() {
        wobbleTask?.cancel()
        wobbleTask = nil

        if let bubble = entity, let parent = bubble.parent {
            playPopSound()
            let bubbleWorldTransform = bubble.transformMatrix(relativeTo: nil)
            spawnPopEffect(in: parent, worldTransform: bubbleWorldTransform)
            bubble.removeFromParent()
        }

        entity = nil
    }

    private func spawnPopEffect(in parent: Entity, worldTransform: simd_float4x4) {
        let popAnchor = Entity()
        popAnchor.name = "DragBubblePopParticles"
        parent.addChild(popAnchor)
        popAnchor.setTransformMatrix(worldTransform, relativeTo: nil)

        var popEmitter = ParticleEmitterComponent()
        popEmitter.timing = .once(emit: .init(duration: 0.045))
        popEmitter.emitterShape = .sphere
        popEmitter.birthLocation = .surface
        popEmitter.birthDirection = .normal
        popEmitter.emitterShapeSize = SIMD3<Float>(repeating: 0.12)
        popEmitter.burstCount = 44
        popEmitter.burstCountVariation = 12
        popEmitter.speed = 0.5
        popEmitter.speedVariation = 0.15
        popEmitter.emissionDirection = [0, 1, 0]
        popEmitter.radialAmount = 1.0
        popEmitter.mainEmitter.spreadingAngle = 360.0
        popEmitter.mainEmitter.lifeSpan = 0.5
        popEmitter.mainEmitter.lifeSpanVariation = 0.20
        popEmitter.mainEmitter.size = 0.004
        popEmitter.mainEmitter.sizeVariation = 0.0015
        popEmitter.mainEmitter.stretchFactor = 9.0
        popEmitter.mainEmitter.opacityCurve = .easeFadeOut
        popEmitter.mainEmitter.acceleration = [0, 0, 0]
        popEmitter.mainEmitter.color = .evolving(
            start: .random(
                a: .init(red: 0.88, green: 0.95, blue: 1.0, alpha: 0.95),
                b: .init(red: 0.68, green: 0.86, blue: 1.0, alpha: 0.95)
            ),
            end: .single(.init(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.0))
        )

        popAnchor.components.set(popEmitter)

        let key = ObjectIdentifier(popAnchor)
        popCleanupTasks[key]?.cancel()
        popCleanupTasks[key] = Task { @MainActor [weak self, weak popAnchor] in
            defer { self?.popCleanupTasks[key] = nil }
            try? await Task.sleep(nanoseconds: 2_300_000_000)
            popAnchor?.removeFromParent()
        }
    }

    private func makeBubbleMaterial() -> PhysicallyBasedMaterial {
        var bubble = PhysicallyBasedMaterial()
        bubble.baseColor = .init(tint: .init(red: 0.88, green: 0.95, blue: 1.0, alpha: 1.0))
        bubble.blending = .transparent(opacity: 0.08)
        bubble.roughness = 0.04
        bubble.metallic = 0.0
        bubble.specular = 1.0
        bubble.clearcoat = 1.0
        bubble.clearcoatRoughness = 0.03
        bubble.emissiveColor = .init(color: .init(red: 0.68, green: 0.86, blue: 1.0, alpha: 1.0))
        bubble.emissiveIntensity = 0.03
        bubble.faceCulling = .none
        return bubble
    }

    private func playPopSound() {
        do {
            if popAudioPlayer == nil {
                guard let soundURL = Bundle.main.url(
                    forResource: "Light Click B",
                    withExtension: "wav",
                    subdirectory: "Resources/Sounds"
                ) ?? Bundle.main.url(
                    forResource: "Light Click B",
                    withExtension: "wav"
                ) else {
                    print("Pop sound missing from bundle: Light Click B.wav")
                    return
                }

                popAudioPlayer = try AVAudioPlayer(contentsOf: soundURL)
                popAudioPlayer?.volume = 0.35
                popAudioPlayer?.prepareToPlay()
            }

            popAudioPlayer?.currentTime = 0
            popAudioPlayer?.play()
        } catch {
            print("Failed to play bubble pop sound: \(error.localizedDescription)")
        }
    }

    private func startWobbleIfNeeded(for sphere: ModelEntity) {
        guard wobbleTask == nil else { return }

        let baseScale = sphere.scale
        let startTime = CACurrentMediaTime()

        wobbleTask = Task { @MainActor [weak self, weak sphere] in
            while !Task.isCancelled {
                guard let self, let sphere else { break }
                if self.entity !== sphere { break }

                let t = Float(CACurrentMediaTime() - startTime)
                let x = 1.0 + (0.10 * sin(t * 2.8))
                let y = 1.0 + (0.08 * sin((t * 3.4) + 1.2))
                let z = 1.0 + (0.12 * sin((t * 2.2) + 2.1))

                sphere.scale = SIMD3<Float>(
                    baseScale.x * x,
                    baseScale.y * y,
                    baseScale.z * z
                )
                sphere.orientation = simd_quatf(
                    angle: 0.08 * sin(t * 2.0),
                    axis: [0, 1, 0]
                )

                try? await Task.sleep(nanoseconds: 16_000_000)
            }

            self?.wobbleTask = nil
        }
    }
}
