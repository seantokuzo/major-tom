import SpriteKit
import UIKit

// MARK: - Agent Sprite

/// Sprite for an agent character in the office scene.
/// Uses programmatic pixel art built from small colored nodes, differentiated by CharacterType.
final class AgentSprite: SKSpriteNode {

    /// The agent ID this sprite represents (used for tap-to-inspect).
    let agentId: String

    /// The character type determines the pixel art appearance.
    let characterType: CharacterType

    /// The pixel art node tree (child of this sprite).
    private let pixelArt: SKNode

    /// The name label node displayed above the sprite.
    private let nameLabel: SKLabelNode

    /// Status indicator dot below the sprite.
    private let statusDot: SKShapeNode

    /// Dog character types for convenience.
    private static let dogTypes: Set<CharacterType> = [
        .dachshund, .cattleDog, .schnauzerBlack, .schnauzerPepper,
    ]

    /// Cold indicator shown when dachshund wants a blanket (snowflake emoji).
    private var coldIndicator: SKLabelNode?

    /// Blanket overlay shown when dachshund has a blanket.
    private var blanketOverlay: SKSpriteNode?

    /// Whether the blanket is currently shown.
    private(set) var isBlanketShown = false
    // MARK: - Initialization

    init(agentId: String, name: String, characterType: CharacterType) {
        self.agentId = agentId
        self.characterType = characterType

        // Build pixel art for this character
        pixelArt = PixelArtBuilder.build(for: characterType)

        // Name label
        nameLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        nameLabel.fontSize = 9
        nameLabel.fontColor = .white
        nameLabel.text = name
        nameLabel.verticalAlignmentMode = .bottom

        // Status dot
        statusDot = SKShapeNode(circleOfRadius: 3)
        statusDot.fillColor = .gray
        statusDot.strokeColor = .clear

        // Use a clear base node — the pixel art child provides the visuals
        let spriteSize: CGSize
        if characterType == .dachshund {
            spriteSize = CGSize(width: 44, height: 20)
        } else if Self.dogTypes.contains(characterType) {
            spriteSize = CGSize(width: 36, height: 24)
        } else {
            spriteSize = CGSize(width: 32, height: 32)
        }

        super.init(texture: nil, color: .clear, size: spriteSize)

        self.name = "agent_\(agentId)"
        self.isUserInteractionEnabled = true

        // Add pixel art centered on sprite
        pixelArt.zPosition = 0
        addChild(pixelArt)

        // Position label above sprite
        nameLabel.position = CGPoint(x: 0, y: spriteSize.height / 2 + 4)
        addChild(nameLabel)

        // Position status dot below sprite
        statusDot.position = CGPoint(x: 0, y: -(spriteSize.height / 2 + 6))
        addChild(statusDot)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Properties

    var isDog: Bool {
        Self.dogTypes.contains(characterType)
    }

    // MARK: - Update Methods

    /// Update the name label text.
    func updateName(_ name: String) {
        nameLabel.text = name
    }

    /// Update the status indicator color based on agent status.
    func updateStatus(_ status: AgentStatus) {
        switch status {
        case .spawning:
            statusDot.fillColor = SKColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
        case .walking:
            statusDot.fillColor = SKColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1)
        case .working:
            statusDot.fillColor = SKColor(red: 0.3, green: 0.85, blue: 0.45, alpha: 1)
        case .idle:
            statusDot.fillColor = SKColor(red: 0.95, green: 0.75, blue: 0.3, alpha: 1)
        case .celebrating:
            statusDot.fillColor = SKColor(red: 0.95, green: 0.65, blue: 0.25, alpha: 1)
        case .leaving:
            statusDot.fillColor = SKColor(red: 0.7, green: 0.3, blue: 0.3, alpha: 1)
        }
    }

    // MARK: - Movement

    /// Animate movement to a target position.
    /// Simple direct movement — no pathfinding for now.
    func moveTo(position: CGPoint, duration: TimeInterval = 1.0, completion: (() -> Void)? = nil) {
        removeAction(forKey: "move")
        let moveAction = SKAction.move(to: position, duration: duration)
        moveAction.timingMode = .easeInEaseOut

        if let completion {
            let sequence = SKAction.sequence([moveAction, SKAction.run(completion)])
            run(sequence, withKey: "move")
        } else {
            run(moveAction, withKey: "move")
        }
    }

    // MARK: - Animations

