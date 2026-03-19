import SpriteKit

// MARK: - Pixel Art Builder

/// Builds programmatic pixel art sprites for all 9 Office character types.
/// Each character is constructed from small colored SKSpriteNode "pixels"
/// arranged in recognizable patterns — no external image assets needed.
enum PixelArtBuilder {

    /// The size of each "pixel" in the sprite art.
    static let pixelSize: CGFloat = 2

    /// Build the pixel art node tree for a given character type.
    /// Returns an SKNode container with all pixel children, centered at (0,0).
    static func build(for type: CharacterType) -> SKNode {
        switch type {
        case .dev:
            return buildDev()
        case .officeWorker:
            return buildOfficeWorker()
        case .pm:
            return buildPM()
        case .clown:
            return buildClown()
        case .frankenstein:
            return buildFrankenstein()
        case .dachshund:
            return buildDachshund()
        case .cattleDog:
            return buildCattleDog()
        case .schnauzerBlack:
            return buildSchnauzer(isBlack: true)
        case .schnauzerPepper:
            return buildSchnauzer(isBlack: false)
        }
    }

    // MARK: - Pixel Helpers

    /// Place a single pixel at grid coordinates. (0,0) is center of the sprite.
    private static func pixel(
        x: Int,
        y: Int,
        color: SKColor,
        in container: SKNode
    ) {
        let node = SKSpriteNode(color: color, size: CGSize(width: pixelSize, height: pixelSize))
        node.position = CGPoint(
            x: CGFloat(x) * pixelSize,
            y: CGFloat(y) * pixelSize
        )
        node.zPosition = 0
        container.addChild(node)
    }

    /// Place a horizontal run of pixels.
    private static func hRun(
        x: Int,
        y: Int,
        count: Int,
        color: SKColor,
        in container: SKNode
    ) {
        for i in 0..<count {
            pixel(x: x + i, y: y, color: color, in: container)
        }
    }

    /// Place a vertical run of pixels.
    private static func vRun(
        x: Int,
        y: Int,
        count: Int,
        color: SKColor,
        in container: SKNode
    ) {
        for i in 0..<count {
            pixel(x: x, y: y + i, color: color, in: container)
        }
    }

    /// Fill a rectangle of pixels.
    private static func rect(
        x: Int,
        y: Int,
        w: Int,
        h: Int,
        color: SKColor,
        in container: SKNode
    ) {
        for row in 0..<h {
            for col in 0..<w {
                pixel(x: x + col, y: y + row, color: color, in: container)
            }
        }
    }

    // MARK: - Color Palette

    // Skin tones
    private static let skin = SKColor(red: 0.95, green: 0.80, blue: 0.65, alpha: 1)
    private static let skinShadow = SKColor(red: 0.85, green: 0.70, blue: 0.55, alpha: 1)

    // Hair
    private static let hairBrown = SKColor(red: 0.40, green: 0.25, blue: 0.15, alpha: 1)
    private static let hairBlack = SKColor(red: 0.15, green: 0.12, blue: 0.10, alpha: 1)

    // Clothing
    private static let hoodieBlue = SKColor(red: 0.25, green: 0.55, blue: 0.85, alpha: 1)
    private static let hoodieDark = SKColor(red: 0.18, green: 0.42, blue: 0.68, alpha: 1)
    private static let shirtWhite = SKColor(red: 0.90, green: 0.90, blue: 0.92, alpha: 1)
    private static let shirtGray = SKColor(red: 0.75, green: 0.75, blue: 0.78, alpha: 1)
    private static let tieRed = SKColor(red: 0.85, green: 0.20, blue: 0.20, alpha: 1)
    private static let pantsNavy = SKColor(red: 0.15, green: 0.18, blue: 0.30, alpha: 1)
    private static let pantsDark = SKColor(red: 0.20, green: 0.20, blue: 0.25, alpha: 1)
    private static let shoes = SKColor(red: 0.22, green: 0.18, blue: 0.15, alpha: 1)

