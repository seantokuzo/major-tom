import SpriteKit

// MARK: - Office Scene

/// The main SpriteKit scene that renders the office floor plan and agent sprites.
/// Includes activity stations, ambient animations, theme overlays, and agent management.
final class OfficeScene: SKScene {

    /// Callback when an agent sprite is tapped (wired to SwiftUI via OfficeView).
    var onAgentTapped: ((String) -> Void)?

    /// Tracks agent sprites by their agent ID.
    private var agentSprites: [String: AgentSprite] = [:]

    /// Desk node references for visual rendering.
    private var deskNodes: [Int: SKShapeNode] = [:]

    /// Station node references.
    private var stationNodes: [ActivityStationType: SKNode] = [:]

    // MARK: - Theme & Mood

    /// Reference to the theme engine (set by OfficeView on appear).
    var themeEngine: ThemeEngine?

    /// Reference to the mood engine (set by OfficeView on appear).
    var moodEngine: MoodEngine?

    /// Overlay node for time-of-day tinting.
    private var themeOverlay: SKSpriteNode?

    /// Desk lamp glow nodes (visible at night).
    private var lampNodes: [Int: SKShapeNode] = [:]

    /// Snow decoration nodes (visible in winter).
    private var snowNodes: [SKShapeNode] = []

    /// Agent interaction scan timer.
    private var interactionScanTime: TimeInterval = 0

    /// Agents currently in an idle chat interaction.
    private var chattingAgents: Set<String> = []

    /// Mood speech timer — triggers random mood quips.
    private var moodSpeechTime: TimeInterval = 0

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
        renderThemeOverlay()
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

    // MARK: - Theme Rendering

    /// Create the theme overlay node that covers the entire scene.
    private func renderThemeOverlay() {
        let overlay = SKSpriteNode(color: .clear, size: size)
        overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.zPosition = 5  // Above furniture/background (0-4), below agents (10)
        overlay.alpha = 0
        overlay.name = "themeOverlay"
        addChild(overlay)
        themeOverlay = overlay

        // Create lamp glow nodes near each desk (hidden by default)
        for desk in OfficeLayout.desks {
            let glow = SKShapeNode(circleOfRadius: 18)
            glow.fillColor = SKColor(red: 1.0, green: 0.86, blue: 0.59, alpha: 0.2)
            glow.strokeColor = .clear
            glow.position = CGPoint(x: desk.position.x + 15, y: desk.position.y + 10)
            glow.zPosition = 8
            glow.alpha = 0
            glow.name = "lamp_\(desk.id)"
            addChild(glow)
            lampNodes[desk.id] = glow
        }
    }

    /// Apply theme state to the scene. Called from update(currentTime:).
    private func applyTheme() {
        guard let theme = themeEngine else { return }

        // Update overlay tint
        if let overlay = themeOverlay {
            overlay.color = theme.palette.overlayColor
            overlay.alpha = theme.palette.overlayAlpha
        }

        // Desk lamps — visible at night when desks are occupied.
        // Check occupancy from agentSprites positions near desks (OfficeLayout.desks is static).
        for desk in OfficeLayout.desks {
            guard let lampNode = lampNodes[desk.id] else { continue }
            let deskOccupied = agentSprites.values.contains { sprite in
                let dx = sprite.position.x - desk.position.x
                let dy = sprite.position.y - desk.position.y
                return dx * dx + dy * dy < 30 * 30
            }
            if theme.palette.lampsOn && deskOccupied {
                lampNode.alpha = 0.25
                // Subtle flicker
                if lampNode.action(forKey: "flicker") == nil {
                    let flicker = SKAction.repeatForever(SKAction.sequence([
                        SKAction.fadeAlpha(to: 0.2, duration: 0.8),
                        SKAction.fadeAlpha(to: 0.3, duration: 0.6),
                    ]))
                    lampNode.run(flicker, withKey: "flicker")
                }
            } else {
                lampNode.removeAction(forKey: "flicker")
                lampNode.alpha = 0
            }
        }

        // Seasonal snow on window areas — add snow nodes if winter and not yet present
        if theme.seasonal.showSnow && snowNodes.isEmpty {
            addSnowDecorations()
        } else if !theme.seasonal.showSnow && !snowNodes.isEmpty {
            removeSnowDecorations()
        }
    }

    /// Add snow decorations on top of the scene (window sills).
    private func addSnowDecorations() {
        // Snow along the top of the scene (window sill area)
        for x in stride(from: 20, to: Int(size.width) - 20, by: 12) {
            let snow = SKShapeNode(ellipseOf: CGSize(width: CGFloat.random(in: 6...10), height: CGFloat.random(in: 3...5)))
            snow.fillColor = SKColor(white: 0.94, alpha: 0.7)
            snow.strokeColor = .clear
            snow.position = CGPoint(x: CGFloat(x) + CGFloat.random(in: -3...3), y: size.height - 5)
            snow.zPosition = 55
            addChild(snow)
            snowNodes.append(snow)
        }
    }

