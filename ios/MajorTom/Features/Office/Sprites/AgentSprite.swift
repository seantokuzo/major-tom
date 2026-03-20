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

        // Derive sprite size from pixel art's actual bounds
        let artFrame = pixelArt.calculateAccumulatedFrame()
        let spriteSize = CGSize(
            width: max(artFrame.width + 4, 32),
            height: max(artFrame.height + 4, 32)
        )

        super.init(texture: nil, color: .clear, size: spriteSize)

        self.name = "agent_\(agentId)"
        self.isUserInteractionEnabled = true

        // Add pixel art centered on sprite
        pixelArt.zPosition = 0
        addChild(pixelArt)

        // Position label above sprite (derived from art frame)
        nameLabel.position = CGPoint(x: 0, y: spriteSize.height / 2 + 4)
        addChild(nameLabel)

        // Position status dot below sprite (derived from art frame)
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
        removeAction(forKey: "idle")
        let bob = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 3, duration: 0.8),
            SKAction.moveBy(x: 0, y: -3, duration: 0.8),
        ])
        run(SKAction.repeatForever(bob), withKey: "idle")
    }

    /// Simple working animation (slight shake).
    func startWorkAnimation() {
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

    /// Stop all animations.
    func stopAnimations() {
        removeAllActions()
    }

    // MARK: - Touch Handling

    /// Tap detection — forwards to the scene for agent selection.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let scene = scene as? OfficeScene else { return }
        scene.agentTapped(agentId: agentId)
    }
}
