import SpriteKit

// MARK: - Office Scene

/// The main SpriteKit scene that renders the office floor plan and agent sprites.
/// Includes activity stations, ambient animations, and agent management.
final class OfficeScene: SKScene {

    /// Callback when an agent sprite is tapped (wired to SwiftUI via OfficeView).
    var onAgentTapped: ((String) -> Void)?

    /// Tracks agent sprites by their agent ID.
    private var agentSprites: [String: AgentSprite] = [:]

    /// Desk node references for visual rendering.
    private var deskNodes: [Int: SKShapeNode] = [:]

    /// Station node references.
    private var stationNodes: [ActivityStationType: SKNode] = [:]

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
        renderStations()
        startAmbientAnimations()
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

    // MARK: - Station Rendering

    /// Render activity station sprites in the scene.
    private func renderStations() {
        for station in StationLayout.stations {
            let container = SKNode()
            container.position = station.position
            container.zPosition = 5
            container.name = "station_\(station.type.rawValue)"

            // Station icon (colored rectangle)
            let iconSize: CGSize
            switch station.type {
            case .pingPong:
                iconSize = CGSize(width: 30, height: 20)
            case .coffeeMachine:
                iconSize = CGSize(width: 16, height: 22)
            case .waterCooler:
                iconSize = CGSize(width: 14, height: 20)
            case .arcade:
                iconSize = CGSize(width: 22, height: 28)
            case .yoga:
                iconSize = CGSize(width: 28, height: 18)
            case .nap:
                iconSize = CGSize(width: 32, height: 14)
            case .whiteboard:
                iconSize = CGSize(width: 30, height: 24)
            }

            let (r, g, b) = station.spriteColor
            let icon = SKShapeNode(rectOf: iconSize, cornerRadius: 3)
            icon.fillColor = SKColor(red: r, green: g, blue: b, alpha: 0.7)
            icon.strokeColor = SKColor(red: r, green: g, blue: b, alpha: 1.0)
            icon.lineWidth = 1
            container.addChild(icon)

            // Station label
            let label = SKLabelNode(fontNamed: "Menlo")
            label.text = station.label.uppercased()
            label.fontSize = 7
            label.fontColor = SKColor(white: 0.6, alpha: 0.8)
            label.position = CGPoint(x: 0, y: -(iconSize.height / 2 + 10))
            label.horizontalAlignmentMode = .center
            container.addChild(label)

            // Station-specific decoration
            addStationDecoration(to: container, type: station.type)

            addChild(container)
            stationNodes[station.type] = container
        }
    }

    /// Add station-specific decorative elements.
    private func addStationDecoration(to container: SKNode, type: ActivityStationType) {
        switch type {
        case .coffeeMachine:
            // Coffee steam particles (3 small dots that float up)
            for i in 0..<3 {
                let steam = SKShapeNode(circleOfRadius: 1.5)
                steam.fillColor = SKColor(white: 0.7, alpha: 0.4)
                steam.strokeColor = .clear
                steam.position = CGPoint(x: CGFloat(i - 1) * 3, y: 14)
                steam.zPosition = 1
                steam.name = "steam_\(i)"
                container.addChild(steam)
            }

        case .pingPong:
            // Ball indicator
            let ball = SKShapeNode(circleOfRadius: 2)
            ball.fillColor = SKColor(red: 1.0, green: 0.8, blue: 0.2, alpha: 0.9)
            ball.strokeColor = .clear
            ball.position = CGPoint(x: 0, y: 0)
            ball.zPosition = 1
            ball.name = "pingpong_ball"
            container.addChild(ball)

        case .arcade:
            // Screen glow
            let glow = SKShapeNode(rectOf: CGSize(width: 16, height: 12), cornerRadius: 2)
            glow.fillColor = SKColor(red: 0.3, green: 0.9, blue: 0.3, alpha: 0.3)
            glow.strokeColor = .clear
            glow.position = CGPoint(x: 0, y: 4)
            glow.zPosition = 1
            glow.name = "arcade_glow"
            container.addChild(glow)

        default:
            break
        }
    }

    // MARK: - Ambient Animations

    /// Start subtle ambient animations for stations.
    private func startAmbientAnimations() {
        // Coffee steam animation
        if let coffeeStation = stationNodes[.coffeeMachine] {
            for i in 0..<3 {
                guard let steam = coffeeStation.childNode(withName: "steam_\(i)") else { continue }
                let delay = Double(i) * 0.4
                let rise = SKAction.sequence([
                    SKAction.wait(forDuration: delay),
                    SKAction.repeatForever(SKAction.sequence([
                        SKAction.group([
                            SKAction.moveBy(x: CGFloat.random(in: -2...2), y: 8, duration: 1.2),
                            SKAction.fadeOut(withDuration: 1.2),
                        ]),
                        SKAction.run { [weak steam] in
                            steam?.position = CGPoint(x: CGFloat(i - 1) * 3, y: 14)
                            steam?.alpha = 0.4
                        },
                    ])),
                ])
                steam.run(rise)
            }
        }

        // Ping pong ball bounce
        if let ppStation = stationNodes[.pingPong],
           let ball = ppStation.childNode(withName: "pingpong_ball") {
            let bounce = SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 12, y: 5, duration: 0.3),
                SKAction.moveBy(x: -12, y: -5, duration: 0.3),
                SKAction.moveBy(x: 12, y: -3, duration: 0.25),
                SKAction.moveBy(x: -12, y: 3, duration: 0.25),
            ]))
            ball.run(bounce)
        }

        // Arcade screen flicker
        if let arcadeStation = stationNodes[.arcade],
           let glow = arcadeStation.childNode(withName: "arcade_glow") {
            let flicker = SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.5, duration: 0.8),
                SKAction.fadeAlpha(to: 0.2, duration: 0.4),
                SKAction.fadeAlpha(to: 0.6, duration: 0.3),
                SKAction.fadeAlpha(to: 0.3, duration: 0.5),
            ]))
            glow.run(flicker)
        }
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

    /// Move an agent to a specific activity station.
    func moveAgentToStation(id: String, stationType: ActivityStationType) {
        guard let sprite = agentSprites[id] else { return }
        guard let station = StationLayout.stations.first(where: { $0.type == stationType }) else { return }

        // Offset slightly so multiple agents don't overlap exactly
        let offset = CGPoint(
            x: CGFloat.random(in: -10...10),
            y: CGFloat.random(in: -8...8)
        )
        let targetPos = CGPoint(
            x: station.position.x + offset.x,
            y: station.position.y + offset.y + 20 // Above the station icon
        )

        sprite.updateStatus(.walking)
        sprite.stopAnimations()
        sprite.moveTo(position: targetPos, duration: 1.5) {
            sprite.updateStatus(.idle)
            sprite.startStationAnimation(stationType: stationType)
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

    // MARK: - Touch Forwarding

    /// Called by AgentSprite when tapped. Forwards to SwiftUI via callback.
    func agentTapped(agentId: String) {
        onAgentTapped?(agentId)
    }
}
