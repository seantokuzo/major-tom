import SpriteKit
import UIKit

// MARK: - Helmet Type

/// Helmet overlay variants toggled per station module.
enum HelmetType {
    case none
    case standard   // Safety visor — Engineering, Training Bay
    case eva        // Full space helmet — EVA Bay
}

// MARK: - Emote Type

/// Animated emote icons that float above an agent's head.
enum EmoteType: String {
    case thought      // 💭
    case exclamation  // ❗
    case heart        // ❤️
    case zzz          // 💤
    case wrench       // 🔧
    case star         // ⭐

    var symbol: String {
        switch self {
        case .thought:     return "💭"
        case .exclamation: return "❗"
        case .heart:       return "❤️"
        case .zzz:         return "💤"
        case .wrench:      return "🔧"
        case .star:        return "⭐"
        }
    }
}

// MARK: - Agent Sprite

/// Sprite for an agent character in the space station scene.
/// Uses texture-based rendering from the CrewSprites atlas with directional facing.
final class AgentSprite: SKSpriteNode {

    /// The agent ID this sprite represents (used for tap-to-inspect).
    let agentId: String

    /// The character type determines the sprite texture set.
    let characterType: CharacterType

    /// Green "unread /btw response" glow — set when an unread sprite.response
    /// is waiting. Overrides default working auras.
    private var unreadGlowNode: SKNode?

    /// Role-colored aura shown while the sprite is working (Wave 5).
    /// Hidden when the green unread glow is active; restored when it clears.
    private var roleAuraNode: SpriteAura?

    /// Last canonicalRole applied to the role aura — used to decide whether
    /// to rebuild on role updates.
    private var currentRoleForAura: String?

    /// Whether a role aura is currently "requested" by the scene — we use
    /// this to restore the aura when the green unread glow is cleared.
    private var roleAuraRequested: Bool = false

    /// Humanized tool-event bubble node (Wave 5). Mutable so each tool.start
    /// can swap the label in-place without re-adding a bubble node.
    private var toolBubbleBG: SKShapeNode?
    private var toolBubbleLabel: SKLabelNode?

    /// Mini progress indicator label shown under the sprite while working (Wave 5).
    private var progressLabel: SKLabelNode?

    /// The texture-based crew sprite body node.
    private let bodySprite: SKSpriteNode

    /// Current facing direction.
    private(set) var facing: FacingDirection = .front

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

    /// Current helmet type.
    private(set) var currentHelmet: HelmetType = .none

    /// The helmet overlay node (nil when no helmet).
    private var helmetNode: SKNode?

    /// The module this agent is currently in (for helmet logic).
    private(set) var currentModule: ModuleType?

    /// Dog character types for convenience.
    private static let dogTypes: Set<CharacterType> = [
        .elvis, .senor, .steve, .esteban, .hoku, .kai,
    ]

    // MARK: - Initialization