    /// Simple idle bobbing animation.
    func startIdleAnimation() {
        removeAction(forKey: "shiver")
        removeAction(forKey: "idle")
        let bob = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 3, duration: 0.8),
            SKAction.moveBy(x: 0, y: -3, duration: 0.8),
        ])
        run(SKAction.repeatForever(bob), withKey: "idle")
    }

    /// Simple working animation (slight shake).
    func startWorkAnimation() {
        removeAction(forKey: "shiver")
        removeAction(forKey: "idle")
        removeAction(forKey: "work")
        let shake = SKAction.sequence([
            SKAction.moveBy(x: 2, y: 0, duration: 0.15),
            SKAction.moveBy(x: -4, y: 0, duration: 0.15),
            SKAction.moveBy(x: 2, y: 0, duration: 0.15),
            SKAction.wait(forDuration: 0.5),
        ])
        run(SKAction.repeatForever(shake), withKey: "work")
    }

    /// Celebration animation (jump + spin).
    func startCelebrationAnimation() {
        removeAllActions()
        let jump = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 20, duration: 0.2),
            SKAction.moveBy(x: 0, y: -20, duration: 0.2),
        ])
        let spin = SKAction.rotate(byAngle: .pi * 2, duration: 0.4)
        let celebrate = SKAction.group([jump, spin])
        run(SKAction.repeat(celebrate, count: 3), withKey: "celebrate")
    }

    /// Gentle shiver animation — slower and more pathetic than work shake.
    /// Used when dachshund is at desk without a blanket.
    func startShiverAnimation() {
        removeAction(forKey: "idle")
        removeAction(forKey: "work")
        removeAction(forKey: "shiver")
        let shiver = SKAction.sequence([
            SKAction.moveBy(x: 1.5, y: 0, duration: 0.1),
            SKAction.moveBy(x: -3, y: 0, duration: 0.1),
            SKAction.moveBy(x: 1.5, y: 0, duration: 0.1),
            SKAction.wait(forDuration: 1.2),
        ])
        run(SKAction.repeatForever(shiver), withKey: "shiver")
    }

    /// Brief happy tail-wag wiggle when blanket is given.
    func playBlanketHappyWiggle() {
        removeAction(forKey: "shiver")
        let wiggle = SKAction.sequence([
            SKAction.rotate(byAngle: 0.15, duration: 0.08),
            SKAction.rotate(byAngle: -0.30, duration: 0.08),
            SKAction.rotate(byAngle: 0.30, duration: 0.08),
            SKAction.rotate(byAngle: -0.30, duration: 0.08),
            SKAction.rotate(byAngle: 0.15, duration: 0.08),
        ])
        run(SKAction.repeat(wiggle, count: 3), withKey: "happyWiggle")
    }

    // MARK: - Blanket Visuals

    /// Show the cold indicator (snowflake) above the sprite.
    func showColdIndicator() {
        guard coldIndicator == nil else { return }
        let label = SKLabelNode(text: "\u{2744}\u{FE0F}")  // ❄️
        label.fontSize = 14
        label.position = CGPoint(x: 0, y: 32)
        label.zPosition = 15
        label.name = "coldIndicator"

        // Gentle pulse so it draws attention
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.2, duration: 0.6),
            SKAction.scale(to: 0.9, duration: 0.6),
        ])
        label.run(SKAction.repeatForever(pulse))

        addChild(label)
        coldIndicator = label
    }

    /// Hide the cold indicator.
    func hideColdIndicator() {
        coldIndicator?.removeFromParent()
        coldIndicator = nil
    }

    /// Show the blanket overlay on the sprite (warm-colored rectangle draped over the dog).
    func showBlanket() {
        guard blanketOverlay == nil else { return }
        isBlanketShown = true

        // Blanket is a warm brown/red rectangle slightly larger than the sprite
        let blanket = SKSpriteNode(
            color: SKColor(red: 0.65, green: 0.25, blue: 0.15, alpha: 0.85),
            size: CGSize(width: size.width + 6, height: size.height * 0.6)
        )
        blanket.position = CGPoint(x: 0, y: -size.height * 0.15)
        blanket.zPosition = 1  // Above sprite body, below name label
        blanket.name = "blanketOverlay"
        addChild(blanket)
        blanketOverlay = blanket

        // Fade-in
        blanket.alpha = 0
        blanket.run(SKAction.fadeIn(withDuration: 0.3))
    }

    /// Remove the blanket overlay.
    func hideBlanket() {
        guard let blanket = blanketOverlay else { return }
        isBlanketShown = false
        blanket.run(SKAction.fadeOut(withDuration: 0.3)) { [weak self] in
            blanket.removeFromParent()
            if self?.blanketOverlay === blanket {
                self?.blanketOverlay = nil
            }
        }
    }

    /// Stop all animations.
    func stopAnimations() {
        removeAllActions()
    }

    // MARK: - Touch Handling

    /// Tap detection — forwards to the scene for agent selection.
    /// If the cold indicator is tapped, gives blanket instead.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let scene = scene as? OfficeScene else { return }
        guard let touch = touches.first else { return }

        // Check if cold indicator was tapped
        let touchLocation = touch.location(in: self)
        if let indicator = coldIndicator, indicator.contains(touchLocation) {
            scene.blanketRequested(agentId: agentId)
            return
        }

        scene.agentTapped(agentId: agentId)
    }
}
