import SpriteKit

// MARK: - Office Scene

/// The main SpriteKit scene rendering Space Station Major Tom.
/// Each module has distinct furniture, prominent windows showing deep space,
/// layered visual depth, and ambient particle effects.
final class OfficeScene: SKScene {

    /// Callback when an agent sprite is tapped (wired to SwiftUI via OfficeView).
    var onAgentTapped: ((String) -> Void)?

    /// Tracks agent sprites by their agent ID.
    private var agentSprites: [String: AgentSprite] = [:]

    /// Desk node references for visual rendering.
    private var deskNodes: [Int: SKShapeNode] = [:]

    /// Station node references.
    private var stationNodes: [ActivityStationType: SKNode] = [:]

    /// Window container nodes for starfield effects.
    private var windowNodes: [SKNode] = []

    // MARK: - Theme & Mood

    var themeEngine: ThemeEngine?
    var moodEngine: MoodEngine?
    private var themeOverlay: SKSpriteNode?
    private var lampNodes: [Int: SKShapeNode] = [:]
    private var snowNodes: [SKShapeNode] = []
    private var interactionScanTime: TimeInterval = 0
    private var chattingAgents: Set<String> = []
    private var moodSpeechTime: TimeInterval = 0

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        super.didMove(to: view)
        backgroundColor = StationPalette.deepSpace
        size = CGSize(width: OfficeLayout.sceneWidth, height: OfficeLayout.sceneHeight)
        scaleMode = .aspectFit
        anchorPoint = CGPoint(x: 0, y: 0)

