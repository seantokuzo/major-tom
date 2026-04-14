import SpriteKit

// MARK: - Office Scene

/// The main SpriteKit scene rendering Space Station Major Tom.
/// 1200×800 scene with camera zoom/pan, parallax starfield, animated airlocks,
/// and module-based rendering. Each module has distinct furniture, windows to space,
/// and ambient particle effects.
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

    /// Animated airlock door nodes (by door ID).
    private var airlockDoors: [String: (left: SKSpriteNode, right: SKSpriteNode, top: SKSpriteNode?, bottom: SKSpriteNode?)] = [:]

    // MARK: - Camera

    private var cameraNode: SKCameraNode!
    private let minCameraScale = StationLayout.minCameraScale
    private let maxCameraScale = StationLayout.maxCameraScale

    // Snap scrolling state
    private var currentSnapPosition: SnapPosition = .col1Top
    private var isSnapAnimating = false  // Prevent input during animation

    // Touch tracking for swipe/pinch/tap gestures
    private var lastPinchDistance: CGFloat?
    private var touchStartTime: TimeInterval = 0
    private var touchStartLocation: CGPoint = .zero  // In scene coordinates
    private var touchStartViewLocation: CGPoint = .zero  // In view coordinates
    private let swipeThreshold: CGFloat = 50  // Minimum swipe distance to trigger snap

    // MARK: - Theme & Mood

    var themeEngine: ThemeEngine?
    var moodEngine: MoodEngine?
    var spaceWeatherEngine: SpaceWeatherEngine?
    private var themeOverlay: SKSpriteNode?
    private var alertOverlay: SKSpriteNode?
    private var lampNodes: [Int: SKShapeNode] = [:]
    private var snowNodes: [SKShapeNode] = []
    private var interactionScanTime: TimeInterval = 0
    private var chattingAgents: Set<String> = []
    private var moodSpeechTime: TimeInterval = 0
    private var currentAlertState: StationAlertState = .normal

    /// Grid-based pathfinding engine for intra-room movement.
    let gridEngine = GridMovementEngine()

    /// All placed furniture for grid obstacle registration.
    private var furniturePlacements: [ModuleType: [FurniturePlacement]] = [:]

    /// Furniture registry for activity system — tracks types and occupancy.
    /// Non-optional: created at scene init so furniture is registered during didMove(to:).
    let furnitureRegistry = FurnitureRegistry()

    /// Furniture sprite nodes keyed by instance ID (for texture swaps during activities).
    private(set) var furnitureNodes: [String: SKNode] = [:]

    /// Guard against `didMove(to:)` being invoked more than once (e.g. SpriteView re-hosting).
    private var hasSetup = false

    // MARK: - Scene Lifecycle

    override func didMove(to view: SKView) {
        guard !hasSetup else { return }
        hasSetup = true
        super.didMove(to: view)
        backgroundColor = StationPalette.deepSpace
        size = CGSize(width: StationLayout.sceneWidth, height: StationLayout.sceneHeight)
        scaleMode = .aspectFill
        anchorPoint = CGPoint(x: 0, y: 0)

        // Enable multi-touch for pinch zoom
        view.isMultipleTouchEnabled = true

        // Setup camera — start at col1_top snap position
        cameraNode = SKCameraNode()
        cameraNode.position = StationLayout.snapCenter(for: .col1Top)
        cameraNode.setScale(StationLayout.defaultCameraScale)
        addChild(cameraNode)
        camera = cameraNode
        currentSnapPosition = .col1Top

        renderStationHull()
        renderCorridor()
        renderWindows()
        renderModuleFurniture()
        buildMovementGrids()
        renderDesks()
        renderAirlockDoors()
        renderMainAirlock()
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
    /// NOTE: Creates individual SKSpriteNodes per tile. Planned migration to SKTileMapNode
    /// (single draw call) in a follow-up wave for better GPU batching.
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

    // MARK: - Corridor Rendering

    /// Render all 6 corridor strips (3 per column) connecting vertically-adjacent rooms.
    private func renderCorridor() {
        for bounds in StationLayout.corridors {
            // Corridor floor — darker, industrial
            renderFloorPanels(in: bounds, moduleType: .engineering)

            // Guide lights along the corridor
            let lightSpacing: CGFloat = 80
            for x in stride(from: bounds.minX + 40, to: bounds.maxX - 30, by: lightSpacing) {
                let light = SKSpriteNode(
                    color: StationPalette.guideLightDim,
                    size: CGSize(width: 20, height: 3)
                )
                light.position = CGPoint(x: x, y: bounds.midY)
                light.zPosition = 0.8
                addChild(light)

                light.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.05, duration: 2.0),
                    SKAction.fadeAlpha(to: 0.2, duration: 2.0),
                ])))
            }

            // Corridor walls (top and bottom edges)
            let wallColor = StationPalette.hullPrimary.withAlphaComponent(0.6)
            let topWall = SKSpriteNode(color: wallColor, size: CGSize(width: bounds.width, height: 2))
            topWall.position = CGPoint(x: bounds.midX, y: bounds.maxY)
            topWall.zPosition = 1
            addChild(topWall)

            let bottomWall = SKSpriteNode(color: wallColor, size: CGSize(width: bounds.width, height: 2))
            bottomWall.position = CGPoint(x: bounds.midX, y: bounds.minY)
            bottomWall.zPosition = 1
            addChild(bottomWall)

            // "CORRIDOR" label centered
            let label = SKLabelNode(fontNamed: "Menlo")
            label.text = "CORRIDOR"
            label.fontSize = 6
            label.fontColor = StationPalette.ambientPanel.withAlphaComponent(0.25)
            label.position = CGPoint(x: bounds.midX, y: bounds.midY - 3)
            label.zPosition = 0.9
            addChild(label)
        }
    }

    // MARK: - Window Rendering

    private func renderWindows() {
        for (module, windowConfig) in StationLayout.allWindows {
            let window = createWindowNode(config: windowConfig, module: module)
            addChild(window)
            windowNodes.append(window)
        }
    }

    private func createWindowNode(config: WindowConfig, module _: StationModule) -> SKNode {
        let container = SKNode()
        container.position = config.position
        container.zPosition = 0.8
        container.name = "window"

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
        farStars.name = "starsFar"
        cropNode.addChild(farStars)

        let nearStars = StationParticleFactory.starFieldNear(size: emitterSize)
        nearStars.zPosition = 2
        nearStars.name = "starsNear"
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

    // MARK: - Grid Movement

    /// Register a furniture sprite as a grid obstacle and in the activity furniture registry.
    private func registerFurniture(_ node: SKNode, id: String, type furnitureType: String, in module: ModuleType) {
        let size: CGSize
        if let sprite = node as? SKSpriteNode {
            size = sprite.size
        } else {
            size = node.frame.size
        }
        let placement = FurniturePlacement(id: id, position: node.position, size: size)
        furniturePlacements[module, default: []].append(placement)

        // Register in activity furniture registry for occupancy tracking
        furnitureRegistry.register(
            id: id,
            furnitureType: furnitureType,
            room: module.rawValue,
            position: node.position
        )

        // Store node reference for texture swaps during activities
        furnitureNodes[id] = node
    }

    /// Build pathfinding grids for all rooms using registered furniture.
    private func buildMovementGrids() {
        gridEngine.buildAllGrids(furniturePlacements: furniturePlacements)
    }

    // MARK: - Module Furniture

    /// Place texture-based furniture in each module using StationLayout bounds.
    private func renderModuleFurniture() {
        renderCommandBridgeFurniture()
        renderEngineeringFurniture()
        renderCrewQuartersFurniture()
        renderGalleyFurniture()
        renderBioDomeFurniture()
        renderArboretumFurniture()
        renderTrainingBayFurniture()
        renderEVABayFurniture()
    }

    private func renderCommandBridgeFurniture() {
        guard let module = StationLayout.module(for: .commandBridge) else { return }
        let bounds = module.bounds
        let room = ModuleType.commandBridge

        // Captain's chair — center-upper area of the bridge
        let chair = StationFurnitureFactory.captainsChair()
        chair.position = CGPoint(x: bounds.midX, y: bounds.maxY - 100)
        chair.zPosition = 3
        addChild(chair)
        registerFurniture(chair, id: "bridge_chair", type: "captains_chair", in: room)

        // Tactical display — upper wall
        let tactical = StationFurnitureFactory.tacticalDisplay()
        tactical.position = CGPoint(x: bounds.midX, y: bounds.maxY - 40)
        tactical.zPosition = 3
        addChild(tactical)
        registerFurniture(tactical, id: "bridge_tactical", type: "tactical_display", in: room)

        // Status screens flanking the bridge
        let status1 = StationFurnitureFactory.statusScreen()
        status1.position = CGPoint(x: bounds.minX + 60, y: bounds.maxY - 60)
        status1.zPosition = 3
        addChild(status1)
        registerFurniture(status1, id: "bridge_status1", type: "status_screen", in: room)

        let status2 = StationFurnitureFactory.statusScreen()
        status2.position = CGPoint(x: bounds.maxX - 60, y: bounds.maxY - 60)
        status2.zPosition = 3
        addChild(status2)
        registerFurniture(status2, id: "bridge_status2", type: "status_screen", in: room)

        addWallStatusPanels(in: bounds, count: 4)
    }

    private func renderEngineeringFurniture() {
        guard let module = StationLayout.module(for: .engineering) else { return }
        let bounds = module.bounds
        let room = ModuleType.engineering

        // REACTOR CORE — centerpiece
        let reactor = StationFurnitureFactory.reactorCore()
        reactor.position = CGPoint(x: bounds.midX, y: bounds.midY + 40)
        reactor.zPosition = 3
        addChild(reactor)
        registerFurniture(reactor, id: "eng_reactor", type: "reactor_core", in: room)

        // Control panels flanking the reactor
        let panel1 = StationFurnitureFactory.controlPanel()
        panel1.position = CGPoint(x: bounds.minX + 80, y: bounds.midY + 120)
        panel1.zPosition = 3
        addChild(panel1)
        registerFurniture(panel1, id: "eng_panel1", type: "control_panel", in: room)

        let panel2 = StationFurnitureFactory.controlPanel()
        panel2.position = CGPoint(x: bounds.maxX - 80, y: bounds.midY + 120)
        panel2.zPosition = 3
        addChild(panel2)
        registerFurniture(panel2, id: "eng_panel2", type: "control_panel", in: room)

        // Tool rack on the left-lower
        let tools = StationFurnitureFactory.toolRack()
        tools.position = CGPoint(x: bounds.minX + 60, y: bounds.midY - 120)
        tools.zPosition = 3
        addChild(tools)
        registerFurniture(tools, id: "eng_tools", type: "tool_rack", in: room)

        // Storage crate on the right-lower
        let crate = StationFurnitureFactory.storageCrate()
        crate.position = CGPoint(x: bounds.maxX - 60, y: bounds.midY - 120)
        crate.zPosition = 3
        addChild(crate)
        registerFurniture(crate, id: "eng_crate", type: "storage_crate", in: room)
    }

    private func renderCrewQuartersFurniture() {
        guard let module = StationLayout.module(for: .crewQuarters) else { return }
        let bounds = module.bounds
        let room = ModuleType.crewQuarters

        // Bunks — 2 along upper wall (room is narrower now)
        let bunk1 = StationFurnitureFactory.bunkBed()
        bunk1.position = CGPoint(x: bounds.minX + 100, y: bounds.maxY - 80)
        bunk1.zPosition = 3
        addChild(bunk1)
        registerFurniture(bunk1, id: "crew_bunk1", type: "bunk_bed", in: room)

        let bunk2 = StationFurnitureFactory.bunkBed()
        bunk2.position = CGPoint(x: bounds.maxX - 100, y: bounds.maxY - 80)
        bunk2.zPosition = 3
        addChild(bunk2)
        registerFurniture(bunk2, id: "crew_bunk2", type: "bunk_bed", in: room)

        // Bunk 3 along upper-mid
        let bunk3 = StationFurnitureFactory.bunkBed()
        bunk3.position = CGPoint(x: bounds.midX, y: bounds.maxY - 180)
        bunk3.zPosition = 3
        addChild(bunk3)
        registerFurniture(bunk3, id: "crew_bunk3", type: "bunk_bed", in: room)

        // Couch in the lounge area
        let couch = StationFurnitureFactory.couch()
        couch.position = CGPoint(x: bounds.midX - 80, y: bounds.midY - 60)
        couch.zPosition = 3
        addChild(couch)
        registerFurniture(couch, id: "crew_couch", type: "couch", in: room)

        // Media screen on right wall area
        let media = StationFurnitureFactory.mediaScreen()
        media.position = CGPoint(x: bounds.maxX - 70, y: bounds.midY)
        media.zPosition = 3
        addChild(media)
        registerFurniture(media, id: "crew_media", type: "media_screen", in: room)

        // Floor lamp
        let lamp = StationFurnitureFactory.floorLampOn()
        lamp.position = CGPoint(x: bounds.midX + 120, y: bounds.midY - 100)
        lamp.zPosition = 3
        addChild(lamp)
        registerFurniture(lamp, id: "crew_lamp", type: "floor_lamp", in: room)

        addWallStatusPanels(in: bounds, count: 2)
    }

    private func renderGalleyFurniture() {
        guard let module = StationLayout.module(for: .galley) else { return }
        let bounds = module.bounds
        let room = ModuleType.galley

        // Food dispensers along the upper wall
        let disp1 = StationFurnitureFactory.foodDispenser()
        disp1.position = CGPoint(x: bounds.minX + 100, y: bounds.maxY - 70)
        disp1.zPosition = 3
        addChild(disp1)
        registerFurniture(disp1, id: "galley_disp1", type: "food_dispenser", in: room)

        let disp2 = StationFurnitureFactory.foodDispenser()
        disp2.position = CGPoint(x: bounds.minX + 220, y: bounds.maxY - 70)
        disp2.zPosition = 3
        addChild(disp2)
        registerFurniture(disp2, id: "galley_disp2", type: "food_dispenser", in: room)

        // Coffee machine
        let coffee = StationFurnitureFactory.coffeeMachine()
        coffee.position = CGPoint(x: bounds.maxX - 100, y: bounds.maxY - 70)
        coffee.zPosition = 3
        addChild(coffee)
        registerFurniture(coffee, id: "galley_coffee", type: "coffee_machine", in: room)

        // Dining table in center-lower
        let table = StationFurnitureFactory.diningTable()
        table.position = CGPoint(x: bounds.midX, y: bounds.midY - 40)
        table.zPosition = 3
        addChild(table)
        registerFurniture(table, id: "galley_table", type: "dining_table", in: room)

        addWallStatusPanels(in: bounds, count: 2)
    }

    private func renderBioDomeFurniture() {
        guard let module = StationLayout.module(for: .bioDome) else { return }
        let bounds = module.bounds
        let room = ModuleType.bioDome

        // Trees
        let tree1 = StationFurnitureFactory.tree()
        tree1.position = CGPoint(x: bounds.minX + 100, y: bounds.midY + 80)
        tree1.zPosition = 3
        addChild(tree1)
        registerFurniture(tree1, id: "bio_tree1", type: "tree", in: room)

        let tree2 = StationFurnitureFactory.tree()
        tree2.position = CGPoint(x: bounds.maxX - 100, y: bounds.midY + 80)
        tree2.zPosition = 3
        addChild(tree2)
        registerFurniture(tree2, id: "bio_tree2", type: "tree", in: room)

        // Water feature — center
        let water = StationFurnitureFactory.waterFeature()
        water.position = CGPoint(x: bounds.midX, y: bounds.midY - 60)
        water.zPosition = 3
        addChild(water)
        registerFurniture(water, id: "bio_water", type: "water_feature", in: room)

        // Office plants
        let plant1 = StationFurnitureFactory.officePlant()
        plant1.position = CGPoint(x: bounds.midX - 120, y: bounds.midY - 120)
        plant1.zPosition = 3
        addChild(plant1)
        registerFurniture(plant1, id: "bio_plant1", type: "office_plant", in: room)

        let plant2 = StationFurnitureFactory.officePlant()
        plant2.position = CGPoint(x: bounds.midX + 120, y: bounds.midY - 120)
        plant2.zPosition = 3
        addChild(plant2)
        registerFurniture(plant2, id: "bio_plant2", type: "office_plant", in: room)

        // Grow-light panels on ceiling
        for x in stride(from: bounds.minX + 60, to: bounds.maxX - 40, by: 100) {
            let light = SKSpriteNode(
                color: SKColor(red: 0.6, green: 0.3, blue: 0.8, alpha: 0.15),
                size: CGSize(width: 35, height: 4)
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

    private func renderArboretumFurniture() {
        guard let module = StationLayout.module(for: .arboretum) else { return }
        let bounds = module.bounds
        let room = ModuleType.arboretum

        // Tree — center upper
        let tree = StationFurnitureFactory.tree()
        tree.position = CGPoint(x: bounds.midX, y: bounds.midY + 100)
        tree.zPosition = 3
        addChild(tree)
        registerFurniture(tree, id: "arb_tree", type: "tree", in: room)

        // Park benches
        let bench1 = StationFurnitureFactory.parkBench()
        bench1.position = CGPoint(x: bounds.minX + 100, y: bounds.midY - 60)
        bench1.zPosition = 3
        addChild(bench1)
        registerFurniture(bench1, id: "arb_bench1", type: "park_bench", in: room)

        let bench2 = StationFurnitureFactory.parkBench()
        bench2.position = CGPoint(x: bounds.maxX - 100, y: bounds.midY - 60)
        bench2.zPosition = 3
        addChild(bench2)
        registerFurniture(bench2, id: "arb_bench2", type: "park_bench", in: room)

        // Pond
        let pond = StationFurnitureFactory.pond()
        pond.position = CGPoint(x: bounds.midX + 100, y: bounds.midY + 20)
        pond.zPosition = 3
        addChild(pond)
        registerFurniture(pond, id: "arb_pond", type: "pond", in: room)

        // Office plant
        let plant = StationFurnitureFactory.officePlant()
        plant.position = CGPoint(x: bounds.minX + 70, y: bounds.midY + 120)
        plant.zPosition = 3
        addChild(plant)
        registerFurniture(plant, id: "arb_plant", type: "office_plant", in: room)
    }

    private func renderTrainingBayFurniture() {
        guard let module = StationLayout.module(for: .trainingBay) else { return }
        let bounds = module.bounds
        let room = ModuleType.trainingBay

        // Treadmills — stacked vertically in narrower room
        let treadmill1 = StationFurnitureFactory.treadmill()
        treadmill1.position = CGPoint(x: bounds.minX + 120, y: bounds.midY + 80)
        treadmill1.zPosition = 3
        addChild(treadmill1)
        registerFurniture(treadmill1, id: "train_treadmill1", type: "treadmill", in: room)

        let treadmill2 = StationFurnitureFactory.treadmill()
        treadmill2.position = CGPoint(x: bounds.minX + 120, y: bounds.midY - 40)
        treadmill2.zPosition = 3
        addChild(treadmill2)
        registerFurniture(treadmill2, id: "train_treadmill2", type: "treadmill", in: room)

        // Weight rack
        let weights = StationFurnitureFactory.weightRack()
        weights.position = CGPoint(x: bounds.maxX - 120, y: bounds.midY + 80)
        weights.zPosition = 3
        addChild(weights)
        registerFurniture(weights, id: "train_weights", type: "weight_rack", in: room)

        // Equipment locker
        let locker = StationFurnitureFactory.equipmentLocker()
        locker.position = CGPoint(x: bounds.maxX - 80, y: bounds.midY - 80)
        locker.zPosition = 3
        addChild(locker)
        registerFurniture(locker, id: "train_locker", type: "equipment_locker", in: room)

        addWallStatusPanels(in: bounds, count: 2)
    }

    private func renderEVABayFurniture() {
        guard let module = StationLayout.module(for: .evaBay) else { return }
        let bounds = module.bounds
        let room = ModuleType.evaBay

        // Space suit racks — 3 arranged vertically in narrower room
        let suit1 = StationFurnitureFactory.spaceSuitRack()
        suit1.position = CGPoint(x: bounds.minX + 100, y: bounds.midY + 80)
        suit1.zPosition = 3
        addChild(suit1)
        registerFurniture(suit1, id: "eva_suit1", type: "space_suit_rack", in: room)

        let suit2 = StationFurnitureFactory.spaceSuitRack()
        suit2.position = CGPoint(x: bounds.midX, y: bounds.midY + 80)
        suit2.zPosition = 3
        addChild(suit2)
        registerFurniture(suit2, id: "eva_suit2", type: "space_suit_rack", in: room)

        let suit3 = StationFurnitureFactory.spaceSuitRack()
        suit3.position = CGPoint(x: bounds.maxX - 100, y: bounds.midY + 80)
        suit3.zPosition = 3
        addChild(suit3)
        registerFurniture(suit3, id: "eva_suit3", type: "space_suit_rack", in: room)

        // Storage crates — lower area
        let crate1 = StationFurnitureFactory.storageCrate()
        crate1.position = CGPoint(x: bounds.minX + 150, y: bounds.midY - 100)
        crate1.zPosition = 3
        addChild(crate1)
        registerFurniture(crate1, id: "eva_crate1", type: "storage_crate", in: room)

        let crate2 = StationFurnitureFactory.storageCrate()
        crate2.position = CGPoint(x: bounds.maxX - 150, y: bounds.midY - 100)
        crate2.zPosition = 3
        addChild(crate2)
        registerFurniture(crate2, id: "eva_crate2", type: "storage_crate", in: room)

        // Status screen
        let status = StationFurnitureFactory.statusScreen()
        status.position = CGPoint(x: bounds.midX, y: bounds.maxY - 50)
        status.zPosition = 3
        addChild(status)
        registerFurniture(status, id: "eva_status", type: "status_screen", in: room)

        addWallStatusPanels(in: bounds, count: 2)
    }

    // MARK: - Desk Rendering

    private func renderDesks() {
        for desk in OfficeLayout.desks {
            // Alternate desk textures for visual variety
            let console: SKSpriteNode = desk.id % 2 == 0
                ? StationFurnitureFactory.workstationDesk()
                : StationFurnitureFactory.workstationDesk2()
            console.position = desk.position
            console.zPosition = 3
            console.name = "consoleGroup_\(desk.id)"
            addChild(console)

            // Invisible hit-target for desk highlighting
            let hitNode = SKShapeNode(rectOf: CGSize(width: 100, height: 70), cornerRadius: 2)
            hitNode.fillColor = .clear
            hitNode.strokeColor = .clear
            hitNode.position = desk.position
            hitNode.zPosition = 3.1
            hitNode.name = "desk_\(desk.id)"
            addChild(hitNode)
            deskNodes[desk.id] = hitNode
        }
    }

    // MARK: - Airlock Doors (Animated)

    /// Render animated sliding airlock doors at module boundaries.
    private func renderAirlockDoors() {
        for door in StationLayout.doors {
            let container = SKNode()
            container.position = door.position
            container.zPosition = 3
            container.name = "door_\(door.id)"

            let panelSize: CGSize
            if door.isHorizontalSlide {
                panelSize = CGSize(width: door.size.width / 2 - 1, height: 4)
            } else {
                panelSize = CGSize(width: 4, height: door.size.height / 2 - 1)
            }

            if door.isHorizontalSlide {
                // Horizontal sliding panels (left/right)
                let leftDoor = SKSpriteNode(color: StationPalette.hullAccent, size: panelSize)
                leftDoor.position = CGPoint(x: -panelSize.width / 2 - 0.5, y: 0)
                leftDoor.name = "doorPanel_L"
                container.addChild(leftDoor)

                let rightDoor = SKSpriteNode(color: StationPalette.hullAccent, size: panelSize)
                rightDoor.position = CGPoint(x: panelSize.width / 2 + 0.5, y: 0)
                rightDoor.name = "doorPanel_R"
                container.addChild(rightDoor)

                airlockDoors[door.id] = (left: leftDoor, right: rightDoor, top: nil, bottom: nil)
            } else {
                // Vertical sliding panels (left/right for horizontal doors)
                let leftDoor = SKSpriteNode(color: StationPalette.hullAccent, size: panelSize)
                leftDoor.position = CGPoint(x: 0, y: -panelSize.height / 2 - 0.5)
                leftDoor.name = "doorPanel_L"
                container.addChild(leftDoor)

                let rightDoor = SKSpriteNode(color: StationPalette.hullAccent, size: panelSize)
                rightDoor.position = CGPoint(x: 0, y: panelSize.height / 2 + 0.5)
                rightDoor.name = "doorPanel_R"
                container.addChild(rightDoor)

                airlockDoors[door.id] = (left: leftDoor, right: rightDoor, top: nil, bottom: nil)
            }

            // Frame
            let frame = SKShapeNode(rectOf: door.size, cornerRadius: 1)
            frame.strokeColor = StationPalette.wallTrim.withAlphaComponent(0.4)
            frame.lineWidth = 1
            frame.fillColor = .clear
            frame.zPosition = 1
            container.addChild(frame)

            // Center seam glow
            let seam: SKSpriteNode
            if door.isHorizontalSlide {
                seam = SKSpriteNode(
                    color: StationPalette.consoleCyan.withAlphaComponent(0.2),
                    size: CGSize(width: 1, height: door.size.height - 4)
                )
            } else {
                seam = SKSpriteNode(
                    color: StationPalette.consoleCyan.withAlphaComponent(0.2),
                    size: CGSize(width: door.size.width - 4, height: 1)
                )
            }
            seam.zPosition = 2
            container.addChild(seam)

            addChild(container)
        }
    }

    /// Track open/close state per door to avoid redundant animations.
    private var openDoorIds: Set<String> = []

    /// Check all doors against all agent positions. A door opens if ANY agent is near.
    func checkDoorProximity(agentPosition: CGPoint) {
        let triggerDistance: CGFloat = 50

        for door in StationLayout.doors {
            guard let panels = airlockDoors[door.id] else { continue }

            // Check if any agent is near this door
            let anyAgentNear = agentSprites.values.contains { sprite in
                let dx = sprite.position.x - door.position.x
                let dy = sprite.position.y - door.position.y
                return sqrt(dx * dx + dy * dy) < triggerDistance
            }

            if anyAgentNear && !openDoorIds.contains(door.id) {
                openDoor(id: door.id, door: door, panels: panels)
            } else if !anyAgentNear && openDoorIds.contains(door.id) {
                closeDoor(id: door.id, door: door, panels: panels)
            }
        }
    }

    private func openDoor(id: String, door: DoorConfig, panels: (left: SKSpriteNode, right: SKSpriteNode, top: SKSpriteNode?, bottom: SKSpriteNode?)) {
        openDoorIds.insert(id)
        let duration: TimeInterval = 0.3

        if door.isHorizontalSlide {
            let slide = door.size.width / 2 + 2
            let openL = CGPoint(x: -(slide / 2 + door.size.width / 4), y: 0)
            let openR = CGPoint(x: slide / 2 + door.size.width / 4, y: 0)
            panels.left.run(SKAction.move(to: openL, duration: duration), withKey: "doorAnim")
            panels.right.run(SKAction.move(to: openR, duration: duration), withKey: "doorAnim")
        } else {
            let slide = door.size.height / 2 + 2
            let openL = CGPoint(x: 0, y: -(slide / 2 + door.size.height / 4))
            let openR = CGPoint(x: 0, y: slide / 2 + door.size.height / 4)
            panels.left.run(SKAction.move(to: openL, duration: duration), withKey: "doorAnim")
            panels.right.run(SKAction.move(to: openR, duration: duration), withKey: "doorAnim")
        }

        HapticService.impact(.light)
    }

    private func closeDoor(id: String, door: DoorConfig, panels: (left: SKSpriteNode, right: SKSpriteNode, top: SKSpriteNode?, bottom: SKSpriteNode?)) {
        guard panels.left.action(forKey: "doorAnim") == nil else { return }
        openDoorIds.remove(id)
        let duration: TimeInterval = 0.4

        if door.isHorizontalSlide {
            let panelW = door.size.width / 4 - 0.5
            let closedL = CGPoint(x: -panelW - 0.5, y: 0)
            let closedR = CGPoint(x: panelW + 0.5, y: 0)
            panels.left.run(SKAction.move(to: closedL, duration: duration), withKey: "doorAnim")
            panels.right.run(SKAction.move(to: closedR, duration: duration), withKey: "doorAnim")
        } else {
            let panelH = door.size.height / 4 - 0.5
            let closedL = CGPoint(x: 0, y: -panelH - 0.5)
            let closedR = CGPoint(x: 0, y: panelH + 0.5)
            panels.left.run(SKAction.move(to: closedL, duration: duration), withKey: "doorAnim")
            panels.right.run(SKAction.move(to: closedR, duration: duration), withKey: "doorAnim")
        }
    }

    /// Draw the main station airlock (entry/exit).
    private func renderMainAirlock() {
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
        // Corridor dust — centered on station
        let dust = StationParticleFactory.corridorDust()
        dust.position = CGPoint(x: size.width / 2, y: size.height / 2)
        dust.particlePositionRange = CGVector(dx: size.width, dy: size.height)
        dust.zPosition = 4
        addChild(dust)

        // Console sparks at some workstations
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

    /// Theme and alert overlays are children of the camera node so they stay fixed on screen.
    private func renderThemeOverlay() {
        let overlaySize = CGSize(width: size.width * 2, height: size.height * 2)

        let overlay = SKSpriteNode(color: .clear, size: overlaySize)
        overlay.zPosition = 100
        overlay.alpha = 0
        overlay.name = "themeOverlay"
        cameraNode.addChild(overlay)
        themeOverlay = overlay

        // Alert overlay (red/blue/yellow wash)
        let alert = SKSpriteNode(color: .clear, size: overlaySize)
        alert.zPosition = 101
        alert.alpha = 0
        alert.name = "alertOverlay"
        cameraNode.addChild(alert)
        alertOverlay = alert

        // Console glow halos at desks
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

        // Apply alert state to overlay and status strips
        applyAlertState(theme: theme)

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

    // MARK: - Alert State

    /// Apply alert state to status strips and alert overlay.
    private func applyAlertState(theme: ThemeEngine) {
        let newState = theme.alertState
        guard newState != currentAlertState else { return }
        currentAlertState = newState

        // Update alert overlay
        if let alert = alertOverlay {
            alert.run(SKAction.group([
                SKAction.colorize(with: theme.alertOverlayColor, colorBlendFactor: 1.0, duration: 0.5),
                SKAction.fadeAlpha(to: theme.alertOverlayAlpha, duration: 0.5),
            ]))
        }

        // Update all status strips
        let stripColor = theme.alertStripColor
        for module in StationLayout.modules {
            if let strip = childNode(withName: "statusStrip_\(module.type.rawValue)") as? SKSpriteNode {
                strip.removeAllActions()
                strip.run(SKAction.colorize(with: stripColor, colorBlendFactor: 1.0, duration: 0.3))

                let (lo, hi, dur): (CGFloat, CGFloat, TimeInterval) = {
                    switch newState {
                    case .normal:      return (0.15, 0.35, 2.5)
                    case .attention:   return (0.2, 0.5, 1.5)
                    case .alert:       return (0.3, 0.7, 0.6)
                    case .celebration: return (0.2, 0.5, 1.2)
                    }
                }()
                strip.run(SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: lo, duration: dur),
                    SKAction.fadeAlpha(to: hi, duration: dur),
                ])))
            }
        }

        // Haptic feedback for alert changes
        switch newState {
        case .normal:      break
        case .attention:   HapticService.impact(.light)
        case .alert:       HapticService.impact(.heavy); HapticService.notification(.warning)
        case .celebration: HapticService.notification(.success)
        }
    }

    // MARK: - Space Weather Events

    /// Handle a space weather event — called by SpaceWeatherEngine callback.
    func handleWeatherEvent(_ event: SpaceWeatherEvent) {
        switch event {
        case .solarFlare:    triggerSolarFlare()
        case .meteorShower:  triggerMeteorShower()
        case .nebulaPassage: triggerNebulaPassage()
        case .stationRumble: triggerStationRumble()
        case .commsBurst:    triggerCommsBurst()
        }
    }

    private func triggerSolarFlare() {
        // Golden wash — attached to camera so it fills screen regardless of pan
        let flash = SKSpriteNode(
            color: SKColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 0),
            size: CGSize(width: size.width * 2, height: size.height * 2)
        )
        flash.zPosition = 90
        cameraNode.addChild(flash)

        flash.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.12, duration: 0.8),
            SKAction.wait(forDuration: 2.0),
            SKAction.fadeAlpha(to: 0, duration: 1.5),
            SKAction.removeFromParent(),
        ]))

        HapticService.impact(.medium)
    }

    private func triggerMeteorShower() {
        // Bright diagonal streaks — attached to camera
        for i in 0..<6 {
            let delay = Double(i) * 0.5

            cameraNode.run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { [weak self] in
                    guard let self else { return }
                    let streak = SKShapeNode()
                    let path = CGMutablePath()
                    let startX = CGFloat.random(in: -self.size.width / 2 ... self.size.width / 2)
                    let startY = CGFloat.random(in: 0 ... self.size.height / 2)
                    path.move(to: CGPoint(x: startX, y: startY))
                    path.addLine(to: CGPoint(x: startX - 80, y: startY - 50))
                    streak.path = path
                    streak.strokeColor = StationPalette.starWhite.withAlphaComponent(0.7)
                    streak.lineWidth = 1.5
                    streak.glowWidth = 3
                    streak.zPosition = 85
                    self.cameraNode.addChild(streak)

                    streak.run(SKAction.sequence([
                        SKAction.fadeOut(withDuration: 0.6),
                        SKAction.removeFromParent(),
                    ]))
                },
            ]))
        }

        for i in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) {
                HapticService.impact(.rigid)
            }
        }
    }

    private func triggerNebulaPassage() {
        let nebulaOverlay = SKSpriteNode(
            color: StationPalette.nebulaPink.withAlphaComponent(0.5),
            size: CGSize(width: size.width * 2, height: size.height * 2)
        )
        nebulaOverlay.zPosition = 89
        nebulaOverlay.alpha = 0
        cameraNode.addChild(nebulaOverlay)

        nebulaOverlay.run(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.04, duration: 10),
            SKAction.wait(forDuration: 20),
            SKAction.fadeAlpha(to: 0, duration: 10),
            SKAction.removeFromParent(),
        ]))
    }

    /// Camera shake — replaces the old "move all children" approach.
    private func triggerStationRumble() {
        let shakeActions: [SKAction] = (0..<8).flatMap { _ -> [SKAction] in
            let dx = CGFloat.random(in: -4...4)
            let dy = CGFloat.random(in: -3...3)
            return [
                SKAction.moveBy(x: dx, y: dy, duration: 0.04),
                SKAction.moveBy(x: -dx, y: -dy, duration: 0.04),
            ]
        }

        cameraNode.run(SKAction.sequence(shakeActions), withKey: "rumble")

        HapticService.impact(.heavy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            HapticService.impact(.heavy)
        }
    }

    private func triggerCommsBurst() {
        for desk in OfficeLayout.desks {
            if let consoleGroup = childNode(withName: "consoleGroup_\(desk.id)") {
                let flash = SKSpriteNode(
                    color: SKColor(white: 0.8, alpha: 0.3),
                    size: CGSize(width: 80, height: 50)
                )
                flash.position = CGPoint(x: 0, y: 20)
                flash.zPosition = 10
                consoleGroup.addChild(flash)

                flash.run(SKAction.sequence([
                    SKAction.fadeOut(withDuration: 0.15),
                    SKAction.removeFromParent(),
                ]))
            }
        }
        HapticService.impact(.light)
    }

    // MARK: - Frame Update

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        applyTheme()
        applyAgentMoods()
        updateParallax()
        updateDoorProximity()

        // Purge expired cell reservations every ~60 frames (~1s)
        if Int(currentTime * 60) % 60 == 0 {
            gridEngine.purgeExpiredReservations()
        }

        if currentTime - interactionScanTime > 8 {
            interactionScanTime = currentTime
            scanForInteractions()
        }
        if currentTime - moodSpeechTime > 15 {
            moodSpeechTime = currentTime
            triggerRandomMoodSpeech()
        }
    }

    // MARK: - Parallax

    /// Shift window starfield layers based on camera offset to create depth parallax.
    private func updateParallax() {
        let cameraOffset = CGPoint(
            x: cameraNode.position.x - size.width / 2,
            y: cameraNode.position.y - size.height / 2
        )

        for windowNode in windowNodes {
            // Far stars: shift 3% of camera offset (deep, barely moves)
            if let farStars = windowNode.childNode(withName: "//starsFar") {
                farStars.position = CGPoint(x: cameraOffset.x * 0.03, y: cameraOffset.y * 0.03)
            }
            // Near stars: shift 6% of camera offset (closer, moves more)
            if let nearStars = windowNode.childNode(withName: "//starsNear") {
                nearStars.position = CGPoint(x: cameraOffset.x * 0.06, y: cameraOffset.y * 0.06)
            }
        }
    }

    // MARK: - Door Proximity Check

    /// Check all doors against all agents once per frame.
    private func updateDoorProximity() {
        // Single call checks all doors against all agents internally
        checkDoorProximity(agentPosition: .zero)
    }

    // MARK: - Agent Moods

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

        // Idle sprites scatter across random rooms; real agents spawn at airlock
        if id.hasPrefix("idle-") {
            let module = StationLayout.modules.randomElement()!
            let bounds = module.bounds
            let margin: CGFloat = 60
            let position = CGPoint(
                x: CGFloat.random(in: (bounds.minX + margin)...(bounds.maxX - margin)),
                y: CGFloat.random(in: (bounds.minY + margin)...(bounds.maxY - margin))
            )
            // Use grid engine to find nearest walkable cell
            if let path = gridEngine.findPath(from: position, to: position, in: module.type) {
                sprite.position = path.last ?? position
            } else {
                sprite.position = position
            }
            sprite.updateModule(module.type)
            sprite.startIdleAnimation()
        } else {
            sprite.position = OfficeLayout.doorPosition
        }

        sprite.zPosition = 10
        addChild(sprite)
        agentSprites[id] = sprite
    }

    func removeAgent(id: String) {
        guard let sprite = agentSprites[id] else { return }
        gridEngine.releaseAllReservations(for: id)
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
        gridEngine.releaseAllReservations(for: id)
        let waypoints = gridEngine.findFullPath(from: sprite.position, to: seatPos, agentId: id)
        sprite.moveAlongPath(waypoints) {
            sprite.updateStatus(.working)
            sprite.updateModule(.commandBridge)
            sprite.startWorkAnimation()
        }
    }

    func moveAgentToBreakArea(id: String, areaType: OfficeAreaType) {
        guard let sprite = agentSprites[id] else { return }
        let position = OfficeLayout.randomPosition(in: areaType)
        sprite.updateStatus(.walking)
        sprite.stopAnimations()
        gridEngine.releaseAllReservations(for: id)
        let waypoints = gridEngine.findFullPath(from: sprite.position, to: position, agentId: id)
        sprite.moveAlongPath(waypoints) {
            sprite.updateStatus(.idle)
            let arrivedModule = StationLayout.module(at: position)?.type
            sprite.updateModule(arrivedModule)
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
        gridEngine.releaseAllReservations(for: id)
        let waypoints = gridEngine.findFullPath(from: sprite.position, to: targetPos, agentId: id)
        sprite.moveAlongPath(waypoints) {
            sprite.updateStatus(.idle)
            let arrivedModule = StationLayout.module(at: targetPos)?.type
            sprite.updateModule(arrivedModule)
            sprite.startStationAnimation(stationType: stationType)
        }
    }

    /// Move an agent to perform a JSON-configured activity at furniture.
    /// The optional `onArrival` callback fires after the agent reaches the target and starts animating.
    func moveAgentToActivity(id: String, assignment: ActivityAssignment, onArrival: ((AgentSprite) -> Void)? = nil) {
        guard let sprite = agentSprites[id] else { return }
        sprite.updateStatus(.walking)
        sprite.stopAnimations()
        gridEngine.releaseAllReservations(for: id)
        let waypoints = gridEngine.findFullPath(from: sprite.position, to: assignment.targetPosition, agentId: id)
        sprite.moveAlongPath(waypoints) {
            sprite.updateStatus(.idle)
            let arrivedModule = StationLayout.module(at: assignment.targetPosition)?.type
            sprite.updateModule(arrivedModule)
            // Use animation ID from the activity definition if available
            if let animId = assignment.animationID {
                sprite.startActivityAnimation(animId)
            } else {
                sprite.startIdleAnimation()
            }
            onArrival?(sprite)
        }
    }

    /// Get the room (ModuleType rawValue) an agent is currently in.
    func currentRoom(for agentId: String) -> String? {
        guard let sprite = agentSprites[agentId] else { return nil }
        return StationLayout.module(at: sprite.position)?.type.rawValue
    }

    func moveAgentToDoor(id: String) {
        guard let sprite = agentSprites[id] else { return }
        sprite.updateStatus(.leaving)
        sprite.stopAnimations()
        gridEngine.releaseAllReservations(for: id)
        let waypoints = gridEngine.findFullPath(from: sprite.position, to: OfficeLayout.doorPosition, agentId: id)
        sprite.moveAlongPath(waypoints) {
            sprite.updateModule(nil)
        }
    }

    func celebrateAgent(id: String) {
        guard let sprite = agentSprites[id] else { return }
        sprite.updateStatus(.celebrating)
        sprite.startCelebrationAnimation()
        sprite.showEmote(.star)
        broadcastCelebration(sourceId: id)
    }

    func updateAgentName(id: String, name: String) { agentSprites[id]?.updateName(name) }
    func updateAgentStatus(id: String, status: AgentStatus) { agentSprites[id]?.updateStatus(status) }

    // MARK: - Desk Highlighting

    func highlightDesk(_ deskIndex: Int, occupied: Bool) {
        guard let deskNode = deskNodes[deskIndex] else { return }
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

    // MARK: - Touch Handling (Snap Scroll / Pinch Zoom / Tap)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let view else { return }
        guard !isSnapAnimating else { return }

        if let allTouches = event?.allTouches, allTouches.count >= 2 {
            // Two fingers → start pinch zoom
            let touchArray = Array(allTouches)
            let p1 = touchArray[0].location(in: view)
            let p2 = touchArray[1].location(in: view)
            lastPinchDistance = hypot(p1.x - p2.x, p1.y - p2.y)
        } else if let touch = touches.first {
            // Single finger → potential swipe or tap
            touchStartTime = CACurrentMediaTime()
            touchStartLocation = touch.location(in: self)
            touchStartViewLocation = touch.location(in: view)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let view else { return }
        guard !isSnapAnimating else { return }

        if let allTouches = event?.allTouches, allTouches.count >= 2 {
            // Pinch zoom — keep for detail viewing
            let touchArray = Array(allTouches)
            let p1 = touchArray[0].location(in: view)
            let p2 = touchArray[1].location(in: view)
            let currentDistance = hypot(p1.x - p2.x, p1.y - p2.y)

            if let prevDist = lastPinchDistance, prevDist > 0 {
                let scaleFactor = prevDist / currentDistance
                let newScale = max(minCameraScale, min(maxCameraScale, cameraNode.xScale * scaleFactor))
                cameraNode.setScale(newScale)
            }
            lastPinchDistance = currentDistance
        }
        // Single finger moves are tracked but NOT applied as pan — swipe direction computed on touchesEnded
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isSnapAnimating else {
            lastPinchDistance = nil
            return
        }

        guard let touch = touches.first, let view else {
            lastPinchDistance = nil
            return
        }

        let endViewLocation = touch.location(in: view)
        let elapsed = CACurrentMediaTime() - touchStartTime

        // Calculate swipe distance in view coordinates
        let dx = endViewLocation.x - touchStartViewLocation.x
        let dy = endViewLocation.y - touchStartViewLocation.y
        let swipeDistance = hypot(dx, dy)

        if swipeDistance > swipeThreshold {
            // Determine dominant swipe direction
            if abs(dx) > abs(dy) {
                // Horizontal swipe — switch columns
                if dx > 0 {
                    // Swipe RIGHT → move to left column (or stay)
                    handleSwipeRight()
                } else {
                    // Swipe LEFT → move to right column (or stay)
                    handleSwipeLeft()
                }
            } else {
                // Vertical swipe — natural scroll direction (like scrolling a webpage)
                // Finger moves DOWN (dy > 0) → reveal upper rooms (handleSwipeUp moves camera up)
                // Finger moves UP (dy < 0) → reveal lower rooms (handleSwipeDown moves camera down)
                if dy > 0 {
                    handleSwipeUp()
                } else {
                    handleSwipeDown()
                }
            }
        } else if elapsed < 0.3 {
            // Short tap → check for agent hit
            let location = touchStartLocation
            let hitNodes = nodes(at: location)
            for node in hitNodes {
                if let agentSprite = node as? AgentSprite {
                    onAgentTapped?(agentSprite.agentId)
                    break
                }
                if let parent = node.parent as? AgentSprite {
                    onAgentTapped?(parent.agentId)
                    break
                }
            }
        }

        lastPinchDistance = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastPinchDistance = nil
    }

    // MARK: - Snap Scrolling

    // MARK: - Camera Position Helpers

    /// The X center for column 1.
    private var col1CenterX: CGFloat { StationLayout.col1X + StationLayout.roomWidth / 2 }
    /// The X center for column 2.
    private var col2CenterX: CGFloat { StationLayout.col2X + StationLayout.roomWidth / 2 }
    /// The X midpoint between columns (threshold for determining current column).
    private var columnMidX: CGFloat { (col1CenterX + col2CenterX) / 2 }
    /// Whether camera is currently in column 1.
    private var isInCol1: Bool { cameraNode.position.x < columnMidX }

    /// Camera Y for showing rows N and N+1 (N=0 is top).
    private func pairCenterY(topRow: Int) -> CGFloat {
        let rh = StationLayout.roomHeight
        let ch = StationLayout.corridorHeight
        let topOfPair = StationLayout.sceneHeight - CGFloat(topRow) * (rh + ch)
        return topOfPair - rh - ch / 2
    }

    /// The topmost Y the camera can meaningfully be (rows 0+1).
    private var topPairY: CGFloat { pairCenterY(topRow: 0) }
    /// The bottommost Y the camera can meaningfully be (rows 2+3).
    private var bottomPairY: CGFloat { pairCenterY(topRow: 2) }
    /// The middle Y (rows 1+2).
    private var midPairY: CGFloat { pairCenterY(topRow: 1) }

    /// Swipe UP → reveal upper rooms (move camera Y up by one row pair step)
    private func handleSwipeUp() {
        let currentY = cameraNode.position.y
        let currentX = cameraNode.position.x

        // Find next higher Y position
        let targetY: CGFloat
        if currentY < midPairY - 50 {
            targetY = midPairY   // bottom → mid
        } else if currentY < topPairY - 50 {
            targetY = topPairY   // mid → top
        } else {
            return // Already at top
        }
        snapToCenter(CGPoint(x: currentX, y: targetY))
    }

    /// Swipe DOWN → reveal lower rooms (move camera Y down by one row pair step)
    private func handleSwipeDown() {
        let currentY = cameraNode.position.y
        let currentX = cameraNode.position.x

        let targetY: CGFloat
        if currentY > midPairY + 50 {
            targetY = midPairY     // top → mid
        } else if currentY > bottomPairY + 50 {
            targetY = bottomPairY  // mid → bottom
        } else {
            return // Already at bottom
        }
        snapToCenter(CGPoint(x: currentX, y: targetY))
    }

    /// Swipe LEFT → switch to column 2, preserving current Y position
    private func handleSwipeLeft() {
        guard isInCol1 else { return }
        snapToCenter(CGPoint(x: col2CenterX, y: cameraNode.position.y))
    }

    /// Swipe RIGHT → switch to column 1, preserving current Y position
    private func handleSwipeRight() {
        guard !isInCol1 else { return }
        snapToCenter(CGPoint(x: col1CenterX, y: cameraNode.position.y))
    }

    /// Animate camera to the given snap position. Resets scale to default.
    private func snapTo(_ position: SnapPosition) {
        guard !isSnapAnimating else { return }
        isSnapAnimating = true
        currentSnapPosition = position

        let target = StationLayout.snapCenter(for: position)
        let moveAction = SKAction.move(to: target, duration: 0.3)
        moveAction.timingMode = .easeInEaseOut
        let scaleAction = SKAction.scale(to: StationLayout.defaultCameraScale, duration: 0.3)
        scaleAction.timingMode = .easeInEaseOut

        cameraNode.run(SKAction.group([moveAction, scaleAction])) { [weak self] in
            self?.isSnapAnimating = false
        }
        HapticService.impact(.light)
    }

    /// Public snap API for mini-map overlay to call.
    func snapToPosition(_ position: SnapPosition) {
        snapTo(position)
    }

    /// Snap camera to an arbitrary center point (for mini-map free selection).
    func snapToCenter(_ center: CGPoint) {
        guard !isSnapAnimating else { return }
        isSnapAnimating = true

        // Find closest snap position for tracking
        let snapPositions = SnapPosition.allCases
        currentSnapPosition = snapPositions.min(by: {
            let a = StationLayout.snapCenter(for: $0)
            let b = StationLayout.snapCenter(for: $1)
            return hypot(a.x - center.x, a.y - center.y) < hypot(b.x - center.x, b.y - center.y)
        }) ?? .col1Top

        let moveAction = SKAction.move(to: center, duration: 0.3)
        moveAction.timingMode = .easeInEaseOut
        let scaleAction = SKAction.scale(to: StationLayout.defaultCameraScale, duration: 0.3)
        scaleAction.timingMode = .easeInEaseOut

        cameraNode.run(SKAction.group([moveAction, scaleAction])) { [weak self] in
            self?.isSnapAnimating = false
        }
        HapticService.impact(.light)
    }

    // MARK: - Camera Public API

    /// Zoom level for external UI (0 = max zoom in, 1 = default, higher = zoomed out).
    var currentZoomLevel: CGFloat {
        cameraNode.xScale
    }

    /// The current snap position for external UI (e.g., mini-map).
    var activeSnapPosition: SnapPosition {
        currentSnapPosition
    }

    /// Smoothly move camera to a position.
    func panCamera(to position: CGPoint, duration: TimeInterval = 0.5) {
        cameraNode.run(SKAction.move(to: position, duration: duration))
    }

    /// Smoothly zoom to a scale.
    func zoomCamera(to scale: CGFloat, duration: TimeInterval = 0.3) {
        let clamped = max(minCameraScale, min(maxCameraScale, scale))
        cameraNode.run(SKAction.scale(to: clamped, duration: duration))
    }

    /// Reset camera to default snap position and zoom.
    func resetCamera(animated: Bool = true) {
        if animated {
            snapTo(.col1Top)
        } else {
            cameraNode.position = StationLayout.snapCenter(for: .col1Top)
            cameraNode.setScale(StationLayout.defaultCameraScale)
            currentSnapPosition = .col1Top
        }
    }

    // MARK: - Legacy Touch Forwarding (kept for compatibility)

    func agentTapped(agentId: String) { onAgentTapped?(agentId) }
}