    /// Remove snow decorations.
    private func removeSnowDecorations() {
        for node in snowNodes {
            node.removeFromParent()
        }
        snowNodes.removeAll()
    }

    // MARK: - Frame Update

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)

        // Apply theme every frame (cheap — just sets colors/alphas)
        applyTheme()

        // Update agent moods from mood engine (every ~30s, but we check each frame for visual updates)
        applyAgentMoods()

        // Scan for agent interactions every ~8 seconds
        if currentTime - interactionScanTime > 8 {
            interactionScanTime = currentTime
            scanForInteractions()
        }

        // Random mood speech every ~15 seconds
        if currentTime - moodSpeechTime > 15 {
            moodSpeechTime = currentTime
            triggerRandomMoodSpeech()
        }
    }

    /// Apply mood engine state to agent sprites.
    private func applyAgentMoods() {
        guard let moodEngine else { return }
        for (agentId, sprite) in agentSprites {
            let mood = moodEngine.mood(for: agentId)
            sprite.updateMood(mood)
        }
    }

    // MARK: - Agent Interactions

    /// Scan for idle agents near each other and trigger chat interactions.
    private func scanForInteractions() {
        let idleSprites = agentSprites.values.filter { sprite in
            !chattingAgents.contains(sprite.agentId) &&
            sprite.action(forKey: "move") == nil  // not currently moving
        }

        guard idleSprites.count >= 2 else { return }

        // Check pairs of idle agents for proximity
        for i in 0..<idleSprites.count {
            for j in (i + 1)..<idleSprites.count {
                let a = idleSprites[i]
                let b = idleSprites[j]
                let dx = a.position.x - b.position.x
                let dy = a.position.y - b.position.y
                let dist = sqrt(dx * dx + dy * dy)

                // Within 80pt and 6% chance to chat
                if dist < 80, Double.random(in: 0...1) < 0.06 {
                    triggerIdleChat(between: a, and: b)
                    return  // Only one chat per scan
                }
            }
        }
    }

    /// Trigger a chat exchange between two idle agents.
    private func triggerIdleChat(between a: AgentSprite, and b: AgentSprite) {
        // Capture agent IDs up-front before closures — avoids stale reference
        // if the sprite is removed mid-chat.
        let aId = a.agentId
        let bId = b.agentId

        chattingAgents.insert(aId)
        chattingAgents.insert(bId)

        let chatTopics = [
            ("Tests are failing again", "It's always the tests"),
            ("We should use microservices", "Nah, monolith's fine"),
            ("My dog ate my PR", "Good boy energy"),
            ("Standup was long", "JIRA is down again"),
            ("Who ordered pizza?", "Coffee run?"),
            ("This PR is huge", "LGTM *eyes closed*"),
            ("Merge conflict time", "Who owns this repo?"),
        ]

        guard let topic = chatTopics.randomElement() else { return }

        // Agent A speaks first
        a.showSpeechBubble(topic.0, duration: 2.5)

        // Agent B responds after a delay
        let delay = SKAction.wait(forDuration: 3.0)
        b.run(delay) { [weak self, weak b] in
            b?.showSpeechBubble(topic.1, duration: 2.5)

            // Clear chatting state after exchange
            let cleanup = SKAction.wait(forDuration: 3.5)
            b?.run(cleanup) { [weak self] in
                self?.chattingAgents.remove(aId)
                self?.chattingAgents.remove(bId)
            }
        }
    }

    /// Trigger a random mood-appropriate speech bubble on a random agent.
    private func triggerRandomMoodSpeech() {
        let candidates = agentSprites.values.filter { !chattingAgents.contains($0.agentId) }
        guard let sprite = candidates.randomElement() else { return }
        sprite.showMoodSpeech()
    }

    /// Broadcast a celebration to all agents near the source agent.
    func broadcastCelebration(sourceId: String) {
        guard let sourceSprite = agentSprites[sourceId] else { return }

        // All other agents within 150pt react
        for (id, sprite) in agentSprites where id != sourceId {
            let dx = sprite.position.x - sourceSprite.position.x
            let dy = sprite.position.y - sourceSprite.position.y
            let dist = sqrt(dx * dx + dy * dy)

            if dist < 150 {
                let reactions = ["GG!", "Ship it!", "Nice work!", "*claps*", "Woohoo!", "Nice!"]
                if let reaction = reactions.randomElement() {
                    let delay = SKAction.wait(forDuration: Double.random(in: 0.3...1.2))
                    sprite.run(delay) { [weak sprite] in
                        sprite?.showSpeechBubble(reaction, duration: 2.0)
                    }
                }
            }
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

    /// Trigger celebration animation on an agent + broadcast to nearby agents.
    func celebrateAgent(id: String) {
        guard let sprite = agentSprites[id] else { return }
        sprite.updateStatus(.celebrating)
        sprite.startCelebrationAnimation()
        broadcastCelebration(sourceId: id)
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
