import SpriteKit

// MARK: - Agent Sprite

/// Placeholder sprite for an agent character in the office scene.
/// Uses a colored rectangle with a name label, differentiated by CharacterType.
/// Will be replaced with pixel art sprites in a future phase.
final class AgentSprite: SKSpriteNode {

    /// The agent ID this sprite represents (used for tap-to-inspect).
    let agentId: String

    /// The character type determines the sprite color.
    let characterType: CharacterType

    /// The name label node displayed above the sprite.
    private let nameLabel: SKLabelNode

    /// Status indicator dot below the sprite.
    private let statusDot: SKShapeNode

    // MARK: - Initialization

    init(agentId: String, name: String, characterType: CharacterType) {
        self.agentId = agentId
        self.characterType = characterType

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

        // Placeholder colored rectangle (32x32)
        let config = CharacterCatalog.config(for: characterType)
        let spriteColor = SKColor(
            red: CGFloat(config.spriteColor.components.red),
            green: CGFloat(config.spriteColor.components.green),
            blue: CGFloat(config.spriteColor.components.blue),
            alpha: 1.0
        )

        super.init(texture: nil, color: spriteColor, size: CGSize(width: 32, height: 32))

        self.name = "agent_\(agentId)"
        self.isUserInteractionEnabled = true

        // Position label above sprite
        nameLabel.position = CGPoint(x: 0, y: 20)
        addChild(nameLabel)

        // Position status dot below sprite
        statusDot.position = CGPoint(x: 0, y: -22)
        addChild(statusDot)

        // Dog characters get a slightly different shape (wider, shorter)
        if isDog {
            self.size = CGSize(width: 36, height: 24)
        }

        // Dachshund is even more elongated
        if characterType == .dachshund {
            self.size = CGSize(width: 44, height: 20)
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Properties

    var isDog: Bool {
        switch characterType {
        case .dachshund, .cattleDog, .schnauzerBlack, .schnauzerPepper:
            return true
        default:
            return false
        }
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

// MARK: - SwiftUI Color → Components Helper

extension Color {
    /// Extract RGB components from a SwiftUI Color.
    /// Falls back to gray if extraction fails.
    var components: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        // Use UIColor bridge to get components
        let uiColor = UIColor(self)
        var r: CGFloat = 0.5
        var g: CGFloat = 0.5
        var b: CGFloat = 0.5
        var a: CGFloat = 1.0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}
