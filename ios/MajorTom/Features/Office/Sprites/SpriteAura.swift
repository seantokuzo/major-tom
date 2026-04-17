import SpriteKit

// MARK: - Sprite Aura (Wave 5)

/// A soft-glow ring that sits UNDER an agent sprite, colored per canonical role.
///
/// Layering priority (AgentSprite coordinates):
///   1. Green "unread /btw response" glow (highest — added on top of role aura)
///   2. Role aura (shown while the sprite is `.working` and no unread response)
///   3. Nothing (default idle / celebrating / leaving states)
///
/// The aura renders as three concentric `SKShapeNode` circles with decreasing
/// alpha to fake a gaussian-style glow without the runtime cost of a CIFilter
/// effect node. Multi-layer alpha stacking is cheap on modern iPhones and
/// survives `scene.isPaused` just fine.
final class SpriteAura: SKNode {

    /// The canonical role this aura is colored for (tracked so callers can
    /// decide whether to rebuild on role updates).
    private(set) var canonicalRole: String?

    init(canonicalRole: String?, radius: CGFloat) {
        self.canonicalRole = canonicalRole
        super.init()
        build(radius: radius, color: RoleMapper.color(forCanonicalRole: canonicalRole))
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Build

    private func build(radius: CGFloat, color: UIColor) {
        // Outer — largest, softest
        let outer = SKShapeNode(circleOfRadius: radius)
        outer.fillColor = color
        outer.strokeColor = .clear
        outer.alpha = 0.15
        outer.zPosition = 0
        addChild(outer)

        // Mid — medium size, medium alpha
        let mid = SKShapeNode(circleOfRadius: radius * 0.75)
        mid.fillColor = color
        mid.strokeColor = .clear
        mid.alpha = 0.25
        mid.zPosition = 1
        addChild(mid)

        // Inner — tight, most saturated
        let inner = SKShapeNode(circleOfRadius: radius * 0.5)
        inner.fillColor = color
        inner.strokeColor = color.withAlphaComponent(0.4)
        inner.lineWidth = 1
        inner.alpha = 0.4
        inner.zPosition = 2
        addChild(inner)

        // Start invisible so callers can fade in
        self.alpha = 0
    }

    // MARK: - Animations

    /// Fade the aura in (call after adding to parent).
    func fadeIn(duration: TimeInterval = 0.25) {
        removeAction(forKey: "auraFade")
        run(SKAction.fadeAlpha(to: 1.0, duration: duration), withKey: "auraFade")
    }

    /// Fade out and remove from parent when complete.
    func fadeOutAndRemove(duration: TimeInterval = 0.25) {
        removeAction(forKey: "auraFade")
        let fade = SKAction.fadeOut(withDuration: duration)
        run(SKAction.sequence([fade, SKAction.removeFromParent()]), withKey: "auraFade")
    }
}
