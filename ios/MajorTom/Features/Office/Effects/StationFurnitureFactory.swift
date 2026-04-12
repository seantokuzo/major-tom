import SpriteKit

// MARK: - Station Furniture Factory

/// Creates texture-based furniture sprites for each station module.
/// All textures are loaded from the StationFurniture sprite atlas (DALL-E pixel art).
/// Uses `.nearest` filtering for pixel art crispness.
enum StationFurnitureFactory {

    /// The sprite atlas containing all furniture textures.
    private static let atlas = SKTextureAtlas(named: "StationFurniture")

    /// Texture cache keyed by imageset name.
    private static var textureCache: [String: SKTexture] = [:]

    // MARK: - Texture Loading

    /// Load a texture from the atlas with nearest-neighbor filtering for pixel art.
    private static func texture(named name: String) -> SKTexture {
        if let cached = textureCache[name] {
            return cached
        }
        let tex = atlas.textureNamed(name)
        tex.filteringMode = .nearest
        textureCache[name] = tex
        return tex
    }

    /// Create a sprite node from a named texture at the given size.
    private static func sprite(named name: String, size: CGSize) -> SKSpriteNode {
        let tex = texture(named: name)
        let node = SKSpriteNode(texture: tex, size: size)
        node.name = "furniture_\(name)"
        return node
    }

    // MARK: - Command Bridge

    /// Workstation desk for agent seating — used at desk positions.
    /// Scaled for 600×640 rooms (was 120×80 for 1200×350 rooms).
    static func workstationDesk() -> SKSpriteNode {
        sprite(named: "workstation_desk1", size: CGSize(width: 100, height: 70))
    }

    /// Alternate workstation desk variant.
    static func workstationDesk2() -> SKSpriteNode {
        sprite(named: "workstation_desk2", size: CGSize(width: 100, height: 70))
    }

    /// Captain's chair — centerpiece of the Command Bridge.
    static func captainsChair() -> SKSpriteNode {
        sprite(named: "captains_chair", size: CGSize(width: 80, height: 80))
    }

