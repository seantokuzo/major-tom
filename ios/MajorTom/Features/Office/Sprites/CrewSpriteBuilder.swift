import SpriteKit

// MARK: - Facing Direction

/// The four cardinal directions a crew sprite can face.
enum FacingDirection: String, CaseIterable {
    case front
    case back
    case left
    case right

    /// Determine facing direction from a movement vector.
    static func from(dx: CGFloat, dy: CGFloat) -> FacingDirection {
        // Favor horizontal over vertical when diagonal
        if abs(dx) > abs(dy) {
            return dx > 0 ? .right : .left
        } else {
            return dy > 0 ? .back : .front
        }
    }
}

// MARK: - Crew Sprite Builder

/// Loads crew sprite textures from the CrewSprites atlas.
/// Replaces PixelArtBuilder's programmatic pixel-node approach with
/// texture-based rendering — one SKTexture per direction per character.
enum CrewSpriteBuilder {

    /// The sprite atlas containing all crew textures.
    private static let atlas = SKTextureAtlas(named: "CrewSprites")

    /// Texture cache keyed by "characterType_direction".
    private static var textureCache: [String: SKTexture] = [:]

    /// The default display size for crew sprites in the scene.
    /// Source art is ~400px, scaled down to this size by SpriteKit.
    /// Sized at 80×80 for the 1240×2620 two-column grid station layout.
    static let spriteSize = CGSize(width: 80, height: 80)

    /// Dog types use the same 80×80 frame in the new layout.
    static let dogSpriteSize = CGSize(width: 80, height: 80)

    private static let dogTypes: Set<CharacterType> = [
        .elvis, .senor, .steve, .esteban, .hoku, .kai,
    ]

    // MARK: - Public API

    /// Get the texture for a character facing a given direction.
    static func texture(for type: CharacterType, facing direction: FacingDirection) -> SKTexture {
        let key = "\(type.rawValue)_\(direction.rawValue)"

        if let cached = textureCache[key] {
            return cached
        }

        let texture = atlas.textureNamed(key)
        texture.filteringMode = .nearest  // Preserve pixel art crispness
        textureCache[key] = texture
        return texture
    }

    /// Characters known to have walk textures (populated on first check).
    private static var walkTextureAvailability: [String: Bool] = [:]

    /// Get the two walk frame textures for a direction (for animation).
    /// Returns nil only if the character definitely has no walk textures.
    static func walkFrames(for type: CharacterType, direction: FacingDirection) -> [SKTexture]? {
        let side = (direction == .left || direction == .front) ? "Left" : "Right"
        let key1 = "\(type.rawValue)_walk\(side)1"
        let key2 = "\(type.rawValue)_walk\(side)2"

        // Check cache first
        if let cached1 = textureCache[key1], let cached2 = textureCache[key2] {
            return [cached1, cached2]
        }

        // Check if we already know this character lacks walk textures
        let availKey = "\(type.rawValue)_walk"
        if walkTextureAvailability[availKey] == false {
            return nil
        }

        // Try loading — textureNamed returns a placeholder if missing.
        // We detect placeholders by checking if the texture size is tiny (<=4px).
        let tex1 = atlas.textureNamed(key1)
        tex1.filteringMode = .nearest

        if tex1.size().width <= 4 {
            // Placeholder texture — this character has no walk sprites
            walkTextureAvailability[availKey] = false
            return nil
        }

        let tex2 = atlas.textureNamed(key2)
        tex2.filteringMode = .nearest
        textureCache[key1] = tex1
        textureCache[key2] = tex2
        walkTextureAvailability[availKey] = true
        return [tex1, tex2]
    }

    /// Get the appropriate sprite size for a character type.
    static func size(for type: CharacterType) -> CGSize {
        dogTypes.contains(type) ? dogSpriteSize : spriteSize
    }

    /// Build an SKSpriteNode with the front-facing texture for a character.
    /// This is the simple entry point — callers can update the texture later
    /// via `updateTexture(_:facing:)` for direction changes.
    static func build(for type: CharacterType, facing direction: FacingDirection = .front) -> SKSpriteNode {
        let tex = texture(for: type, facing: direction)
        let node = SKSpriteNode(texture: tex, size: size(for: type))
        node.name = "crewSprite_\(type.rawValue)"
        return node
    }

    /// Update an existing sprite node's texture for a new facing direction.
    static func updateTexture(_ node: SKSpriteNode, type: CharacterType, facing direction: FacingDirection) {
        let tex = texture(for: type, facing: direction)
        node.texture = tex
        node.size = size(for: type)
    }

    /// Preload all textures to avoid hitches during gameplay.
    static func preloadAll(completion: @escaping () -> Void) {
        atlas.preload(completionHandler: completion)
    }

    /// All available texture names in the atlas (for debugging).
    static var textureNames: [String] {
        atlas.textureNames.sorted()
    }
}
