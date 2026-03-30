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

    /// Mood tint overlay (colored circle behind the sprite).
    private let moodTintNode: SKShapeNode

    /// Speech bubble label node for mood quips.
    private let speechBubble: SKLabelNode

    /// Background for the speech bubble (mutable — updated on each showSpeechBubble call).
    private var speechBubbleBG: SKShapeNode

    /// Current mood for this agent.
    private(set) var currentMood: AgentMood = .neutral

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

        // Mood tint overlay — larger circle behind sprite
        moodTintNode = SKShapeNode(circleOfRadius: 20)
        moodTintNode.fillColor = .clear
        moodTintNode.strokeColor = .clear
        moodTintNode.alpha = 0
        moodTintNode.zPosition = -1

        // Speech bubble
        speechBubble = SKLabelNode(fontNamed: "Menlo")
        speechBubble.fontSize = 8
        speechBubble.fontColor = .white
        speechBubble.horizontalAlignmentMode = .center
        speechBubble.verticalAlignmentMode = .center
        speechBubble.alpha = 0

        speechBubbleBG = SKShapeNode(rectOf: CGSize(width: 100, height: 16), cornerRadius: 4)
        speechBubbleBG.fillColor = SKColor(white: 0.1, alpha: 0.85)
        speechBubbleBG.strokeColor = SKColor(white: 0.3, alpha: 0.5)
        speechBubbleBG.lineWidth = 0.5
        speechBubbleBG.alpha = 0

        // Derive sprite size from pixel art's actual bounds
        let artFrame = pixelArt.calculateAccumulatedFrame()
        let spriteSize = CGSize(
            width: max(artFrame.width + 4, 32),
            height: max(artFrame.height + 4, 32)
        )

        super.init(texture: nil, color: .clear, size: spriteSize)

        self.name = "agent_\(agentId)"
        self.isUserInteractionEnabled = true

        // Add mood tint behind everything
        addChild(moodTintNode)

        // Add pixel art centered on sprite
        pixelArt.zPosition = 0
        addChild(pixelArt)

        // Position label above sprite (derived from art frame)
        nameLabel.position = CGPoint(x: 0, y: spriteSize.height / 2 + 4)
        addChild(nameLabel)

        // Position status dot below sprite (derived from art frame)
        statusDot.position = CGPoint(x: 0, y: -(spriteSize.height / 2 + 6))
        addChild(statusDot)

        // Speech bubble above name label
        speechBubbleBG.position = CGPoint(x: 0, y: spriteSize.height / 2 + 20)
        speechBubbleBG.zPosition = 20
        addChild(speechBubbleBG)

        speechBubble.position = CGPoint(x: 0, y: spriteSize.height / 2 + 20)
        speechBubble.zPosition = 21
        addChild(speechBubble)
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
        removeAction(forKey: "station")
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
        removeAction(forKey: "station")
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

    /// Station-specific idle animations.
    func startStationAnimation(stationType: ActivityStationType) {
        removeAction(forKey: "idle")
        removeAction(forKey: "work")
        removeAction(forKey: "station")

        let animation: SKAction

        switch stationType {
        case .pingPong:
            // Side-to-side swinging motion
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 6, y: 0, duration: 0.25),
                SKAction.moveBy(x: -12, y: 0, duration: 0.5),
                SKAction.moveBy(x: 6, y: 0, duration: 0.25),
                SKAction.wait(forDuration: 0.3),
            ]))

        case .coffeeMachine:
            // Slight lean forward (waiting for coffee)
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 0, y: -2, duration: 0.6),
                SKAction.moveBy(x: 0, y: 2, duration: 0.6),
                SKAction.wait(forDuration: 1.5),
            ]))

        case .waterCooler:
            // Gentle sway (chatting at the cooler)
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 2, y: 1, duration: 0.7),
                SKAction.moveBy(x: -4, y: 0, duration: 1.0),
                SKAction.moveBy(x: 2, y: -1, duration: 0.7),
            ]))

        case .arcade:
            // Rapid button mashing
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 1, y: -1, duration: 0.1),
                SKAction.moveBy(x: -2, y: 1, duration: 0.1),
                SKAction.moveBy(x: 1, y: 0, duration: 0.1),
                SKAction.wait(forDuration: 0.2),
            ]))

        case .yoga:
            // Slow breathing motion
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 0, y: 4, duration: 1.5),
                SKAction.moveBy(x: 0, y: -4, duration: 1.5),
            ]))

        case .nap:
            // Very slow bob (sleeping)
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 0, y: 1, duration: 2.0),
                SKAction.moveBy(x: 0, y: -1, duration: 2.0),
            ]))

        case .whiteboard:
            // Drawing motion
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 3, y: 2, duration: 0.3),
                SKAction.moveBy(x: -1, y: -4, duration: 0.4),
                SKAction.moveBy(x: -2, y: 2, duration: 0.3),
                SKAction.wait(forDuration: 0.5),
            ]))
        }

        run(animation, withKey: "station")
    }

    /// Stop all animations.
    func stopAnimations() {
        removeAllActions()
    }

    // MARK: - Mood Visuals

    /// Update the mood state and apply visual changes.
    func updateMood(_ mood: AgentMood) {
        guard mood != currentMood else { return }
        currentMood = mood

        let visuals = mood.visuals

        // Update tint node
        moodTintNode.removeAction(forKey: "moodPulse")

        if visuals.tintOpacity > 0 {
            moodTintNode.fillColor = visuals.tintColor
            moodTintNode.alpha = visuals.tintOpacity

            if visuals.pulse {
                let pulseAction = SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: visuals.tintOpacity * 0.5, duration: Double(.pi / visuals.pulseSpeed)),
                    SKAction.fadeAlpha(to: visuals.tintOpacity, duration: Double(.pi / visuals.pulseSpeed)),
                ]))
                moodTintNode.run(pulseAction, withKey: "moodPulse")
            }
        } else {
            moodTintNode.alpha = 0
        }

        // Apply mood-specific idle animation override
        applyMoodIdleAnimation(mood)
    }

    /// Apply mood-specific idle animation on top of current state.
    private func applyMoodIdleAnimation(_ mood: AgentMood) {
        removeAction(forKey: "moodIdle")

        switch mood {
        case .frustrated:
            // Quick shake
            let shake = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 3, y: 0, duration: 0.08),
                SKAction.moveBy(x: -6, y: 0, duration: 0.08),
                SKAction.moveBy(x: 3, y: 0, duration: 0.08),
                SKAction.wait(forDuration: 1.5),
            ]))
            run(shake, withKey: "moodIdle")

        case .excited:
            // Bounce
            let bounce = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 0, y: 6, duration: 0.15),
                SKAction.moveBy(x: 0, y: -6, duration: 0.15),
                SKAction.wait(forDuration: 0.4),
            ]))
            run(bounce, withKey: "moodIdle")

        case .bored:
            // Slow drift side to side
            let drift = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 4, y: 0, duration: 2.0),
                SKAction.moveBy(x: -4, y: 0, duration: 2.0),
            ]))
            run(drift, withKey: "moodIdle")

        case .focused:
            // Very slight lean-in (barely moving, intense)
            let lean = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 0, y: -1, duration: 1.0),
                SKAction.moveBy(x: 0, y: 1, duration: 1.0),
            ]))
            run(lean, withKey: "moodIdle")

        case .happy, .neutral:
            // No extra animation — default idle is fine
            break
        }
    }

    /// Show a speech bubble with the given text, auto-hiding after duration.
    func showSpeechBubble(_ text: String, duration: TimeInterval = 3.0) {
        speechBubble.text = text
        speechBubbleBG.removeAllActions()
        speechBubble.removeAllActions()

        // Resize background to fit text
        let textWidth = CGFloat(text.count) * 5.5 + 12
        let savedPosition = speechBubbleBG.position
        let savedZPosition = speechBubbleBG.zPosition
        speechBubbleBG.removeFromParent()
        let newBG = SKShapeNode(rectOf: CGSize(width: max(textWidth, 40), height: 16), cornerRadius: 4)
        newBG.fillColor = SKColor(white: 0.1, alpha: 0.85)
        newBG.strokeColor = SKColor(white: 0.3, alpha: 0.5)
        newBG.lineWidth = 0.5
        newBG.position = savedPosition
        newBG.zPosition = savedZPosition
        newBG.alpha = 0
        // Update the mutable reference so subsequent calls manipulate the correct node
        speechBubbleBG = newBG
        addChild(newBG)

        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.2)
        let wait = SKAction.wait(forDuration: duration)
        let fadeOut = SKAction.fadeOut(withDuration: 0.5)
        let sequence = SKAction.sequence([fadeIn, wait, fadeOut])

        speechBubble.run(sequence)
        newBG.run(SKAction.sequence([fadeIn, wait, fadeOut, SKAction.removeFromParent()]))
    }

    /// Trigger a mood-appropriate speech bubble if the mood has quips.
    func showMoodSpeech() {
        guard let text = currentMood.pickSpeech() else { return }
        showSpeechBubble(text)
    }

    // MARK: - Touch Handling

    /// Tap detection — forwards to the scene for agent selection.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let scene = scene as? OfficeScene else { return }
        scene.agentTapped(agentId: agentId)
    }
}