    /// Large tactical display screen on wall.
    static func tacticalDisplay() -> SKNode {
        let node = sprite(named: "tactical_display", size: CGSize(width: 130, height: 90))

        // Subtle animated glow overlay for the screen
        let glow = SKShapeNode(rectOf: CGSize(width: 110, height: 70), cornerRadius: 2)
        glow.fillColor = .clear
        glow.strokeColor = StationPalette.consoleCyan.withAlphaComponent(0.08)
        glow.lineWidth = 2
        glow.glowWidth = 3
        glow.zPosition = 1
        node.addChild(glow)

        glow.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 2.0),
            SKAction.fadeAlpha(to: 0.8, duration: 2.0),
        ])))

        return node
    }

    /// Status screen — smaller data readout.
    static func statusScreen() -> SKSpriteNode {
        sprite(named: "status_screen", size: CGSize(width: 70, height: 50))
    }

    // MARK: - Engineering

    /// Reactor core with pulsing animation overlay.
    static func reactorCore() -> SKNode {
        let node = sprite(named: "reactor_core", size: CGSize(width: 130, height: 130))

        // Pulsing glow overlay on the core
        let glow = SKShapeNode(circleOfRadius: 25)
        glow.fillColor = StationPalette.consoleCyan.withAlphaComponent(0.15)
        glow.strokeColor = .clear
        glow.glowWidth = 8
        glow.zPosition = 1
        node.addChild(glow)

        glow.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.15, duration: 1.5),
                SKAction.fadeAlpha(to: 0.4, duration: 1.5),
            ]),
            SKAction.group([
                SKAction.scale(to: 0.9, duration: 1.5),
                SKAction.fadeAlpha(to: 0.8, duration: 1.5),
            ]),
        ])))

        return node
    }

    /// Control panel — wall-mounted engineering panel.
    static func controlPanel() -> SKSpriteNode {
        sprite(named: "control_panel", size: CGSize(width: 80, height: 70))
    }

    /// Tool rack for engineering equipment.
    static func toolRack() -> SKSpriteNode {
        sprite(named: "tool_rack", size: CGSize(width: 65, height: 100))
    }

    /// Storage crate — generic cargo.
    static func storageCrate() -> SKSpriteNode {
        sprite(named: "storage_crate", size: CGSize(width: 65, height: 55))
    }

    // MARK: - Crew Quarters

    /// Bunk bed for crew rest.
    static func bunkBed() -> SKSpriteNode {
        sprite(named: "bunk_bed", size: CGSize(width: 80, height: 80))
    }

    /// Couch / lounge seating.
    static func couch() -> SKSpriteNode {
        sprite(named: "couch", size: CGSize(width: 100, height: 55))
    }

    /// Media entertainment screen.
    static func mediaScreen() -> SKSpriteNode {
        sprite(named: "media_screen", size: CGSize(width: 80, height: 65))
    }

    /// Floor lamp (lit variant).
    static func floorLampOn() -> SKNode {
        let node = sprite(named: "floor_lamp_on", size: CGSize(width: 35, height: 80))

        // Warm glow circle around the lamp
        let glow = SKShapeNode(circleOfRadius: 25)
        glow.fillColor = SKColor(red: 1.0, green: 0.9, blue: 0.6, alpha: 0.06)
        glow.strokeColor = .clear
        glow.position = CGPoint(x: 0, y: 20)
        glow.zPosition = -1
        node.addChild(glow)

        glow.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.5, duration: 2.0),
            SKAction.fadeAlpha(to: 1.0, duration: 2.0),
        ])))

        return node
    }

    // MARK: - Galley

    /// Food dispenser / vending unit.
    static func foodDispenser() -> SKSpriteNode {
        sprite(named: "food_dispenser", size: CGSize(width: 65, height: 100))
    }

    /// Coffee machine / beverage synthesizer.
    static func coffeeMachine() -> SKSpriteNode {
        sprite(named: "coffee_machine", size: CGSize(width: 50, height: 80))
    }

    /// Dining table.
    static func diningTable() -> SKSpriteNode {
        sprite(named: "dining_table", size: CGSize(width: 110, height: 70))
    }

    // MARK: - Bio-Dome

    /// Tree — large plant for nature modules.
    static func tree() -> SKSpriteNode {
        sprite(named: "tree", size: CGSize(width: 80, height: 100))
    }

    /// Water feature — decorative pool.
    static func waterFeature() -> SKNode {
        let node = sprite(named: "water_feature", size: CGSize(width: 100, height: 70))

        // Shimmer overlay
        let shimmer = SKShapeNode(ellipseOf: CGSize(width: 50, height: 22))
        shimmer.fillColor = SKColor(red: 0.10, green: 0.25, blue: 0.40, alpha: 0.15)
        shimmer.strokeColor = .clear
        shimmer.position = CGPoint(x: -5, y: -5)
        shimmer.zPosition = 1
        node.addChild(shimmer)

        shimmer.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 2.0),
            SKAction.fadeAlpha(to: 0.8, duration: 2.0),
        ])))

        return node
    }

    /// Small office plant in a pot.
    static func officePlant() -> SKSpriteNode {
        sprite(named: "office_plant", size: CGSize(width: 50, height: 65))
    }

    // MARK: - Arboretum

    /// Park bench for seating.
    static func parkBench() -> SKSpriteNode {
        sprite(named: "park_bench", size: CGSize(width: 80, height: 45))
    }

    /// Pond — water body in the arboretum.
    static func pond() -> SKSpriteNode {
        sprite(named: "pond", size: CGSize(width: 110, height: 80))
    }

    // MARK: - Training Bay

    /// Treadmill exercise equipment.
    static func treadmill() -> SKSpriteNode {
        sprite(named: "treadmill", size: CGSize(width: 65, height: 55))
    }

    /// Weight rack / strength equipment.
    static func weightRack() -> SKSpriteNode {
        sprite(named: "weight_rack", size: CGSize(width: 65, height: 75))
    }

    /// Equipment locker for storage.
    static func equipmentLocker() -> SKSpriteNode {
        sprite(named: "equipment_locker", size: CGSize(width: 65, height: 100))
    }

    // MARK: - EVA Bay

    /// Space suit on display rack.
    static func spaceSuitRack() -> SKSpriteNode {
        sprite(named: "space_suit_rack", size: CGSize(width: 65, height: 110))
    }

    // MARK: - Preloading

    /// Preload all furniture textures to avoid hitches.
    static func preloadAll(completion: @escaping () -> Void) {
        atlas.preload(completionHandler: completion)
    }
}
