import SpriteKit

// MARK: - Office Scene

/// The main SpriteKit scene that renders the office floor plan and agent sprites.
/// Placeholder version: colored rectangles for areas, colored sprites for agents.
/// Pretty pixel art comes in a future phase.
final class OfficeScene: SKScene {

    /// Callback when an agent sprite is tapped (wired to SwiftUI via OfficeView).
    var onAgentTapped: ((String) -> Void)?

    /// Callback when a blanket is requested via tapping the cold indicator.
    var onBlanketRequested: ((String) -> Void)?

    /// Optional callback fired when a blanket is given (for future haptic/sound).
    var onBlanketGiven: ((String) -> Void)?

    /// Tracks agent sprites by their agent ID.
    private var agentSprites: [String: AgentSprite] = [:]

    /// Desk node references for visual rendering.
    private var deskNodes: [Int: SKShapeNode] = [:]

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        backgroundColor = SKColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1.0)
        size = CGSize(width: OfficeLayout.sceneWidth, height: OfficeLayout.sceneHeight)
        scaleMode = .aspectFit
        anchorPoint = CGPoint(x: 0, y: 0)

        renderFloorPlan()
        renderDesks()
        renderDoor()
    }

    // MARK: - Floor Plan Rendering

    /// Draw colored rectangles for each office area.
    private func renderFloorPlan() {
        let areaColors: [OfficeAreaType: SKColor] = [
            .mainFloor:     SKColor(red: 0.18, green: 0.18, blue: 0.22, alpha: 1),
            .serverRoom:    SKColor(red: 0.15, green: 0.20, blue: 0.25, alpha: 1),
            .breakRoom:     SKColor(red: 0.22, green: 0.18, blue: 0.20, alpha: 1),
            .kitchen:       SKColor(red: 0.20, green: 0.20, blue: 0.18, alpha: 1),
            .dogCorner:     SKColor(red: 0.20, green: 0.18, blue: 0.15, alpha: 1),
            .dogPark:       SKColor(red: 0.15, green: 0.22, blue: 0.15, alpha: 1),
            .gym:           SKColor(red: 0.20, green: 0.15, blue: 0.20, alpha: 1),
            .rollercoaster: SKColor(red: 0.25, green: 0.18, blue: 0.18, alpha: 1),
        ]

        for area in OfficeLayout.areas {
            // Area background
            let node = SKSpriteNode(
                color: areaColors[area.type] ?? .darkGray,
                size: area.bounds.size
            )
            // SpriteKit positions by center, but our bounds are origin-based
            node.position = CGPoint(
                x: area.bounds.midX,
                y: area.bounds.midY
            )
            node.zPosition = 0
            addChild(node)

            // Area border
            let border = SKShapeNode(rect: area.bounds)
            border.strokeColor = SKColor(white: 0.3, alpha: 0.5)
            border.lineWidth = 1
            border.fillColor = .clear
            border.zPosition = 1
            addChild(border)

            // Area label
            let label = SKLabelNode(fontNamed: "Menlo")
            label.text = area.name.uppercased()
            label.fontSize = 10
            label.fontColor = SKColor(white: 0.5, alpha: 0.7)
            label.position = CGPoint(x: area.bounds.midX, y: area.bounds.maxY - 15)
            label.zPosition = 2
            addChild(label)
        }
    }

    /// Draw desk placeholders on the main floor.
    private func renderDesks() {
        for desk in OfficeLayout.desks {
            let deskNode = SKShapeNode(rectOf: CGSize(width: 40, height: 25), cornerRadius: 3)
            deskNode.fillColor = SKColor(red: 0.35, green: 0.25, blue: 0.18, alpha: 1)
            deskNode.strokeColor = SKColor(white: 0.4, alpha: 0.5)
            deskNode.lineWidth = 1
            deskNode.position = desk.position
            deskNode.zPosition = 3
            deskNode.name = "desk_\(desk.id)"
            addChild(deskNode)
            deskNodes[desk.id] = deskNode

            // Desk number label
            let label = SKLabelNode(fontNamed: "Menlo")
            label.text = "\(desk.id + 1)"
            label.fontSize = 8
            label.fontColor = SKColor(white: 0.5, alpha: 0.6)
            label.position = CGPoint(x: 0, y: -3)
            label.zPosition = 4
            deskNode.addChild(label)
        }
    }

    /// Draw the office door/entrance marker.
    private func renderDoor() {
        let door = SKShapeNode(rectOf: CGSize(width: 30, height: 10), cornerRadius: 2)
        door.fillColor = SKColor(red: 0.95, green: 0.65, blue: 0.25, alpha: 0.8)
        door.strokeColor = .clear
        door.position = OfficeLayout.doorPosition
        door.zPosition = 3
        addChild(door)

        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = "DOOR"
        label.fontSize = 7
        label.fontColor = .white
        label.position = CGPoint(x: 0, y: -3)
        door.addChild(label)
    }

    // MARK: - Agent Sprite Management

    /// Add a new agent sprite to the scene at the door position.
    func addAgent(id: String, name: String, characterType: CharacterType) {
        guard agentSprites[id] == nil else { return }

        let sprite = AgentSprite(agentId: id, name: name, characterType: characterType)
        sprite.position = OfficeLayout.doorPosition
        sprite.zPosition = 10
        addChild(sprite)
        agentSprites[id] = sprite
    }

    /// Remove an agent sprite from the scene.
    func removeAgent(id: String) {
        guard let sprite = agentSprites[id] else { return }
        sprite.stopAnimations()

        let fadeOut = SKAction.fadeOut(withDuration: 0.5)
        sprite.run(fadeOut) { [weak self] in
            sprite.removeFromParent()
            self?.agentSprites.removeValue(forKey: id)
        }
    }

    /// Move an agent sprite to a desk position.
    func moveAgentToDesk(id: String, deskIndex: Int) {
        guard let sprite = agentSprites[id] else { return }
        guard deskIndex < OfficeLayout.desks.count else { return }

        let deskPos = OfficeLayout.desks[deskIndex].position
        // Sit slightly behind the desk
        let seatPos = CGPoint(x: deskPos.x, y: deskPos.y - 20)

        sprite.stopAnimations()
        sprite.updateStatus(.walking)
        sprite.moveTo(position: seatPos, duration: 1.5) {
            sprite.updateStatus(.working)
            sprite.startWorkAnimation()
        }
    }

    /// Move an agent to a random idle position in a break area.
    func moveAgentToBreakArea(id: String, areaType: OfficeAreaType) {
        guard let sprite = agentSprites[id] else { return }
        let position = OfficeLayout.randomPosition(in: areaType)

        sprite.updateStatus(.walking)
        sprite.stopAnimations()
        sprite.moveTo(position: position, duration: 2.0) {
            sprite.updateStatus(.idle)
            sprite.startIdleAnimation()
        }
    }

    /// Move an agent toward the door (leaving).
    func moveAgentToDoor(id: String) {
        guard let sprite = agentSprites[id] else { return }
        sprite.updateStatus(.leaving)
        sprite.stopAnimations()
        sprite.moveTo(position: OfficeLayout.doorPosition, duration: 1.5)
    }

    /// Trigger celebration animation on an agent.
    func celebrateAgent(id: String) {
        guard let sprite = agentSprites[id] else { return }
        sprite.updateStatus(.celebrating)
        sprite.startCelebrationAnimation()
    }

    /// Update an agent's displayed name.
    func updateAgentName(id: String, name: String) {
        agentSprites[id]?.updateName(name)
    }

    /// Update the status indicator for an agent.
    func updateAgentStatus(id: String, status: AgentStatus) {
        agentSprites[id]?.updateStatus(status)
    }

    // MARK: - Desk Highlighting

    /// Highlight a desk when an agent is assigned to it.
    func highlightDesk(_ deskIndex: Int, occupied: Bool) {
        guard let deskNode = deskNodes[deskIndex] else { return }
        if occupied {
            deskNode.fillColor = SKColor(red: 0.45, green: 0.35, blue: 0.25, alpha: 1)
            deskNode.strokeColor = SKColor(red: 0.95, green: 0.65, blue: 0.25, alpha: 0.6)
        } else {
            deskNode.fillColor = SKColor(red: 0.35, green: 0.25, blue: 0.18, alpha: 1)
            deskNode.strokeColor = SKColor(white: 0.4, alpha: 0.5)
        }
    }

    // MARK: - Blanket Mechanic

    /// Show the cold/shiver state for an agent wanting a blanket.
    func showColdState(id: String) {
        guard let sprite = agentSprites[id] else { return }
        sprite.showColdIndicator()
        if sprite.action(forKey: "shiver") == nil {
            sprite.startShiverAnimation()
        }
    }

    /// Give blanket to an agent — show overlay, play happy animation.
    func giveBlanket(id: String) {
        guard let sprite = agentSprites[id] else { return }
        sprite.hideColdIndicator()
        sprite.removeAction(forKey: "shiver")
        sprite.showBlanket()
        sprite.playBlanketHappyWiggle()
        onBlanketGiven?(id)
    }

    /// Remove blanket visual from an agent (when leaving desk).
    func removeBlanket(id: String) {
        guard let sprite = agentSprites[id] else { return }
        sprite.hideColdIndicator()
        sprite.hideBlanket()
        sprite.removeAction(forKey: "shiver")
    }

    // MARK: - Touch Forwarding

    /// Called by AgentSprite when the cold indicator is tapped.
    func blanketRequested(agentId: String) {
        onBlanketRequested?(agentId)
    }

    /// Called by AgentSprite when tapped. Forwards to SwiftUI via callback.
    func agentTapped(agentId: String) {
        onAgentTapped?(agentId)
    }
}
