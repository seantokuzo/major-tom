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
    /// Sized at 80×80 for the 1200×3200 vertically-scrolling station layout.
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