        renderStationHull()
        renderWindows()
        renderModuleFurniture()
        renderDesks()
        renderAirlock()
        renderStations()
        renderThemeOverlay()
        renderAmbientParticles()
        startAmbientAnimations()
    }

    // MARK: - Station Hull Rendering

    private func renderStationHull() {
        for module in StationLayout.modules {
            let bounds = module.bounds

            // Module floor — alternating panel shading for depth
            renderFloorPanels(in: bounds, moduleType: module.type)

            // Hull walls — thick borders with bevel effect
            renderHullWalls(for: bounds)

            // Ceiling pipe runs
            renderCeilingPipes(for: bounds, moduleType: module.type)

            // Module name plate
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.text = module.name.uppercased()
            label.fontSize = 9
            label.fontColor = StationPalette.ambientPanel.withAlphaComponent(0.7)
            label.position = CGPoint(x: bounds.midX, y: bounds.maxY - 15)
            label.zPosition = 2
            addChild(label)

            // Status strip
            renderStatusStrip(for: bounds, moduleType: module.type)
        }
    }

    /// Alternating floor panel tiles with subtle shade variation.
    private func renderFloorPanels(in bounds: CGRect, moduleType: ModuleType) {
        let tileSize: CGFloat = 32
        let baseColor = StationPalette.floorColor(for: moduleType)

        var col = 0
        var x = bounds.minX
        while x < bounds.maxX {
            var row = 0
            var y = bounds.minY
            while y < bounds.maxY {
                let w = min(tileSize, bounds.maxX - x)
                let h = min(tileSize, bounds.maxY - y)

                // Alternate shade for checkerboard depth
                let isLight = (col + row) % 2 == 0
                let shade: CGFloat = isLight ? 1.0 : 0.88
                let tileColor = blendColor(baseColor, brightness: shade)

                let tile = SKSpriteNode(color: tileColor, size: CGSize(width: w, height: h))
                tile.position = CGPoint(x: x + w / 2, y: y + h / 2)
                tile.zPosition = 0
                addChild(tile)

                // Tile seam lines (right and top edges)
                if x + tileSize < bounds.maxX {
                    let vSeam = SKSpriteNode(
                        color: StationPalette.floorGridLine.withAlphaComponent(0.4),
                        size: CGSize(width: 1, height: h)
                    )
                    vSeam.position = CGPoint(x: x + w, y: y + h / 2)
                    vSeam.zPosition = 0.5
                    addChild(vSeam)
                }
                if y + tileSize < bounds.maxY {
                    let hSeam = SKSpriteNode(
                        color: StationPalette.floorGridLine.withAlphaComponent(0.4),
                        size: CGSize(width: w, height: 1)
                    )
                    hSeam.position = CGPoint(x: x + w / 2, y: y + h)
                    hSeam.zPosition = 0.5
                    addChild(hSeam)
                }

                y += tileSize
                row += 1
            }
            x += tileSize
            col += 1
        }
    }

    /// Helper: adjust a color's brightness.
    private func blendColor(_ color: SKColor, brightness: CGFloat) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SKColor(red: r * brightness, green: g * brightness, blue: b * brightness, alpha: a)
    }

    /// Thick hull walls with bevel/highlight effect.
    private func renderHullWalls(for bounds: CGRect) {
        let wallThickness: CGFloat = 4

        // Top wall (bright edge = lit from overhead)
        let topWall = SKSpriteNode(
            color: StationPalette.hullAccent,
            size: CGSize(width: bounds.width, height: wallThickness)
        )
        topWall.position = CGPoint(x: bounds.midX, y: bounds.maxY - wallThickness / 2)
        topWall.zPosition = 1
        addChild(topWall)

        // Top wall highlight
        let topHighlight = SKSpriteNode(
            color: StationPalette.wallTrim.withAlphaComponent(0.3),
            size: CGSize(width: bounds.width, height: 1)
        )
        topHighlight.position = CGPoint(x: bounds.midX, y: bounds.maxY - 0.5)
        topHighlight.zPosition = 1.5
        addChild(topHighlight)

        // Bottom wall (shadow = underside)
        let bottomWall = SKSpriteNode(
            color: StationPalette.hullPrimary,
            size: CGSize(width: bounds.width, height: wallThickness)
        )
        bottomWall.position = CGPoint(x: bounds.midX, y: bounds.minY + wallThickness / 2)
        bottomWall.zPosition = 1
        addChild(bottomWall)

        // Left wall
        let leftWall = SKSpriteNode(
            color: StationPalette.hullAccent.withAlphaComponent(0.8),
            size: CGSize(width: wallThickness, height: bounds.height)
        )
        leftWall.position = CGPoint(x: bounds.minX + wallThickness / 2, y: bounds.midY)
        leftWall.zPosition = 1
        addChild(leftWall)

        // Right wall
        let rightWall = SKSpriteNode(
            color: StationPalette.hullPrimary.withAlphaComponent(0.9),
            size: CGSize(width: wallThickness, height: bounds.height)
        )
        rightWall.position = CGPoint(x: bounds.maxX - wallThickness / 2, y: bounds.midY)
        rightWall.zPosition = 1
        addChild(rightWall)
    }

    /// Ceiling pipes with visual weight.
    private func renderCeilingPipes(for bounds: CGRect, moduleType: ModuleType) {
        let pipeY = bounds.maxY - 7
        let pipe = SKSpriteNode(
            color: StationPalette.ceilingPipe.withAlphaComponent(0.5),
            size: CGSize(width: bounds.width - 12, height: 3)
        )
        pipe.position = CGPoint(x: bounds.midX, y: pipeY)
        pipe.zPosition = 1.8
        addChild(pipe)

        // Pipe highlight (top edge catch light)
        let pipeHL = SKSpriteNode(
            color: StationPalette.wallTrim.withAlphaComponent(0.2),
            size: CGSize(width: bounds.width - 14, height: 1)
        )
        pipeHL.position = CGPoint(x: bounds.midX, y: pipeY + 1.5)
        pipeHL.zPosition = 1.9
        addChild(pipeHL)

        // Engineering: extra cable conduits
        if moduleType == .engineering {
            for offset in stride(from: bounds.minX + 20, to: bounds.maxX - 10, by: 22) {
                let cable = SKShapeNode()
                let path = CGMutablePath()
                path.move(to: CGPoint(x: offset, y: bounds.maxY - 5))
                path.addLine(to: CGPoint(x: offset + 4, y: bounds.maxY - 22))
                cable.path = path
                cable.strokeColor = StationPalette.consoleCyan.withAlphaComponent(0.12)
                cable.lineWidth = 1.5
                cable.zPosition = 1.8
                addChild(cable)
            }
        }
    }

    /// Pulsing status strip along module bottom wall.
    private func renderStatusStrip(for bounds: CGRect, moduleType: ModuleType) {
        let strip = SKSpriteNode(
            color: StationPalette.consoleSuccess.withAlphaComponent(0.3),
            size: CGSize(width: bounds.width - 12, height: 2)
        )
        strip.position = CGPoint(x: bounds.midX, y: bounds.minY + 6)
        strip.zPosition = 1.5
        strip.name = "statusStrip_\(moduleType.rawValue)"
        addChild(strip)

        strip.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.15, duration: 2.5),
            SKAction.fadeAlpha(to: 0.4, duration: 2.5),
        ])))
    }

    // MARK: - Window Rendering

    private func renderWindows() {
        for (module, windowConfig) in StationLayout.allWindows {
            let window = createWindowNode(config: windowConfig, module: module)
            addChild(window)
            windowNodes.append(window)
        }
    }

    private func createWindowNode(config: WindowConfig, module: StationModule) -> SKNode {
        let container = SKNode()
        container.position = config.position
        container.zPosition = 0.8

        let windowSize = config.size

        // Deep space backing
        let spaceBg = SKSpriteNode(color: StationPalette.deepSpace, size: windowSize)
        spaceBg.zPosition = 0
        container.addChild(spaceBg)

        // Crop node masks particles to window shape
        let cropNode = SKCropNode()
        cropNode.maskNode = SKSpriteNode(color: .white, size: windowSize)
        cropNode.zPosition = 1

        // Emitter area slightly oversized for coverage
        let emitterSize = CGSize(width: windowSize.width * 2, height: windowSize.height * 2)

        let nebula = StationParticleFactory.nebulaGlow(size: emitterSize)
        cropNode.addChild(nebula)

        let farStars = StationParticleFactory.starFieldFar(size: emitterSize)
        farStars.zPosition = 1
        cropNode.addChild(farStars)

        let nearStars = StationParticleFactory.starFieldNear(size: emitterSize)
        nearStars.zPosition = 2
        cropNode.addChild(nearStars)

        container.addChild(cropNode)

        // Metallic window frame with depth — outer border
        let outerFrame = SKShapeNode(rectOf: CGSize(width: windowSize.width + 6, height: windowSize.height + 6), cornerRadius: 2)
        outerFrame.strokeColor = StationPalette.hullPrimary
        outerFrame.lineWidth = 3
        outerFrame.fillColor = .clear
        outerFrame.zPosition = 3
        container.addChild(outerFrame)

        // Inner frame highlight
        let innerFrame = SKShapeNode(rectOf: CGSize(width: windowSize.width + 2, height: windowSize.height + 2), cornerRadius: 1)
        innerFrame.strokeColor = StationPalette.wallTrim.withAlphaComponent(0.5)
        innerFrame.lineWidth = 1
        innerFrame.fillColor = .clear
        innerFrame.zPosition = 3.5
        container.addChild(innerFrame)

        // Glass reflection — diagonal highlight
        let reflection = SKSpriteNode(
            color: SKColor(white: 1.0, alpha: 0.04),
            size: CGSize(width: windowSize.width * 0.5, height: windowSize.height * 0.3)
        )
        reflection.position = CGPoint(x: -windowSize.width * 0.12, y: windowSize.height * 0.15)
        reflection.zPosition = 4
        reflection.zRotation = 0.1
        container.addChild(reflection)

        return container
    }

    // MARK: - Module Furniture

    /// Place signature furniture in each module.
    private func renderModuleFurniture() {
        renderCommandBridgeFurniture()
        renderEngineeringFurniture()
        renderCrewQuartersFurniture()
        renderGalleyFurniture()
        renderBioDomeFurniture()
        renderTrainingBayFurniture()
        renderEVABayFurniture()
    }

    private func renderCommandBridgeFurniture() {
        // Tactical display on the upper wall
        let tactical = StationFurnitureFactory.tacticalDisplay()
        tactical.position = CGPoint(x: 720, y: 560)
        tactical.zPosition = 3
        addChild(tactical)

        // Blinking wall panels
        addWallStatusPanels(in: CGRect(x: 200, y: 300, width: 600, height: 300), count: 4)
    }

    private func renderEngineeringFurniture() {
        let bounds = CGRect(x: 0, y: 400, width: 200, height: 200)

        // REACTOR CORE — centerpiece
        let reactor = StationFurnitureFactory.reactorCore()
        reactor.position = CGPoint(x: bounds.midX, y: bounds.midY)
        reactor.zPosition = 3
        addChild(reactor)

        // Power panels on the wall
        let panel1 = StationFurnitureFactory.powerPanel()
        panel1.position = CGPoint(x: bounds.maxX - 20, y: bounds.midY + 30)
        panel1.zPosition = 3
        addChild(panel1)

        let panel2 = StationFurnitureFactory.powerPanel()
        panel2.position = CGPoint(x: bounds.maxX - 20, y: bounds.midY - 30)
        panel2.zPosition = 3
        addChild(panel2)
    }

    private func renderCrewQuartersFurniture() {
        let bounds = CGRect(x: 0, y: 200, width: 200, height: 200)

        // Bunks
        let bunk1 = StationFurnitureFactory.bunkBed(color: SKColor(red: 0.20, green: 0.25, blue: 0.45, alpha: 1))
        bunk1.position = CGPoint(x: bounds.midX + 20, y: bounds.maxY - 50)
        bunk1.zPosition = 3
        addChild(bunk1)

        let bunk2 = StationFurnitureFactory.bunkBed(color: SKColor(red: 0.35, green: 0.20, blue: 0.30, alpha: 1))
        bunk2.position = CGPoint(x: bounds.midX + 20, y: bounds.maxY - 80)
        bunk2.zPosition = 3
        addChild(bunk2)

        let bunk3 = StationFurnitureFactory.bunkBed(color: SKColor(red: 0.20, green: 0.35, blue: 0.30, alpha: 1))
        bunk3.position = CGPoint(x: bounds.midX + 20, y: bounds.maxY - 110)
        bunk3.zPosition = 3
        addChild(bunk3)

        // Media screen
        let media = StationFurnitureFactory.mediaScreen()
        media.position = CGPoint(x: bounds.maxX - 25, y: bounds.midY + 10)
        media.zPosition = 3
        addChild(media)

        addWallStatusPanels(in: bounds, count: 2)
    }

    private func renderGalleyFurniture() {
        let bounds = CGRect(x: 200, y: 100, width: 250, height: 200)

        // Food dispensers
        let disp1 = StationFurnitureFactory.foodDispenser()
        disp1.position = CGPoint(x: bounds.minX + 30, y: bounds.maxY - 40)
        disp1.zPosition = 3
        addChild(disp1)

        let disp2 = StationFurnitureFactory.foodDispenser()
        disp2.position = CGPoint(x: bounds.minX + 60, y: bounds.maxY - 40)
        disp2.zPosition = 3
        addChild(disp2)

        // Counter
        let counter = StationFurnitureFactory.counter()
        counter.position = CGPoint(x: bounds.midX + 20, y: bounds.midY - 10)
        counter.zPosition = 3
        addChild(counter)

        // Seating
        for i in 0..<3 {
            let chair = StationFurnitureFactory.chair()
            chair.position = CGPoint(x: bounds.midX + CGFloat(i - 1) * 22 + 20, y: bounds.midY - 30)
            chair.zPosition = 3
            addChild(chair)
        }

        addWallStatusPanels(in: bounds, count: 2)
    }

    private func renderBioDomeFurniture() {
        let bounds = CGRect(x: 450, y: 100, width: 350, height: 200)

        // Plants / trees (the "living" part of the bio-dome)
        let tree1 = StationFurnitureFactory.plant(size: 1.3)
        tree1.position = CGPoint(x: bounds.minX + 60, y: bounds.midY + 10)
        tree1.zPosition = 3
        addChild(tree1)

        let tree2 = StationFurnitureFactory.plant(size: 1.0)
        tree2.position = CGPoint(x: bounds.midX + 30, y: bounds.midY + 20)
        tree2.zPosition = 3
        addChild(tree2)

        let tree3 = StationFurnitureFactory.plant(size: 0.8)
        tree3.position = CGPoint(x: bounds.maxX - 60, y: bounds.midY - 10)
        tree3.zPosition = 3
        addChild(tree3)

        // Water feature
        let water = StationFurnitureFactory.waterFeature()
        water.position = CGPoint(x: bounds.midX - 20, y: bounds.minY + 35)
        water.zPosition = 3
        addChild(water)

        // Small grow-light panels on the ceiling
        for x in stride(from: bounds.minX + 40, to: bounds.maxX - 30, by: 70) {
            let light = SKSpriteNode(
                color: SKColor(red: 0.6, green: 0.3, blue: 0.8, alpha: 0.15),
                size: CGSize(width: 30, height: 4)
            )
            light.position = CGPoint(x: x, y: bounds.maxY - 20)
            light.zPosition = 2
            addChild(light)

            light.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.08, duration: 3.0),
                SKAction.fadeAlpha(to: 0.2, duration: 3.0),
            ])))
        }
    }

    private func renderTrainingBayFurniture() {
        let bounds = CGRect(x: 0, y: 0, width: 250, height: 100)

        // Exercise equipment
        let equip1 = StationFurnitureFactory.exerciseEquipment()
        equip1.position = CGPoint(x: bounds.minX + 50, y: bounds.midY)
        equip1.zPosition = 3
        addChild(equip1)

        let equip2 = StationFurnitureFactory.exerciseEquipment()
        equip2.position = CGPoint(x: bounds.minX + 100, y: bounds.midY)
        equip2.zPosition = 3
        addChild(equip2)

        addWallStatusPanels(in: bounds, count: 2)
    }

    private func renderEVABayFurniture() {
        let bounds = CGRect(x: 500, y: 0, width: 300, height: 100)

        // Space suit racks
        let suit1 = StationFurnitureFactory.spaceSuitRack()
        suit1.position = CGPoint(x: bounds.minX + 40, y: bounds.midY + 5)
        suit1.zPosition = 3
        addChild(suit1)

        let suit2 = StationFurnitureFactory.spaceSuitRack()
        suit2.position = CGPoint(x: bounds.minX + 75, y: bounds.midY + 5)
        suit2.zPosition = 3
        addChild(suit2)

        let suit3 = StationFurnitureFactory.spaceSuitRack()
        suit3.position = CGPoint(x: bounds.minX + 110, y: bounds.midY + 5)
        suit3.zPosition = 3
        addChild(suit3)

        addWallStatusPanels(in: bounds, count: 2)
    }

    // MARK: - Desk Rendering

    private func renderDesks() {
        for desk in OfficeLayout.desks {
            // Use the detailed console workstation from the factory
            let console = StationFurnitureFactory.workstationConsole()
            console.position = desk.position
            console.zPosition = 3
            console.name = "consoleGroup_\(desk.id)"
            addChild(console)

            // Invisible hit-target for desk highlighting (the shape node the rest of the code references)
            let hitNode = SKShapeNode(rectOf: CGSize(width: 44, height: 20), cornerRadius: 2)
            hitNode.fillColor = .clear
            hitNode.strokeColor = .clear
            hitNode.position = desk.position
            hitNode.zPosition = 3.1
            hitNode.name = "desk_\(desk.id)"
            addChild(hitNode)
            deskNodes[desk.id] = hitNode
        }
    }

    /// Draw the station airlock.
    private func renderAirlock() {
        let airlock = SKNode()
        airlock.position = OfficeLayout.doorPosition
        airlock.zPosition = 3

        // Left door panel
        let leftDoor = SKSpriteNode(
            color: StationPalette.hullPrimary,
            size: CGSize(width: 14, height: 28)
        )
        leftDoor.position = CGPoint(x: -8, y: 0)
        airlock.addChild(leftDoor)

        // Right door panel
        let rightDoor = SKSpriteNode(
            color: StationPalette.hullPrimary,
            size: CGSize(width: 14, height: 28)
        )
        rightDoor.position = CGPoint(x: 8, y: 0)
        airlock.addChild(rightDoor)

        // Frame
        let frame = SKShapeNode(rectOf: CGSize(width: 32, height: 32), cornerRadius: 2)
        frame.strokeColor = StationPalette.wallTrim.withAlphaComponent(0.5)
        frame.lineWidth = 1.5
        frame.fillColor = .clear
        frame.zPosition = 1
        airlock.addChild(frame)

        // Center seam
        let seam = SKSpriteNode(
            color: StationPalette.consoleCyan.withAlphaComponent(0.3),
            size: CGSize(width: 1, height: 26)
        )
        seam.zPosition = 2
        airlock.addChild(seam)

        // Status light
        let light = SKShapeNode(circleOfRadius: 2.5)
        light.fillColor = StationPalette.consoleSuccess.withAlphaComponent(0.6)
        light.strokeColor = .clear
        light.position = CGPoint(x: 0, y: 19)
        light.zPosition = 2
        airlock.addChild(light)

        light.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 1.0),
            SKAction.fadeAlpha(to: 0.8, duration: 1.0),
        ])))

        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = "AIRLOCK"
        label.fontSize = 6
        label.fontColor = StationPalette.ambientPanel.withAlphaComponent(0.5)
        label.position = CGPoint(x: 0, y: -22)
        label.zPosition = 2
        airlock.addChild(label)

        addChild(airlock)
    }

    // MARK: - Station Rendering

    private func renderStations() {
        for station in ActivityStationLayout.stations {
            let container = SKNode()
            container.position = station.position
            container.zPosition = 5
            container.name = "station_\(station.type.rawValue)"

            let iconSize: CGSize
            switch station.type {
            case .pingPong:     iconSize = CGSize(width: 30, height: 20)
            case .coffeeMachine: iconSize = CGSize(width: 16, height: 22)
            case .waterCooler:  iconSize = CGSize(width: 14, height: 20)
            case .arcade:       iconSize = CGSize(width: 22, height: 28)
            case .yoga:         iconSize = CGSize(width: 28, height: 18)
            case .nap:          iconSize = CGSize(width: 32, height: 14)
            case .whiteboard:   iconSize = CGSize(width: 30, height: 24)
            }

            let (r, g, b) = station.spriteColor
            let icon = SKShapeNode(rectOf: iconSize, cornerRadius: 3)
            icon.fillColor = SKColor(red: r, green: g, blue: b, alpha: 0.5)
            icon.strokeColor = SKColor(red: r, green: g, blue: b, alpha: 0.7)
            icon.lineWidth = 1
            container.addChild(icon)

            let label = SKLabelNode(fontNamed: "Menlo")
            label.text = station.label.uppercased()
            label.fontSize = 7
            label.fontColor = StationPalette.ambientPanel.withAlphaComponent(0.5)
            label.position = CGPoint(x: 0, y: -(iconSize.height / 2 + 10))
            label.horizontalAlignmentMode = .center
            container.addChild(label)

            addStationDecoration(to: container, type: station.type)
            addChild(container)
            stationNodes[station.type] = container
        }
    }

    private func addStationDecoration(to container: SKNode, type: ActivityStationType) {
        switch type {
        case .coffeeMachine:
            for i in 0..<3 {
                let steam = SKShapeNode(circleOfRadius: 1.5)
                steam.fillColor = StationPalette.wallTrim.withAlphaComponent(0.3)
                steam.strokeColor = .clear
                steam.position = CGPoint(x: CGFloat(i - 1) * 3, y: 14)
                steam.zPosition = 1
                steam.name = "steam_\(i)"
                container.addChild(steam)
            }
        case .pingPong:
            let ball = SKShapeNode(circleOfRadius: 2)
            ball.fillColor = StationPalette.statusIdle.withAlphaComponent(0.7)
            ball.strokeColor = .clear
            ball.name = "pingpong_ball"
            ball.zPosition = 1
            container.addChild(ball)
        case .arcade:
            let glow = SKShapeNode(rectOf: CGSize(width: 16, height: 12), cornerRadius: 2)
            glow.fillColor = StationPalette.consoleCyan.withAlphaComponent(0.2)
            glow.strokeColor = .clear
            glow.position = CGPoint(x: 0, y: 4)
            glow.zPosition = 1
            glow.name = "arcade_glow"
            container.addChild(glow)
        default:
            break
        }
    }

    // MARK: - Ambient Particles & Decorations

    private func renderAmbientParticles() {
        let dust = StationParticleFactory.corridorDust()
        dust.position = CGPoint(x: size.width / 2, y: size.height / 2)
        dust.zPosition = 4
        addChild(dust)

        // Console sparks at a few workstations
        for desk in OfficeLayout.desks where Int.random(in: 0..<3) == 0 {
            let sparks = StationParticleFactory.consoleSparks()
            sparks.position = CGPoint(x: desk.position.x, y: desk.position.y + 10)
            addChild(sparks)
        }
    }

    /// Add blinking status panels on module walls.
    private func addWallStatusPanels(in bounds: CGRect, count: Int) {
        for _ in 0..<count {
            let panel = SKShapeNode(rectOf: CGSize(width: 4, height: 3), cornerRadius: 0.5)
            let colors: [SKColor] = [StationPalette.consoleCyan, StationPalette.consoleSuccess, StationPalette.statusIdle]
            panel.fillColor = (colors.randomElement() ?? StationPalette.consoleCyan).withAlphaComponent(0.3)
            panel.strokeColor = .clear

            let onTop = Bool.random()
            if onTop {
                panel.position = CGPoint(
                    x: CGFloat.random(in: bounds.minX + 15 ... bounds.maxX - 15),
                    y: bounds.maxY - CGFloat.random(in: 18...22)
                )
            } else {
                let onLeft = Bool.random()
                panel.position = CGPoint(
                    x: onLeft ? bounds.minX + CGFloat.random(in: 6...12) : bounds.maxX - CGFloat.random(in: 6...12),
                    y: CGFloat.random(in: bounds.minY + 15 ... bounds.maxY - 22)
                )
            }
            panel.zPosition = 2

            let blinkDelay = Double.random(in: 1...6)
            panel.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.5, duration: 0.2),
                SKAction.fadeAlpha(to: 0.15, duration: 0.3),
                SKAction.wait(forDuration: blinkDelay),
            ])))
            addChild(panel)
        }
    }

    // MARK: - Theme Rendering

    private func renderThemeOverlay() {
        let overlay = SKSpriteNode(color: .clear, size: size)
        overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.zPosition = 5
        overlay.alpha = 0
        overlay.name = "themeOverlay"
        addChild(overlay)
        themeOverlay = overlay

        for desk in OfficeLayout.desks {
            let glow = SKShapeNode(circleOfRadius: 20)
            glow.fillColor = StationPalette.consoleCyan.withAlphaComponent(0.08)
            glow.strokeColor = .clear
            glow.position = CGPoint(x: desk.position.x, y: desk.position.y + 12)
            glow.zPosition = 8
            glow.alpha = 0
            glow.name = "lamp_\(desk.id)"
            addChild(glow)
            lampNodes[desk.id] = glow
        }
    }

    private func applyTheme() {
        guard let theme = themeEngine else { return }

        if let overlay = themeOverlay {
            overlay.color = theme.palette.overlayColor
            overlay.alpha = theme.palette.overlayAlpha
        }

        for desk in OfficeLayout.desks {
            guard let lampNode = lampNodes[desk.id] else { continue }
            let deskOccupied = agentSprites.values.contains { sprite in
                let dx = sprite.position.x - desk.position.x
                let dy = sprite.position.y - desk.position.y
                return dx * dx + dy * dy < 30 * 30
            }
            if deskOccupied {
                lampNode.alpha = 0.2
                if lampNode.action(forKey: "flicker") == nil {
                    lampNode.run(SKAction.repeatForever(SKAction.sequence([
                        SKAction.fadeAlpha(to: 0.15, duration: 0.8),
                        SKAction.fadeAlpha(to: 0.25, duration: 0.6),
                    ])), withKey: "flicker")
                }
            } else {
                lampNode.removeAction(forKey: "flicker")
                lampNode.alpha = 0
            }
        }

        if theme.seasonal.showSnow && snowNodes.isEmpty {
            addSnowDecorations()
        } else if !theme.seasonal.showSnow && !snowNodes.isEmpty {
            removeSnowDecorations()
        }
    }

    private func addSnowDecorations() {
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

    private func removeSnowDecorations() {
        snowNodes.forEach { $0.removeFromParent() }
        snowNodes.removeAll()
    }

    // MARK: - Frame Update

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        applyTheme()
        applyAgentMoods()

        if currentTime - interactionScanTime > 8 {
            interactionScanTime = currentTime
            scanForInteractions()
        }
        if currentTime - moodSpeechTime > 15 {
            moodSpeechTime = currentTime
            triggerRandomMoodSpeech()
        }
    }

    private func applyAgentMoods() {
        guard let moodEngine else { return }
        for (agentId, sprite) in agentSprites {
            sprite.updateMood(moodEngine.mood(for: agentId))
        }
    }

    // MARK: - Agent Interactions

    private func scanForInteractions() {
        let idleSprites = agentSprites.values.filter {
            !chattingAgents.contains($0.agentId) && $0.action(forKey: "move") == nil
        }
        guard idleSprites.count >= 2 else { return }

        for i in 0..<idleSprites.count {
            for j in (i + 1)..<idleSprites.count {
                let a = idleSprites[i], b = idleSprites[j]
                let dx = a.position.x - b.position.x, dy = a.position.y - b.position.y
                if sqrt(dx * dx + dy * dy) < 80, Double.random(in: 0...1) < 0.06 {
                    triggerIdleChat(between: a, and: b)
                    return
                }
            }
        }
    }

    private func triggerIdleChat(between a: AgentSprite, and b: AgentSprite) {
        let aId = a.agentId, bId = b.agentId
        chattingAgents.insert(aId)
        chattingAgents.insert(bId)

        let chatTopics = [
            ("Reactor's running hot", "Always does on Tuesdays"),
            ("Did you see the nebula?", "Gorgeous. Best view yet"),
            ("Tests are failing again", "It's always the tests"),
            ("Merge conflict time", "Who owns this repo?"),
            ("Coffee synth is broken", "Again? I just fixed it"),
            ("This PR is huge", "LGTM *eyes closed*"),
            ("Nav says we're off course", "We're always off course"),
        ]
        guard let topic = chatTopics.randomElement() else { return }

        a.showSpeechBubble(topic.0, duration: 2.5)
        b.run(SKAction.wait(forDuration: 3.0)) { [weak self, weak b] in
            b?.showSpeechBubble(topic.1, duration: 2.5)
            b?.run(SKAction.wait(forDuration: 3.5)) { [weak self] in
                self?.chattingAgents.remove(aId)
                self?.chattingAgents.remove(bId)
            }
        }
    }

    private func triggerRandomMoodSpeech() {
        let candidates = agentSprites.values.filter { !chattingAgents.contains($0.agentId) }
        candidates.randomElement()?.showMoodSpeech()
    }

    func broadcastCelebration(sourceId: String) {
        guard let src = agentSprites[sourceId] else { return }
        for (id, sprite) in agentSprites where id != sourceId {
            let dx = sprite.position.x - src.position.x, dy = sprite.position.y - src.position.y
            if sqrt(dx * dx + dy * dy) < 150 {
                let reactions = ["GG!", "Ship it!", "Mission complete!", "*claps*", "Stellar work!", "Nice!"]
                if let reaction = reactions.randomElement() {
                    sprite.run(SKAction.wait(forDuration: Double.random(in: 0.3...1.2))) { [weak sprite] in
                        sprite?.showSpeechBubble(reaction, duration: 2.0)
                    }
                }
            }
        }
    }

    // MARK: - Ambient Animations

    private func startAmbientAnimations() {
        if let coffeeStation = stationNodes[.coffeeMachine] {
            for i in 0..<3 {
                guard let steam = coffeeStation.childNode(withName: "steam_\(i)") else { continue }
                steam.run(SKAction.sequence([
                    SKAction.wait(forDuration: Double(i) * 0.4),
                    SKAction.repeatForever(SKAction.sequence([
                        SKAction.group([
                            SKAction.moveBy(x: CGFloat.random(in: -2...2), y: 8, duration: 1.2),
                            SKAction.fadeOut(withDuration: 1.2),
                        ]),
                        SKAction.run { [weak steam] in
                            steam?.position = CGPoint(x: CGFloat(i - 1) * 3, y: 14)
                            steam?.alpha = 0.3
                        },
                    ])),
                ]))
            }
        }

        if let ppStation = stationNodes[.pingPong],
           let ball = ppStation.childNode(withName: "pingpong_ball") {
            ball.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 12, y: 5, duration: 0.3),
                SKAction.moveBy(x: -12, y: -5, duration: 0.3),
                SKAction.moveBy(x: 12, y: -3, duration: 0.25),
                SKAction.moveBy(x: -12, y: 3, duration: 0.25),
            ])))
        }

        if let arcadeStation = stationNodes[.arcade],
           let glow = arcadeStation.childNode(withName: "arcade_glow") {
            glow.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.4, duration: 0.8),
                SKAction.fadeAlpha(to: 0.15, duration: 0.4),
                SKAction.fadeAlpha(to: 0.5, duration: 0.3),
                SKAction.fadeAlpha(to: 0.2, duration: 0.5),
            ])))
        }
    }

    // MARK: - Agent Sprite Management

    func addAgent(id: String, name: String, characterType: CharacterType) {
        guard agentSprites[id] == nil else { return }
        let sprite = AgentSprite(agentId: id, name: name, characterType: characterType)
        sprite.position = OfficeLayout.doorPosition
        sprite.zPosition = 10
        addChild(sprite)
        agentSprites[id] = sprite
    }

    func removeAgent(id: String) {
        guard let sprite = agentSprites[id] else { return }
        sprite.stopAnimations()
        sprite.run(SKAction.fadeOut(withDuration: 0.5)) { [weak self] in
            sprite.removeFromParent()
            self?.agentSprites.removeValue(forKey: id)
        }
    }

    func moveAgentToDesk(id: String, deskIndex: Int) {
        guard let sprite = agentSprites[id], deskIndex < OfficeLayout.desks.count else { return }
        let seatPos = CGPoint(x: OfficeLayout.desks[deskIndex].position.x, y: OfficeLayout.desks[deskIndex].position.y - 20)
        sprite.stopAnimations()
        sprite.updateStatus(.walking)
        sprite.moveTo(position: seatPos, duration: 1.5) {
            sprite.updateStatus(.working)
            sprite.startWorkAnimation()
        }
    }

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

    func moveAgentToStation(id: String, stationType: ActivityStationType) {
        guard let sprite = agentSprites[id],
              let station = ActivityStationLayout.stations.first(where: { $0.type == stationType }) else { return }
        let targetPos = CGPoint(
            x: station.position.x + CGFloat.random(in: -10...10),
            y: station.position.y + CGFloat.random(in: -8...8) + 20
        )
        sprite.updateStatus(.walking)
        sprite.stopAnimations()
        sprite.moveTo(position: targetPos, duration: 1.5) {
            sprite.updateStatus(.idle)
            sprite.startStationAnimation(stationType: stationType)
        }
    }

    func moveAgentToDoor(id: String) {
        guard let sprite = agentSprites[id] else { return }
        sprite.updateStatus(.leaving)
        sprite.stopAnimations()
        sprite.moveTo(position: OfficeLayout.doorPosition, duration: 1.5)
    }

    func celebrateAgent(id: String) {
        guard let sprite = agentSprites[id] else { return }
        sprite.updateStatus(.celebrating)
        sprite.startCelebrationAnimation()
        broadcastCelebration(sourceId: id)
    }

    func updateAgentName(id: String, name: String) { agentSprites[id]?.updateName(name) }
    func updateAgentStatus(id: String, status: AgentStatus) { agentSprites[id]?.updateStatus(status) }

    // MARK: - Desk Highlighting

    func highlightDesk(_ deskIndex: Int, occupied: Bool) {
        guard let deskNode = deskNodes[deskIndex] else { return }
        // The visual console is a separate node — highlight changes the invisible hit node's stroke
        // to show a cyan glow ring around the console
        if occupied {
            deskNode.strokeColor = StationPalette.consoleCyan.withAlphaComponent(0.4)
            deskNode.lineWidth = 1.5
            deskNode.glowWidth = 3
        } else {
            deskNode.strokeColor = .clear
            deskNode.lineWidth = 0
            deskNode.glowWidth = 0
        }
    }

    // MARK: - Touch Forwarding

    func agentTapped(agentId: String) { onAgentTapped?(agentId) }
}