    // Tech
    private static let screenGlow = SKColor(red: 0.40, green: 0.85, blue: 1.0, alpha: 1)
    private static let headphoneBlack = SKColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1)

    // PM
    private static let pmKhaki = SKColor(red: 0.82, green: 0.75, blue: 0.60, alpha: 1)
    private static let pmShirt = SKColor(red: 0.35, green: 0.60, blue: 0.80, alpha: 1)
    private static let clipboard = SKColor(red: 0.70, green: 0.55, blue: 0.35, alpha: 1)
    private static let clipboardPage = SKColor(red: 0.95, green: 0.93, blue: 0.88, alpha: 1)

    // Clown
    private static let clownRed = SKColor(red: 0.95, green: 0.15, blue: 0.15, alpha: 1)
    private static let clownYellow = SKColor(red: 1.0, green: 0.90, blue: 0.20, alpha: 1)
    private static let clownGreen = SKColor(red: 0.20, green: 0.85, blue: 0.40, alpha: 1)
    private static let clownPurple = SKColor(red: 0.65, green: 0.25, blue: 0.90, alpha: 1)
    private static let clownOrange = SKColor(red: 1.0, green: 0.55, blue: 0.15, alpha: 1)
    private static let clownPink = SKColor(red: 0.95, green: 0.40, blue: 0.60, alpha: 1)
    private static let noseRed = SKColor(red: 0.95, green: 0.20, blue: 0.20, alpha: 1)

    // Frankenstein
    private static let frankGreen = SKColor(red: 0.45, green: 0.75, blue: 0.40, alpha: 1)
    private static let frankDarkGreen = SKColor(red: 0.35, green: 0.60, blue: 0.30, alpha: 1)
    private static let boltGray = SKColor(red: 0.70, green: 0.72, blue: 0.75, alpha: 1)
    private static let stitchBlack = SKColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
    private static let frankJacket = SKColor(red: 0.25, green: 0.22, blue: 0.20, alpha: 1)

    // Dog colors
    private static let dachshundBrown = SKColor(red: 0.72, green: 0.42, blue: 0.18, alpha: 1)
    private static let dachshundDark = SKColor(red: 0.55, green: 0.30, blue: 0.12, alpha: 1)
    private static let dachshundBelly = SKColor(red: 0.85, green: 0.60, blue: 0.35, alpha: 1)

    private static let cattleBlue = SKColor(red: 0.40, green: 0.50, blue: 0.65, alpha: 1)
    private static let cattleDarkBlue = SKColor(red: 0.30, green: 0.38, blue: 0.50, alpha: 1)
    private static let cattleRed = SKColor(red: 0.80, green: 0.35, blue: 0.25, alpha: 1)
    private static let cattleTan = SKColor(red: 0.85, green: 0.72, blue: 0.55, alpha: 1)

    private static let schnauzerDark = SKColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1)
    private static let schnauzerBeard = SKColor(red: 0.25, green: 0.25, blue: 0.30, alpha: 1)
    private static let pepperLight = SKColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1)
    private static let pepperMid = SKColor(red: 0.38, green: 0.38, blue: 0.42, alpha: 1)
    private static let pepperDark = SKColor(red: 0.22, green: 0.22, blue: 0.25, alpha: 1)

    // Eyes
    private static let eyeWhite = SKColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1)
    private static let eyeBlack = SKColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
    private static let dogEye = SKColor(red: 0.20, green: 0.12, blue: 0.08, alpha: 1)
    private static let dogNose = SKColor(red: 0.10, green: 0.08, blue: 0.06, alpha: 1)

    // MARK: - Human Builders (32x32 grid, centered at 0,0 -> coords from -8 to +7)

    /// Developer: hoodie, headphones, laptop glow
    private static func buildDev() -> SKNode {
        let n = SKNode()
        let ox = -8 // offset so grid maps -8..+7
        let oy = -8

        // Hair (top of head)
        hRun(x: ox+5, y: oy+15, count: 6, color: hairBrown, in: n)
        hRun(x: ox+4, y: oy+14, count: 8, color: hairBrown, in: n)

        // Head / face
        rect(x: ox+5, y: oy+11, w: 6, h: 3, color: skin, in: n)
        // Eyes
        pixel(x: ox+6, y: oy+12, color: eyeWhite, in: n)
        pixel(x: ox+7, y: oy+12, color: eyeBlack, in: n)
        pixel(x: ox+9, y: oy+12, color: eyeWhite, in: n)
        pixel(x: ox+10, y: oy+12, color: eyeBlack, in: n)
        // Mouth
        hRun(x: ox+7, y: oy+11, count: 2, color: skinShadow, in: n)

        // Headphones
        pixel(x: ox+4, y: oy+13, color: headphoneBlack, in: n)
        pixel(x: ox+4, y: oy+12, color: headphoneBlack, in: n)
        pixel(x: ox+11, y: oy+13, color: headphoneBlack, in: n)
        pixel(x: ox+11, y: oy+12, color: headphoneBlack, in: n)
        hRun(x: ox+5, y: oy+15, count: 6, color: headphoneBlack, in: n)

        // Hoodie body
        rect(x: ox+4, y: oy+5, w: 8, h: 6, color: hoodieBlue, in: n)
        // Hoodie pocket
        hRun(x: ox+6, y: oy+6, count: 4, color: hoodieDark, in: n)
        // Hood strings
        pixel(x: ox+7, y: oy+10, color: shirtWhite, in: n)
        pixel(x: ox+9, y: oy+10, color: shirtWhite, in: n)

        // Arms
        vRun(x: ox+3, y: oy+5, count: 5, color: hoodieBlue, in: n)
        vRun(x: ox+12, y: oy+5, count: 5, color: hoodieBlue, in: n)
        // Hands
        pixel(x: ox+3, y: oy+5, color: skin, in: n)
        pixel(x: ox+12, y: oy+5, color: skin, in: n)

        // Pants
        rect(x: ox+5, y: oy+2, w: 3, h: 3, color: pantsDark, in: n)
        rect(x: ox+8, y: oy+2, w: 3, h: 3, color: pantsDark, in: n)

        // Shoes
        hRun(x: ox+4, y: oy+1, count: 4, color: shoes, in: n)
        hRun(x: ox+8, y: oy+1, count: 4, color: shoes, in: n)

        // Laptop glow effect (subtle) on torso
        pixel(x: ox+6, y: oy+7, color: screenGlow, in: n)
        pixel(x: ox+7, y: oy+7, color: screenGlow, in: n)
        pixel(x: ox+8, y: oy+7, color: screenGlow, in: n)
        pixel(x: ox+9, y: oy+7, color: screenGlow, in: n)

        return n
    }

    /// Office Worker: button-up shirt, tie, neat hair
    private static func buildOfficeWorker() -> SKNode {
        let n = SKNode()
        let ox = -8
        let oy = -8

        // Hair
        hRun(x: ox+5, y: oy+15, count: 6, color: hairBlack, in: n)
        hRun(x: ox+4, y: oy+14, count: 8, color: hairBlack, in: n)
        // Part line
        pixel(x: ox+7, y: oy+14, color: SKColor(red: 0.25, green: 0.20, blue: 0.18, alpha: 1), in: n)

        // Head / face
        rect(x: ox+5, y: oy+11, w: 6, h: 3, color: skin, in: n)
        // Eyes
        pixel(x: ox+6, y: oy+12, color: eyeWhite, in: n)
        pixel(x: ox+7, y: oy+12, color: eyeBlack, in: n)
        pixel(x: ox+9, y: oy+12, color: eyeWhite, in: n)
        pixel(x: ox+10, y: oy+12, color: eyeBlack, in: n)
        // Mouth
        hRun(x: ox+7, y: oy+11, count: 2, color: skinShadow, in: n)

        // Shirt body (white button-up)
        rect(x: ox+4, y: oy+5, w: 8, h: 6, color: shirtWhite, in: n)
        // Button line
        vRun(x: ox+8, y: oy+5, count: 6, color: shirtGray, in: n)
        // Tie
        pixel(x: ox+8, y: oy+10, color: tieRed, in: n)
        pixel(x: ox+8, y: oy+9, color: tieRed, in: n)
        pixel(x: ox+7, y: oy+8, color: tieRed, in: n)
        pixel(x: ox+8, y: oy+8, color: tieRed, in: n)
        pixel(x: ox+9, y: oy+8, color: tieRed, in: n)
        pixel(x: ox+8, y: oy+7, color: tieRed, in: n)
        pixel(x: ox+8, y: oy+6, color: tieRed, in: n)

        // Arms
        vRun(x: ox+3, y: oy+5, count: 5, color: shirtWhite, in: n)
        vRun(x: ox+12, y: oy+5, count: 5, color: shirtWhite, in: n)
        pixel(x: ox+3, y: oy+5, color: skin, in: n)
        pixel(x: ox+12, y: oy+5, color: skin, in: n)

        // Pants
        rect(x: ox+5, y: oy+2, w: 3, h: 3, color: pantsNavy, in: n)
        rect(x: ox+8, y: oy+2, w: 3, h: 3, color: pantsNavy, in: n)

        // Shoes
        hRun(x: ox+4, y: oy+1, count: 4, color: shoes, in: n)
        hRun(x: ox+8, y: oy+1, count: 4, color: shoes, in: n)

        return n
    }

    /// Project Manager: business casual, clipboard
    private static func buildPM() -> SKNode {
        let n = SKNode()
        let ox = -8
        let oy = -8

        // Hair (styled)
        hRun(x: ox+5, y: oy+15, count: 6, color: hairBrown, in: n)
        hRun(x: ox+4, y: oy+14, count: 8, color: hairBrown, in: n)
        pixel(x: ox+4, y: oy+13, color: hairBrown, in: n)

        // Head / face
        rect(x: ox+5, y: oy+11, w: 6, h: 3, color: skin, in: n)
        // Eyes
        pixel(x: ox+6, y: oy+12, color: eyeWhite, in: n)
        pixel(x: ox+7, y: oy+12, color: eyeBlack, in: n)
        pixel(x: ox+9, y: oy+12, color: eyeWhite, in: n)
        pixel(x: ox+10, y: oy+12, color: eyeBlack, in: n)
        // Smile
        pixel(x: ox+7, y: oy+11, color: skinShadow, in: n)
        pixel(x: ox+9, y: oy+11, color: skinShadow, in: n)

        // Button-up shirt (blue, business casual)
        rect(x: ox+4, y: oy+5, w: 8, h: 6, color: pmShirt, in: n)
        // Collar
        pixel(x: ox+6, y: oy+10, color: shirtWhite, in: n)
        pixel(x: ox+10, y: oy+10, color: shirtWhite, in: n)

        // Arms
        vRun(x: ox+3, y: oy+5, count: 5, color: pmShirt, in: n)
        vRun(x: ox+12, y: oy+5, count: 5, color: pmShirt, in: n)
        pixel(x: ox+3, y: oy+5, color: skin, in: n)
        pixel(x: ox+12, y: oy+5, color: skin, in: n)

        // Clipboard (held in left hand area)
        rect(x: ox+1, y: oy+5, w: 2, h: 4, color: clipboard, in: n)
        rect(x: ox+1, y: oy+6, w: 2, h: 2, color: clipboardPage, in: n)
        // Clip
        pixel(x: ox+1, y: oy+9, color: boltGray, in: n)
        pixel(x: ox+2, y: oy+9, color: boltGray, in: n)

        // Khaki pants
        rect(x: ox+5, y: oy+2, w: 3, h: 3, color: pmKhaki, in: n)
        rect(x: ox+8, y: oy+2, w: 3, h: 3, color: pmKhaki, in: n)

        // Shoes
        hRun(x: ox+4, y: oy+1, count: 4, color: shoes, in: n)
        hRun(x: ox+8, y: oy+1, count: 4, color: shoes, in: n)

        return n
    }

    /// Office Clown: rainbow hair, red nose, colorful outfit
    private static func buildClown() -> SKNode {
        let n = SKNode()
        let ox = -8
        let oy = -8

        // Rainbow hair (big, poofy)
        hRun(x: ox+4, y: oy+15, count: 2, color: clownRed, in: n)
        hRun(x: ox+6, y: oy+15, count: 2, color: clownOrange, in: n)
        hRun(x: ox+8, y: oy+15, count: 2, color: clownYellow, in: n)
        hRun(x: ox+10, y: oy+15, count: 2, color: clownGreen, in: n)
        hRun(x: ox+3, y: oy+14, count: 2, color: clownRed, in: n)
        hRun(x: ox+5, y: oy+14, count: 2, color: clownOrange, in: n)
        hRun(x: ox+7, y: oy+14, count: 2, color: clownYellow, in: n)
        hRun(x: ox+9, y: oy+14, count: 2, color: clownGreen, in: n)
        hRun(x: ox+11, y: oy+14, count: 2, color: clownPurple, in: n)
        // Extra poof
        pixel(x: ox+3, y: oy+15, color: clownPurple, in: n)
        pixel(x: ox+12, y: oy+15, color: clownPurple, in: n)

        // Face (white like clown makeup)
        let clownFace = SKColor(red: 0.95, green: 0.92, blue: 0.90, alpha: 1)
        rect(x: ox+5, y: oy+11, w: 6, h: 3, color: clownFace, in: n)
        // Eyes (big, expressive)
        pixel(x: ox+6, y: oy+12, color: eyeBlack, in: n)
        pixel(x: ox+10, y: oy+12, color: eyeBlack, in: n)
        // Red nose (center, prominent)
        pixel(x: ox+7, y: oy+12, color: noseRed, in: n)
        pixel(x: ox+8, y: oy+12, color: noseRed, in: n)
        pixel(x: ox+7, y: oy+11, color: noseRed, in: n)
        pixel(x: ox+8, y: oy+11, color: noseRed, in: n)
        // Big smile
        pixel(x: ox+6, y: oy+11, color: clownRed, in: n)
        pixel(x: ox+10, y: oy+11, color: clownRed, in: n)

        // Colorful outfit (alternating)
        rect(x: ox+4, y: oy+7, w: 4, h: 4, color: clownYellow, in: n)
        rect(x: ox+8, y: oy+7, w: 4, h: 4, color: clownPurple, in: n)
        rect(x: ox+4, y: oy+5, w: 4, h: 2, color: clownGreen, in: n)
        rect(x: ox+8, y: oy+5, w: 4, h: 2, color: clownOrange, in: n)
        // Big buttons
        pixel(x: ox+8, y: oy+9, color: clownRed, in: n)
        pixel(x: ox+8, y: oy+7, color: clownGreen, in: n)

        // Arms
        vRun(x: ox+3, y: oy+5, count: 5, color: clownPink, in: n)
        vRun(x: ox+12, y: oy+5, count: 5, color: clownPink, in: n)
        // Big gloves
        pixel(x: ox+2, y: oy+5, color: shirtWhite, in: n)
        pixel(x: ox+3, y: oy+5, color: shirtWhite, in: n)
        pixel(x: ox+12, y: oy+5, color: shirtWhite, in: n)
        pixel(x: ox+13, y: oy+5, color: shirtWhite, in: n)

        // Pants
        rect(x: ox+5, y: oy+2, w: 3, h: 3, color: clownPurple, in: n)
        rect(x: ox+8, y: oy+2, w: 3, h: 3, color: clownYellow, in: n)

        // Big shoes
        hRun(x: ox+3, y: oy+1, count: 5, color: clownRed, in: n)
        hRun(x: ox+8, y: oy+1, count: 5, color: clownRed, in: n)

        return n
    }

    /// Frankenstein: green skin, flat top, bolts, stitches, dark jacket
    private static func buildFrankenstein() -> SKNode {
        let n = SKNode()
        let ox = -8
        let oy = -8

        // Flat top head (distinctive flat shape)
        hRun(x: ox+4, y: oy+15, count: 8, color: hairBlack, in: n)
        hRun(x: ox+4, y: oy+14, count: 8, color: hairBlack, in: n)

        // Green head (taller, blocky)
        rect(x: ox+4, y: oy+11, w: 8, h: 3, color: frankGreen, in: n)
        // Brow ridge
        hRun(x: ox+4, y: oy+13, count: 8, color: frankDarkGreen, in: n)
        // Eyes (deep set, angry looking)
        pixel(x: ox+5, y: oy+12, color: eyeWhite, in: n)
        pixel(x: ox+6, y: oy+12, color: eyeBlack, in: n)
        pixel(x: ox+9, y: oy+12, color: eyeBlack, in: n)
        pixel(x: ox+10, y: oy+12, color: eyeWhite, in: n)
        // Mouth / stitches across face
        hRun(x: ox+5, y: oy+11, count: 6, color: stitchBlack, in: n)
        // Vertical stitch
        vRun(x: ox+8, y: oy+11, count: 3, color: stitchBlack, in: n)

        // Neck bolts
        pixel(x: ox+3, y: oy+12, color: boltGray, in: n)
        pixel(x: ox+12, y: oy+12, color: boltGray, in: n)
        pixel(x: ox+3, y: oy+11, color: boltGray, in: n)
        pixel(x: ox+12, y: oy+11, color: boltGray, in: n)

        // Dark jacket / body (bigger, bulkier)
        rect(x: ox+3, y: oy+5, w: 10, h: 6, color: frankJacket, in: n)
        // Shirt underneath
        vRun(x: ox+7, y: oy+5, count: 6, color: frankDarkGreen, in: n)
        vRun(x: ox+8, y: oy+5, count: 6, color: frankDarkGreen, in: n)

        // Arms (thick)
        vRun(x: ox+2, y: oy+5, count: 5, color: frankJacket, in: n)
        vRun(x: ox+13, y: oy+5, count: 5, color: frankJacket, in: n)
        // Green hands
        pixel(x: ox+2, y: oy+5, color: frankGreen, in: n)
        pixel(x: ox+13, y: oy+5, color: frankGreen, in: n)

        // Pants
        rect(x: ox+4, y: oy+2, w: 4, h: 3, color: pantsDark, in: n)
        rect(x: ox+8, y: oy+2, w: 4, h: 3, color: pantsDark, in: n)

        // Big boots
        hRun(x: ox+3, y: oy+1, count: 5, color: shoes, in: n)
        hRun(x: ox+8, y: oy+1, count: 5, color: shoes, in: n)

        return n
    }

    // MARK: - Dog Builders

    /// Dachshund: long body, short legs, floppy ears
    /// Grid: approx 22x10 centered (wider than tall)
    private static func buildDachshund() -> SKNode {
        let n = SKNode()
        let ox = -11 // center a ~22 wide sprite
        let oy = -5  // center a ~10 tall sprite

        // Ears (floppy, hanging down from head)
        vRun(x: ox+17, y: oy+5, count: 3, color: dachshundDark, in: n)
        vRun(x: ox+20, y: oy+5, count: 3, color: dachshundDark, in: n)

        // Head (rounded)
        rect(x: ox+17, y: oy+7, w: 4, h: 3, color: dachshundBrown, in: n)
        pixel(x: ox+18, y: oy+10, color: dachshundBrown, in: n)
        pixel(x: ox+19, y: oy+10, color: dachshundBrown, in: n)
        // Snout
        pixel(x: ox+21, y: oy+8, color: dachshundBrown, in: n)
        pixel(x: ox+21, y: oy+7, color: dachshundBrown, in: n)
        pixel(x: ox+22, y: oy+8, color: dogNose, in: n) // nose
        // Eye
        pixel(x: ox+19, y: oy+9, color: dogEye, in: n)

        // Long body
        rect(x: ox+4, y: oy+5, w: 13, h: 4, color: dachshundBrown, in: n)
        // Belly (lighter underside)
        hRun(x: ox+5, y: oy+5, count: 11, color: dachshundBelly, in: n)

        // Tail (curving up)
        pixel(x: ox+3, y: oy+7, color: dachshundBrown, in: n)
        pixel(x: ox+2, y: oy+8, color: dachshundBrown, in: n)
        pixel(x: ox+2, y: oy+9, color: dachshundDark, in: n)

        // Short legs (4 stubby legs)
        // Front legs
        vRun(x: ox+14, y: oy+3, count: 2, color: dachshundBrown, in: n)
        vRun(x: ox+16, y: oy+3, count: 2, color: dachshundBrown, in: n)
        // Back legs
        vRun(x: ox+5, y: oy+3, count: 2, color: dachshundBrown, in: n)
        vRun(x: ox+7, y: oy+3, count: 2, color: dachshundBrown, in: n)

        // Paws
        pixel(x: ox+14, y: oy+3, color: dachshundDark, in: n)
        pixel(x: ox+16, y: oy+3, color: dachshundDark, in: n)
        pixel(x: ox+5, y: oy+3, color: dachshundDark, in: n)
        pixel(x: ox+7, y: oy+3, color: dachshundDark, in: n)

        return n
    }

    /// Cattle Dog: blue/red heeler pattern, pointed ears, muscular
    /// Grid: approx 18x12 centered
    private static func buildCattleDog() -> SKNode {
        let n = SKNode()
        let ox = -9
        let oy = -6

        // Pointed ears
        pixel(x: ox+13, y: oy+12, color: cattleBlue, in: n)
        pixel(x: ox+16, y: oy+12, color: cattleBlue, in: n)
        pixel(x: ox+13, y: oy+11, color: cattleBlue, in: n)
        pixel(x: ox+14, y: oy+11, color: cattleBlue, in: n)
        pixel(x: ox+15, y: oy+11, color: cattleBlue, in: n)
        pixel(x: ox+16, y: oy+11, color: cattleBlue, in: n)

        // Head
        rect(x: ox+13, y: oy+8, w: 5, h: 3, color: cattleBlue, in: n)
        // Face mask (tan)
        pixel(x: ox+15, y: oy+9, color: cattleTan, in: n)
        pixel(x: ox+15, y: oy+8, color: cattleTan, in: n)
        pixel(x: ox+16, y: oy+8, color: cattleTan, in: n)
        // Eyes
        pixel(x: ox+14, y: oy+9, color: dogEye, in: n)
        pixel(x: ox+16, y: oy+9, color: dogEye, in: n)
        // Nose
        pixel(x: ox+17, y: oy+8, color: dogNose, in: n)

        // Body (muscular, stocky)
        rect(x: ox+4, y: oy+5, w: 10, h: 4, color: cattleBlue, in: n)
        // Speckle pattern (heeler spots)
        pixel(x: ox+5, y: oy+7, color: cattleDarkBlue, in: n)
        pixel(x: ox+7, y: oy+8, color: cattleDarkBlue, in: n)
        pixel(x: ox+9, y: oy+6, color: cattleDarkBlue, in: n)
        pixel(x: ox+11, y: oy+7, color: cattleDarkBlue, in: n)
        pixel(x: ox+6, y: oy+5, color: cattleRed, in: n)
        pixel(x: ox+8, y: oy+7, color: cattleRed, in: n)
        pixel(x: ox+10, y: oy+5, color: cattleRed, in: n)
        pixel(x: ox+12, y: oy+6, color: cattleRed, in: n)
        // Belly
        hRun(x: ox+5, y: oy+5, count: 8, color: cattleTan, in: n)

        // Tail (medium, slightly up)
        pixel(x: ox+3, y: oy+7, color: cattleBlue, in: n)
        pixel(x: ox+2, y: oy+8, color: cattleBlue, in: n)
        pixel(x: ox+1, y: oy+8, color: cattleDarkBlue, in: n)

        // Legs (sturdier than dachshund)
        vRun(x: ox+5, y: oy+3, count: 2, color: cattleTan, in: n)
        vRun(x: ox+7, y: oy+3, count: 2, color: cattleTan, in: n)
        vRun(x: ox+11, y: oy+3, count: 2, color: cattleTan, in: n)
        vRun(x: ox+13, y: oy+3, count: 2, color: cattleTan, in: n)

        // Paws
        pixel(x: ox+5, y: oy+3, color: cattleDarkBlue, in: n)
        pixel(x: ox+7, y: oy+3, color: cattleDarkBlue, in: n)
        pixel(x: ox+11, y: oy+3, color: cattleDarkBlue, in: n)
        pixel(x: ox+13, y: oy+3, color: cattleDarkBlue, in: n)

        return n
    }

    /// Schnauzer: distinctive beard/eyebrows, blocky shape
    /// `isBlack` = true for Black Schnauzer, false for Pepper (salt & pepper)
    private static func buildSchnauzer(isBlack: Bool) -> SKNode {
        let n = SKNode()
        let ox = -9
        let oy = -6

        let bodyMain = isBlack ? schnauzerDark : pepperMid
        let bodyAccent = isBlack ? schnauzerBeard : pepperLight
        let bodyDark = isBlack ? SKColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1) : pepperDark
        let beardColor = isBlack ? schnauzerBeard : pepperLight
        let browColor = isBlack ? schnauzerBeard : pepperLight

        // Ears (folded, blocky)
        pixel(x: ox+13, y: oy+12, color: bodyMain, in: n)
        pixel(x: ox+14, y: oy+12, color: bodyMain, in: n)
        pixel(x: ox+16, y: oy+12, color: bodyMain, in: n)
        pixel(x: ox+17, y: oy+12, color: bodyMain, in: n)

        // Head (blocky)
        rect(x: ox+13, y: oy+8, w: 5, h: 4, color: bodyMain, in: n)
        // Distinctive eyebrows
        hRun(x: ox+13, y: oy+11, count: 2, color: browColor, in: n)
        hRun(x: ox+16, y: oy+11, count: 2, color: browColor, in: n)
        // Eyes (under brows)
        pixel(x: ox+14, y: oy+10, color: dogEye, in: n)
        pixel(x: ox+16, y: oy+10, color: dogEye, in: n)
        // Snout/nose
        pixel(x: ox+18, y: oy+9, color: dogNose, in: n)
        pixel(x: ox+18, y: oy+8, color: dogNose, in: n)
        // Distinctive beard (hangs below jaw)
        rect(x: ox+15, y: oy+6, w: 3, h: 2, color: beardColor, in: n)
        pixel(x: ox+16, y: oy+5, color: beardColor, in: n)

        // Body (blocky, square)
        rect(x: ox+4, y: oy+5, w: 10, h: 4, color: bodyMain, in: n)
        // Lighter underbelly for pepper
        if !isBlack {
            hRun(x: ox+5, y: oy+5, count: 8, color: pepperLight, in: n)
            // Salt & pepper speckle
            pixel(x: ox+6, y: oy+7, color: pepperDark, in: n)
            pixel(x: ox+8, y: oy+8, color: pepperLight, in: n)
            pixel(x: ox+10, y: oy+6, color: pepperDark, in: n)
            pixel(x: ox+12, y: oy+7, color: pepperLight, in: n)
        } else {
            // Subtle shading for black
            pixel(x: ox+6, y: oy+7, color: bodyDark, in: n)
            pixel(x: ox+9, y: oy+6, color: bodyDark, in: n)
        }

        // Tail (stubby, upright — cropped schnauzer tail)
        pixel(x: ox+3, y: oy+8, color: bodyMain, in: n)
        pixel(x: ox+3, y: oy+9, color: bodyMain, in: n)

        // Legs (straight, blocky — schnauzer style)
        vRun(x: ox+5, y: oy+2, count: 3, color: bodyAccent, in: n)
        vRun(x: ox+7, y: oy+2, count: 3, color: bodyAccent, in: n)
        vRun(x: ox+11, y: oy+2, count: 3, color: bodyAccent, in: n)
        vRun(x: ox+13, y: oy+2, count: 3, color: bodyAccent, in: n)

        // Paws
        pixel(x: ox+5, y: oy+2, color: bodyDark, in: n)
        pixel(x: ox+7, y: oy+2, color: bodyDark, in: n)
        pixel(x: ox+11, y: oy+2, color: bodyDark, in: n)
        pixel(x: ox+13, y: oy+2, color: bodyDark, in: n)

        return n
    }
}