    init(agentId: String, name: String, characterType: CharacterType) {
        self.agentId = agentId
        self.characterType = characterType

        // Build texture-based crew sprite
        bodySprite = CrewSpriteBuilder.build(for: characterType, facing: .front)

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
        moodTintNode = SKShapeNode(circleOfRadius: 28)
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

        let spriteSize = CrewSpriteBuilder.size(for: characterType)

        super.init(texture: nil, color: .clear, size: spriteSize)

        self.name = "agent_\(agentId)"
        self.isUserInteractionEnabled = false

        // Add mood tint behind everything
        addChild(moodTintNode)

        // Add body sprite centered
        bodySprite.zPosition = 0
        addChild(bodySprite)

        // Position label above sprite
        nameLabel.position = CGPoint(x: 0, y: spriteSize.height / 2 + 4)
        addChild(nameLabel)

        // Position status dot below sprite
        statusDot.position = CGPoint(x: 0, y: -(spriteSize.height / 2 + 6))
        addChild(statusDot)

        // Speech bubble above name label
        speechBubbleBG.position = CGPoint(x: 0, y: spriteSize.height / 2 + 20)
        speechBubbleBG.zPosition = 20
        addChild(speechBubbleBG)

        speechBubble.position = CGPoint(x: 0, y: spriteSize.height / 2 + 20)
        speechBubble.zPosition = 21
        addChild(speechBubble)

        // Idle sprites: hide status dot, dim name label
        if agentId.hasPrefix("idle-") {
            statusDot.alpha = 0
            nameLabel.alpha = 0.6
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Properties

    var isIdleSprite: Bool {
        agentId.hasPrefix("idle-")
    }

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
        // Idle pool sprites keep their dot hidden
        if isIdleSprite {
            statusDot.alpha = 0
            return
        }

        statusDot.alpha = 1
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

    // MARK: - Facing Direction

    /// Update the sprite's facing direction and swap the body texture.
    func setFacing(_ direction: FacingDirection) {
        guard direction != facing else { return }
        facing = direction
        CrewSpriteBuilder.updateTexture(bodySprite, type: characterType, facing: direction)
    }

    // MARK: - Movement

    /// Animate movement to a target position.
    /// Updates facing direction based on the movement vector.
    func moveTo(position: CGPoint, duration: TimeInterval = 1.0, completion: (() -> Void)? = nil) {
        removeAction(forKey: "move")

        // Update facing based on movement direction
        let dx = position.x - self.position.x
        let dy = position.y - self.position.y
        if abs(dx) > 1 || abs(dy) > 1 {
            setFacing(FacingDirection.from(dx: dx, dy: dy))
        }

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

    /// Start an animation based on a JSON activity animation ID.
    /// Maps string IDs from Activities.json to specific motion patterns.
    func startActivityAnimation(_ animationID: String) {
        removeAction(forKey: "idle")
        removeAction(forKey: "work")
        removeAction(forKey: "station")
        removeAction(forKey: "activity")

        let animation: SKAction

        switch animationID {
        case "sleeping":
            // Very slow bob (sleeping)
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 0, y: 1, duration: 2.0),
                SKAction.moveBy(x: 0, y: -1, duration: 2.0),
            ]))

        case "sitting":
            // Gentle micro-movement (seated)
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 0.5, y: 0, duration: 1.5),
                SKAction.moveBy(x: -1, y: 0, duration: 2.0),
                SKAction.moveBy(x: 0.5, y: 0, duration: 1.5),
            ]))

        case "exercising":
            // Quick up/down motion
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 0, y: 3, duration: 0.3),
                SKAction.moveBy(x: 0, y: -3, duration: 0.3),
                SKAction.wait(forDuration: 0.2),
            ]))

        case "working":
            // Focused lean-in with small gestures
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 1, y: -1, duration: 0.4),
                SKAction.moveBy(x: -2, y: 1, duration: 0.5),
                SKAction.moveBy(x: 1, y: 0, duration: 0.4),
                SKAction.wait(forDuration: 0.8),
            ]))

        case "sniffing":
            // Nose-to-ground bobbing
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 3, y: -2, duration: 0.4),
                SKAction.moveBy(x: -6, y: 0, duration: 0.6),
                SKAction.moveBy(x: 3, y: 2, duration: 0.4),
                SKAction.wait(forDuration: 0.3),
            ]))

        case "running":
            // Fast side-to-side (playing/fetching)
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 8, y: 0, duration: 0.3),
                SKAction.moveBy(x: -16, y: 0, duration: 0.6),
                SKAction.moveBy(x: 8, y: 0, duration: 0.3),
                SKAction.wait(forDuration: 0.2),
            ]))

        case "cooking":
            // Busy chopping/stirring motion
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 2, y: -1, duration: 0.2),
                SKAction.moveBy(x: -4, y: 0, duration: 0.25),
                SKAction.moveBy(x: 2, y: 1, duration: 0.2),
                SKAction.wait(forDuration: 0.4),
            ]))

        case "reading":
            // Very still, occasional page-turn lean
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.wait(forDuration: 2.5),
                SKAction.moveBy(x: 0.5, y: -0.5, duration: 0.3),
                SKAction.moveBy(x: -0.5, y: 0.5, duration: 0.3),
            ]))

        case "waiting":
            // Impatient weight-shifting
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 1.5, y: 0, duration: 1.0),
                SKAction.moveBy(x: -3, y: 0, duration: 1.5),
                SKAction.moveBy(x: 1.5, y: 0, duration: 1.0),
                SKAction.wait(forDuration: 0.8),
            ]))

        case "walking":
            // Gentle wandering sway
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 3, y: 1, duration: 0.8),
                SKAction.moveBy(x: -6, y: -2, duration: 1.2),
                SKAction.moveBy(x: 3, y: 1, duration: 0.8),
            ]))

        case "arcade":
            // Rapid button-mashing with excitement
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 1, y: -1, duration: 0.1),
                SKAction.moveBy(x: -2, y: 1, duration: 0.1),
                SKAction.moveBy(x: 1, y: 0, duration: 0.1),
                SKAction.wait(forDuration: 0.15),
            ]))

        default:
            // Generic idle sway fallback
            animation = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 1, y: 0.5, duration: 1.0),
                SKAction.moveBy(x: -2, y: -1, duration: 1.5),
                SKAction.moveBy(x: 1, y: 0.5, duration: 1.0),
            ]))
        }

        run(animation, withKey: "activity")
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

        // Occasionally show a mood-related emote (30% chance on mood change)
        if Double.random(in: 0...1) < 0.3 {
            if let emote = mood.emote {
                showEmote(emote)
            }
        }
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

    // MARK: - Helmet Overlay

    /// Set the helmet type, creating or removing the overlay node.
    func setHelmet(_ type: HelmetType) {
        guard type != currentHelmet else { return }
        currentHelmet = type

        // Remove existing helmet
        helmetNode?.removeFromParent()
        helmetNode = nil

        let spriteSize = CrewSpriteBuilder.size(for: characterType)

        switch type {
        case .none:
            break

        case .standard:
            // Safety visor — small cyan-tinted rounded rect over the top half of the head
            let visor = SKShapeNode(rectOf: CGSize(width: spriteSize.width * 0.6, height: spriteSize.height * 0.3), cornerRadius: 4)
            visor.fillColor = SKColor(red: 0, green: 0.83, blue: 1, alpha: 0.25)
            visor.strokeColor = SKColor(red: 0, green: 0.83, blue: 1, alpha: 0.6)
            visor.lineWidth = 1
            visor.position = CGPoint(x: 0, y: spriteSize.height * 0.18)
            visor.zPosition = 5
            bodySprite.addChild(visor)
            helmetNode = visor

        case .eva:
            // Full space helmet — dome bubble around the head
            let dome = SKShapeNode(circleOfRadius: spriteSize.width * 0.42)
            dome.fillColor = SKColor(red: 0.7, green: 0.85, blue: 1, alpha: 0.15)
            dome.strokeColor = SKColor(red: 0.7, green: 0.85, blue: 1, alpha: 0.5)
            dome.lineWidth = 1.5
            dome.position = CGPoint(x: 0, y: spriteSize.height * 0.12)
            dome.zPosition = 5
            // Glass reflection highlight
            let reflection = SKShapeNode(ellipseOf: CGSize(width: spriteSize.width * 0.2, height: spriteSize.height * 0.12))
            reflection.fillColor = SKColor(white: 1, alpha: 0.2)
            reflection.strokeColor = .clear
            reflection.position = CGPoint(x: -spriteSize.width * 0.1, y: spriteSize.height * 0.08)
            dome.addChild(reflection)
            bodySprite.addChild(dome)
            helmetNode = dome
        }
    }

    /// Update the helmet based on which module the agent is in.
    func updateModule(_ module: ModuleType?) {
        currentModule = module
        setHelmet(WaypointPathfinder.helmetType(for: module))
    }

    // MARK: - Emote System

    // MARK: - Role Aura (Wave 5)

    /// Show the role-colored aura under the sprite. Hidden while the green
    /// unread-response glow is active; restored when it clears.
    ///
    /// Safe to call repeatedly with the same `canonicalRole` — no-ops when
    /// the current aura already matches. Role changes rebuild the node.
    func showRoleAura(canonicalRole: String?) {
        roleAuraRequested = true
        currentRoleForAura = canonicalRole

        // Green glow suppresses the role aura entirely.
        guard unreadGlowNode == nil else {
            removeRoleAuraNode()
            return
        }

        // No-op if the current aura is already for this role.
        if let existing = roleAuraNode, existing.canonicalRole == canonicalRole {
            return
        }

        // Rebuild: remove any existing role aura first.
        removeRoleAuraNode()

        let spriteSize = CrewSpriteBuilder.size(for: characterType)
        // ~1.3× sprite bounding radius (spec). Sprite is a square frame.
        let radius = max(spriteSize.width, spriteSize.height) * 0.5 * 1.3

        let aura = SpriteAura(canonicalRole: canonicalRole, radius: radius)
        aura.name = "roleAura"
        // Under the body sprite (zPosition 0) but above the floor (no overlap).
        aura.zPosition = -1.0
        addChild(aura)
        aura.fadeIn()
        roleAuraNode = aura
    }

    /// Hide the role aura. Clears both the requested flag and the node so it
    /// won't re-appear until `showRoleAura` is called again.
    func hideRoleAura() {
        roleAuraRequested = false
        currentRoleForAura = nil
        removeRoleAuraNode()
    }

    private func removeRoleAuraNode() {
        guard let aura = roleAuraNode else { return }
        aura.fadeOutAndRemove()
        roleAuraNode = nil
    }

    // MARK: - Unread /btw Response Glow (Wave 4 + Wave 5 priority)

    /// Attach the green "unread /btw response" glow.
    /// Hides any active role aura — it will be restored by `hideUnreadResponseGlow`
    /// if the sprite was still requesting one.
    func showUnreadResponseGlow() {
        guard unreadGlowNode == nil else { return }
        let spriteSize = CrewSpriteBuilder.size(for: characterType)
        let radius = max(spriteSize.width, spriteSize.height) * 0.8

        let glow = SKShapeNode(circleOfRadius: radius)
        glow.fillColor = SKColor(red: 0.25, green: 0.9, blue: 0.45, alpha: 0.35)
        glow.strokeColor = SKColor(red: 0.30, green: 1.0, blue: 0.55, alpha: 0.7)
        glow.lineWidth = 2
        glow.name = "unreadResponseGlow"
        glow.zPosition = -0.5
        glow.alpha = 0

        let fadeIn = SKAction.fadeAlpha(to: 0.85, duration: 0.25)
        let pulse = SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.45, duration: 0.9),
            SKAction.fadeAlpha(to: 0.85, duration: 0.9),
        ]))
        glow.run(SKAction.sequence([fadeIn, pulse]))

        addChild(glow)
        unreadGlowNode = glow

        // Green takes priority — suppress the role aura until the glow clears.
        removeRoleAuraNode()
    }

    /// Remove the unread glow. Restores the role aura if one was previously
    /// requested (i.e. the sprite is still in a working state).
    func hideUnreadResponseGlow() {
        guard let glow = unreadGlowNode else { return }
        glow.removeAllActions()
        glow.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.25),
            SKAction.removeFromParent(),
        ]))
        unreadGlowNode = nil

        // Restore the role aura if the scene still wants it shown.
        if roleAuraRequested {
            showRoleAura(canonicalRole: currentRoleForAura)
        }
    }

    /// Preview a /btw response as a speech bubble over the sprite.
    func showResponsePreviewBubble(_ text: String, duration: TimeInterval = 5.0) {
        showSpeechBubble(text, duration: duration)
    }

    // MARK: - Tool Bubble (Wave 5)

    /// Show or update the humanized tool-event bubble above the sprite.
    /// Auto-hides after `autoHideAfter` seconds as a safety net if the
    /// matching `tool.complete` never arrives.
    func showToolBubble(label: String, autoHideAfter: TimeInterval = 30.0) {
        let spriteSize = CrewSpriteBuilder.size(for: characterType)
        let textWidth = CGFloat(label.count) * 5.5 + 12
        let bubbleWidth = max(textWidth, 50)
        let bubbleY = spriteSize.height / 2 + 36

        if let bg = toolBubbleBG, let lbl = toolBubbleLabel {
            // Fade-swap the text in place so we don't flash a new node.
            lbl.run(SKAction.sequence([
                SKAction.fadeOut(withDuration: 0.1),
                SKAction.run { lbl.text = label },
                SKAction.fadeIn(withDuration: 0.15),
            ]))
            // Resize background to fit new label.
            bg.run(SKAction.run { [weak self, weak bg] in
                guard let bg else { return }
                let parent = bg.parent
                bg.removeFromParent()
                let newBG = SKShapeNode(rectOf: CGSize(width: bubbleWidth, height: 16), cornerRadius: 4)
                newBG.fillColor = SKColor(white: 0.1, alpha: 0.85)
                newBG.strokeColor = SKColor(red: 0.35, green: 0.75, blue: 1.0, alpha: 0.5)
                newBG.lineWidth = 0.5
                newBG.position = CGPoint(x: 0, y: bubbleY)
                newBG.zPosition = 18
                parent?.addChild(newBG)
                self?.toolBubbleBG = newBG
            })
        } else {
            // Build fresh
            let bg = SKShapeNode(rectOf: CGSize(width: bubbleWidth, height: 16), cornerRadius: 4)
            bg.fillColor = SKColor(white: 0.1, alpha: 0.85)
            bg.strokeColor = SKColor(red: 0.35, green: 0.75, blue: 1.0, alpha: 0.5)
            bg.lineWidth = 0.5
            bg.position = CGPoint(x: 0, y: bubbleY)
            bg.zPosition = 18
            bg.alpha = 0
            addChild(bg)

            let lbl = SKLabelNode(fontNamed: "Menlo")
            lbl.fontSize = 8
            lbl.fontColor = SKColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 1)
            lbl.horizontalAlignmentMode = .center
            lbl.verticalAlignmentMode = .center
            lbl.text = label
            lbl.position = CGPoint(x: 0, y: bubbleY)
            lbl.zPosition = 19
            lbl.alpha = 0
            addChild(lbl)

            let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.2)
            bg.run(fadeIn)
            lbl.run(fadeIn)

            toolBubbleBG = bg
            toolBubbleLabel = lbl
        }

        // (Re)schedule the safety auto-hide.
        removeAction(forKey: "toolBubbleSafety")
        let safety = SKAction.sequence([
            SKAction.wait(forDuration: autoHideAfter),
            SKAction.run { [weak self] in self?.hideToolBubble() },
        ])
        run(safety, withKey: "toolBubbleSafety")
    }

    /// Hide the tool-event bubble (fades out and removes).
    func hideToolBubble() {
        removeAction(forKey: "toolBubbleSafety")
        let fade = SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.2),
            SKAction.removeFromParent(),
        ])
        toolBubbleBG?.run(fade)
        toolBubbleLabel?.run(fade)
        toolBubbleBG = nil
        toolBubbleLabel = nil
    }

    // MARK: - Progress Indicator (Wave 5)

    /// Update the mini progress indicator shown below the sprite.
    /// Passing `nil` for both params hides the indicator.
    func updateProgressIndicator(toolCount: Int?, tokenCount: Int?) {
        let formatted = Self.formatProgressText(toolCount: toolCount, tokenCount: tokenCount)
        guard let text = formatted else {
            hideProgressIndicator()
            return
        }

        let spriteSize = CrewSpriteBuilder.size(for: characterType)
        // Above the status dot (which is at -(height/2 + 6)), but below the
        // sprite body. Use -height/2 - 18 for clear separation from the dot.
        let yPos = -(spriteSize.height / 2 + 18)

        if let lbl = progressLabel {
            lbl.text = text
            lbl.position = CGPoint(x: 0, y: yPos)
            return
        }

        let lbl = SKLabelNode(fontNamed: "Menlo")
        lbl.fontSize = 7
        lbl.fontColor = SKColor(red: 0.75, green: 0.85, blue: 1.0, alpha: 0.95)
        lbl.horizontalAlignmentMode = .center
        lbl.verticalAlignmentMode = .top
        lbl.text = text
        lbl.position = CGPoint(x: 0, y: yPos)
        lbl.zPosition = 8
        lbl.alpha = 0
        addChild(lbl)
        progressLabel = lbl
        lbl.run(SKAction.fadeAlpha(to: 1.0, duration: 0.2))
    }

    /// Hide the progress indicator (fades out and removes).
    func hideProgressIndicator() {
        guard let lbl = progressLabel else { return }
        lbl.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.2),
            SKAction.removeFromParent(),
        ]))
        progressLabel = nil
    }

    /// Format `{toolCount} tools · {tokenCount}k tokens` with k/M suffix
    /// on the token count (one decimal). Returns nil when neither is present.
    static func formatProgressText(toolCount: Int?, tokenCount: Int?) -> String? {
        let toolPart: String? = toolCount.map { count in
            let label = count == 1 ? "tool" : "tools"
            return "\(count) \(label)"
        }
        let tokenPart: String? = tokenCount.map(formatTokenCount)

        switch (toolPart, tokenPart) {
        case let (tools?, tokens?): return "\(tools) · \(tokens)"
        case let (tools?, nil):     return tools
        case let (nil, tokens?):    return tokens
        default:                    return nil
        }
    }

    /// Format a raw token count as `"1.2k tokens"` / `"3.4M tokens"` / `"812 tokens"`.
    static func formatTokenCount(_ count: Int) -> String {
        let absCount = abs(count)
        if absCount >= 1_000_000 {
            let millions = Double(count) / 1_000_000.0
            return String(format: "%.1fM tokens", millions)
        } else if absCount >= 1_000 {
            let thousands = Double(count) / 1_000.0
            return String(format: "%.1fk tokens", thousands)
        } else {
            return "\(count) tokens"
        }
    }

    /// Show an animated emote above the sprite.
    /// The emote pops in, floats upward, then fades out.
    func showEmote(_ emote: EmoteType) {
        // Remove any existing emote
        childNode(withName: "emote")?.removeFromParent()

        let spriteSize = CrewSpriteBuilder.size(for: characterType)

        let label = SKLabelNode(text: emote.symbol)
        label.fontSize = 16
        label.name = "emote"
        label.position = CGPoint(x: 0, y: spriteSize.height / 2 + 8)
        label.zPosition = 25
        label.setScale(0.1)
        label.alpha = 0
        addChild(label)

        // Pop in
        let popIn = SKAction.group([
            SKAction.scale(to: 1.0, duration: 0.15),
            SKAction.fadeAlpha(to: 1.0, duration: 0.15),
        ])
        popIn.timingMode = .easeOut

        // Hold + gentle float
        let floatUp = SKAction.moveBy(x: 0, y: 12, duration: 1.2)
        floatUp.timingMode = .easeOut

        // Fade out
        let fadeOut = SKAction.group([
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.scale(to: 0.6, duration: 0.4),
        ])

        let sequence = SKAction.sequence([popIn, floatUp, fadeOut, SKAction.removeFromParent()])
        label.run(sequence)
    }

    // MARK: - Walk Animation

    /// Start a 2-frame walk cycle animation using walk sprite textures.
    /// Falls back to the standard facing texture if walk textures aren't available.
    func startWalkAnimation(direction: FacingDirection) {
        removeAction(forKey: "walkAnim")

        guard let frames = CrewSpriteBuilder.walkFrames(for: characterType, direction: direction) else {
            // No walk textures — just use the facing direction texture
            setFacing(direction)
            return
        }

        let animate = SKAction.animate(with: frames, timePerFrame: 0.28, resize: false, restore: false)
        bodySprite.run(SKAction.repeatForever(animate), withKey: "walkAnim")
    }

    /// Stop walk animation and restore the standing texture.
    func stopWalkAnimation() {
        bodySprite.removeAction(forKey: "walkAnim")
        CrewSpriteBuilder.updateTexture(bodySprite, type: characterType, facing: facing)
    }

    // MARK: - Waypoint Movement

    /// Move along a series of waypoints sequentially.
    /// Each segment calculates its own duration based on distance for consistent speed.
    /// Uses walk cycle animation when walk textures are available.
    func moveAlongPath(_ waypoints: [CGPoint], speed: CGFloat = 90, completion: (() -> Void)? = nil) {
        guard !waypoints.isEmpty else {
            completion?()
            return
        }

        removeAction(forKey: "move")

        var actions: [SKAction] = []
        var current = self.position

        for waypoint in waypoints {
            let dx = waypoint.x - current.x
            let dy = waypoint.y - current.y
            let distance = sqrt(dx * dx + dy * dy)
            let duration = max(TimeInterval(distance / speed), 0.1)

            // Update facing and start walk animation at the start of each segment
            let facingUpdate = SKAction.run { [weak self] in
                guard let self else { return }
                if abs(dx) > 1 || abs(dy) > 1 {
                    let newDirection = FacingDirection.from(dx: dx, dy: dy)
                    self.facing = newDirection
                    self.startWalkAnimation(direction: newDirection)
                }
            }

            let move = SKAction.move(to: waypoint, duration: duration)
            move.timingMode = .linear  // Consistent speed for grid paths

            actions.append(facingUpdate)
            actions.append(move)
            current = waypoint
        }

        // Stop walk animation when movement completes
        actions.append(SKAction.run { [weak self] in
            self?.stopWalkAnimation()
        })

        if let completion {
            actions.append(SKAction.run(completion))
        }

        run(SKAction.sequence(actions), withKey: "move")
    }

}
