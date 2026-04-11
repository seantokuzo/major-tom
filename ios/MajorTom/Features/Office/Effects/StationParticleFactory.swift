import SpriteKit
import UIKit

// MARK: - Station Particle Factory

/// Creates GPU-accelerated particle emitters for the space station.
/// All effects are programmatic — no .sks files needed.
enum StationParticleFactory {

    // MARK: - Shared Textures

    /// Small circular dot texture for star/dust particles.
    private static let dotTexture: SKTexture = {
        let size = 8
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
        }
        return SKTexture(image: image)
    }()

    /// Soft glow texture for nebula particles.
    private static let glowTexture: SKTexture = {
        let size = 32
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { ctx in
            let center = CGPoint(x: size / 2, y: size / 2)
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: center, startRadius: 0,
                endCenter: center, endRadius: CGFloat(size / 2),
                options: .drawsAfterEndLocation
            )
        }
        return SKTexture(image: image)
    }()

    // MARK: - Starfield (Behind Windows)

    /// Distant star layer — tiny dots, very slow drift left.
    static func starFieldFar(size: CGSize) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = dotTexture
        emitter.particleBirthRate = 20
        emitter.particleLifetime = 15
        emitter.particleLifetimeRange = 5

        emitter.particleColor = StationPalette.starWhite
        emitter.particleColorBlendFactor = 1.0
        emitter.particleAlpha = 0.5
        emitter.particleAlphaRange = 0.3

        emitter.particleScale = 0.15
        emitter.particleScaleRange = 0.05

        // Slow drift leftward (station rotation feel)
        emitter.particleSpeed = 3
        emitter.particleSpeedRange = 2
        emitter.emissionAngle = .pi

        emitter.particlePositionRange = CGVector(dx: size.width, dy: size.height)
        emitter.zPosition = -98

        return emitter
    }

    /// Near star layer — slightly larger, faster drift for parallax.
    static func starFieldNear(size: CGSize) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = dotTexture
        emitter.particleBirthRate = 10
        emitter.particleLifetime = 10
        emitter.particleLifetimeRange = 3

        emitter.particleColor = StationPalette.starWhite
        emitter.particleColorBlendFactor = 1.0
        emitter.particleAlpha = 0.7
        emitter.particleAlphaRange = 0.2

        emitter.particleScale = 0.25
        emitter.particleScaleRange = 0.1

        // Faster parallax drift
        emitter.particleSpeed = 8
        emitter.particleSpeedRange = 3
        emitter.emissionAngle = .pi

        emitter.particlePositionRange = CGVector(dx: size.width, dy: size.height)
        emitter.zPosition = -96

        return emitter
    }

    /// Nebula glow — large soft colored blobs, barely moving.
    static func nebulaGlow(size: CGSize) -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = glowTexture
        emitter.particleBirthRate = 1.5
        emitter.particleLifetime = 20
        emitter.particleLifetimeRange = 8

        emitter.particleColor = StationPalette.nebulaBlue
        emitter.particleColorBlendFactor = 1.0
        emitter.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [
                StationPalette.nebulaBlue,
                StationPalette.nebulaPink,
                StationPalette.nebulaTeal,
                StationPalette.nebulaBlue,
            ],
            times: [0, 0.33, 0.66, 1.0]
        )
        emitter.particleAlpha = 0.08
        emitter.particleAlphaRange = 0.04
        emitter.particleAlphaSpeed = -0.003

        emitter.particleScale = 2.0
        emitter.particleScaleRange = 1.0

        // Nearly stationary
        emitter.particleSpeed = 1
        emitter.particleSpeedRange = 1
        emitter.emissionAngle = .pi
        emitter.emissionAngleRange = .pi * 2

        emitter.particlePositionRange = CGVector(dx: size.width, dy: size.height)
        emitter.particleBlendMode = .add
        emitter.zPosition = -99

        return emitter
    }

    // MARK: - Ambient Station Effects

    /// Corridor dust — ultra-faint floating specks with random drift.
    static func corridorDust() -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = dotTexture
        emitter.particleBirthRate = 4
        emitter.particleLifetime = 8
        emitter.particleLifetimeRange = 4

        emitter.particleColor = StationPalette.wallTrim
        emitter.particleColorBlendFactor = 1.0
        emitter.particleAlpha = 0.12
        emitter.particleAlphaRange = 0.06
        emitter.particleAlphaSpeed = -0.01

        emitter.particleScale = 0.15
        emitter.particleScaleRange = 0.05

        // Gentle random drift
        emitter.particleSpeed = 2
        emitter.particleSpeedRange = 2
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi * 2

        emitter.particlePositionRange = CGVector(dx: 800, dy: 600)
        emitter.zPosition = 4

        return emitter
    }

    /// Console sparks — occasional tiny spark at workstations.
    static func consoleSparks() -> SKEmitterNode {
        let emitter = SKEmitterNode()
        emitter.particleTexture = dotTexture
        emitter.particleBirthRate = 0.3
        emitter.particleLifetime = 0.5
        emitter.particleLifetimeRange = 0.2

        emitter.particleColor = StationPalette.consoleCyan
        emitter.particleColorBlendFactor = 1.0
        emitter.particleAlpha = 0.8
        emitter.particleAlphaRange = 0.2
        emitter.particleAlphaSpeed = -1.5

        emitter.particleScale = 0.15
        emitter.particleScaleRange = 0.05

        // Sparks upward
        emitter.particleSpeed = 15
        emitter.particleSpeedRange = 10
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi / 3
        emitter.yAcceleration = -20

        emitter.particlePositionRange = CGVector(dx: 20, dy: 4)
        emitter.particleBlendMode = .add
        emitter.zPosition = 7

        return emitter
    }
}
