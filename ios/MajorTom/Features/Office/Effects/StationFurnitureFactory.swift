import SpriteKit

// MARK: - Station Furniture Factory

/// Draws detailed, multi-layer furniture for each station module.
/// Every piece uses 3-5 color layers for visual depth — base, shadow, highlight, detail, accent.
enum StationFurnitureFactory {

    // MARK: - Command Bridge

    /// Workstation console with monitor showing code/data lines.
    static func workstationConsole() -> SKNode {
        let node = SKNode()

        // Desk surface (dark metal)
        let desk = SKShapeNode(rectOf: CGSize(width: 44, height: 20), cornerRadius: 2)
        desk.fillColor = SKColor(red: 0.12, green: 0.14, blue: 0.20, alpha: 1)
        desk.strokeColor = SKColor(red: 0.20, green: 0.22, blue: 0.30, alpha: 0.6)
        desk.lineWidth = 0.5
        node.addChild(desk)

        // Desk highlight edge (top)
        let highlight = SKSpriteNode(
            color: SKColor(red: 0.18, green: 0.20, blue: 0.28, alpha: 1),
            size: CGSize(width: 42, height: 2)
        )
        highlight.position = CGPoint(x: 0, y: 9)
        node.addChild(highlight)

        // Monitor frame
        let monitor = SKShapeNode(rectOf: CGSize(width: 28, height: 18), cornerRadius: 1)
        monitor.fillColor = SKColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 1)
        monitor.strokeColor = SKColor(red: 0.15, green: 0.18, blue: 0.25, alpha: 0.8)
        monitor.lineWidth = 1
        monitor.position = CGPoint(x: 0, y: 18)
        node.addChild(monitor)

        // Monitor screen (inner glow)
        let screen = SKSpriteNode(
            color: SKColor(red: 0.04, green: 0.08, blue: 0.14, alpha: 1),
            size: CGSize(width: 24, height: 14)
        )
        screen.position = CGPoint(x: 0, y: 18)
        node.addChild(screen)

        // Code lines on screen (colored data)
        let lineColors: [SKColor] = [
            StationPalette.consoleCyan.withAlphaComponent(0.6),
            StationPalette.consoleSuccess.withAlphaComponent(0.5),
            StationPalette.consoleWarning.withAlphaComponent(0.4),
            StationPalette.consoleCyan.withAlphaComponent(0.5),
        ]
        for (i, color) in lineColors.enumerated() {
            let lineWidth = CGFloat.random(in: 8...18)
            let line = SKSpriteNode(color: color, size: CGSize(width: lineWidth, height: 1.5))
            line.position = CGPoint(x: -6 + lineWidth / 2, y: 23 - CGFloat(i) * 3.5)
            line.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            node.addChild(line)
        }

        // Monitor stand
        let stand = SKSpriteNode(
            color: SKColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1),
            size: CGSize(width: 6, height: 4)
        )
        stand.position = CGPoint(x: 0, y: 10)
        node.addChild(stand)

        // Keyboard
        let keyboard = SKShapeNode(rectOf: CGSize(width: 20, height: 6), cornerRadius: 1)
        keyboard.fillColor = SKColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1)
        keyboard.strokeColor = SKColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 0.5)
        keyboard.lineWidth = 0.5
        keyboard.position = CGPoint(x: 0, y: -2)
        node.addChild(keyboard)

        // Key dots on keyboard
        for row in 0..<2 {
            for col in 0..<5 {
                let key = SKShapeNode(rectOf: CGSize(width: 2.5, height: 1.5))
                key.fillColor = SKColor(red: 0.14, green: 0.16, blue: 0.20, alpha: 0.7)
                key.strokeColor = .clear
                key.position = CGPoint(x: CGFloat(col - 2) * 3.5, y: CGFloat(row) * 2.5 - 2.5)
                keyboard.addChild(key)
            }
        }

        // Status LED on desk
        let led = SKShapeNode(circleOfRadius: 1.5)
        led.fillColor = StationPalette.consoleCyan.withAlphaComponent(0.5)
        led.strokeColor = .clear
        led.position = CGPoint(x: 18, y: 0)
        node.addChild(led)

        // LED pulse
        led.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.3, duration: 1.5),
            SKAction.fadeAlpha(to: 0.7, duration: 1.5),
        ])))

        return node
    }

    /// Large tactical display screen on wall.
    static func tacticalDisplay() -> SKNode {
        let node = SKNode()

        // Large screen frame
        let frame = SKShapeNode(rectOf: CGSize(width: 70, height: 40), cornerRadius: 2)
        frame.fillColor = SKColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1)
        frame.strokeColor = StationPalette.wallTrim.withAlphaComponent(0.6)
        frame.lineWidth = 1.5
        node.addChild(frame)

        // Screen surface
        let screen = SKSpriteNode(
            color: SKColor(red: 0.03, green: 0.05, blue: 0.10, alpha: 1),
            size: CGSize(width: 64, height: 34)
        )
        node.addChild(screen)

        // Grid overlay (tactical)
        for i in 0..<4 {
            let vLine = SKSpriteNode(
                color: StationPalette.consoleCyan.withAlphaComponent(0.08),
                size: CGSize(width: 0.5, height: 32)
            )
            vLine.position = CGPoint(x: CGFloat(i - 1) * 16 - 8, y: 0)
            node.addChild(vLine)
        }
        for i in 0..<3 {
            let hLine = SKSpriteNode(
                color: StationPalette.consoleCyan.withAlphaComponent(0.08),
                size: CGSize(width: 62, height: 0.5)
            )
            hLine.position = CGPoint(x: 0, y: CGFloat(i - 1) * 11)
            node.addChild(hLine)
        }

        // Data blips on tactical
        for _ in 0..<5 {
            let blip = SKShapeNode(circleOfRadius: 1.5)
            blip.fillColor = StationPalette.consoleCyan.withAlphaComponent(0.4)
            blip.strokeColor = .clear
            blip.position = CGPoint(
                x: CGFloat.random(in: -28...28),
                y: CGFloat.random(in: -14...14)
            )
            node.addChild(blip)

            blip.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.2, duration: Double.random(in: 0.8...2.0)),
                SKAction.fadeAlpha(to: 0.6, duration: Double.random(in: 0.8...2.0)),
            ])))
        }

        // Screen border glow
        let glow = SKShapeNode(rectOf: CGSize(width: 68, height: 38), cornerRadius: 2)
        glow.fillColor = .clear
        glow.strokeColor = StationPalette.consoleCyan.withAlphaComponent(0.1)
        glow.lineWidth = 2
        glow.glowWidth = 3
        node.addChild(glow)

        return node
    }

    // MARK: - Engineering

    /// Reactor core with pulsing concentric rings.
    static func reactorCore() -> SKNode {
        let node = SKNode()

        // Outer ring
        let outerRing = SKShapeNode(circleOfRadius: 35)
        outerRing.fillColor = SKColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 1)
        outerRing.strokeColor = StationPalette.consoleCyan.withAlphaComponent(0.3)
        outerRing.lineWidth = 2
        node.addChild(outerRing)

        // Middle ring
        let midRing = SKShapeNode(circleOfRadius: 24)
        midRing.fillColor = SKColor(red: 0.04, green: 0.06, blue: 0.12, alpha: 1)
        midRing.strokeColor = StationPalette.consoleCyan.withAlphaComponent(0.4)
        midRing.lineWidth = 1.5
        node.addChild(midRing)

        // Inner core
        let core = SKShapeNode(circleOfRadius: 14)
        core.fillColor = SKColor(red: 0.0, green: 0.15, blue: 0.25, alpha: 1)
        core.strokeColor = StationPalette.consoleCyan.withAlphaComponent(0.6)
        core.lineWidth = 1
        core.glowWidth = 4
        node.addChild(core)

        // Core bright center
        let center = SKShapeNode(circleOfRadius: 6)
        center.fillColor = StationPalette.consoleCyan.withAlphaComponent(0.3)
        center.strokeColor = .clear
        center.glowWidth = 8
        node.addChild(center)

        // Pulsing animation on core
        let pulse = SKAction.repeatForever(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 1.1, duration: 1.5),
                SKAction.fadeAlpha(to: 0.6, duration: 1.5),
            ]),
            SKAction.group([
                SKAction.scale(to: 0.95, duration: 1.5),
                SKAction.fadeAlpha(to: 1.0, duration: 1.5),
            ]),
        ]))
        center.run(pulse)

        // Energy lines radiating from core (4 lines)
        for angle in stride(from: 0, to: CGFloat.pi * 2, by: CGFloat.pi / 2) {
            let line = SKShapeNode()
            let path = CGMutablePath()
            let innerR: CGFloat = 16
            let outerR: CGFloat = 33
            path.move(to: CGPoint(x: cos(angle) * innerR, y: sin(angle) * innerR))
            path.addLine(to: CGPoint(x: cos(angle) * outerR, y: sin(angle) * outerR))
            line.path = path
            line.strokeColor = StationPalette.consoleCyan.withAlphaComponent(0.2)
            line.lineWidth = 1
            line.glowWidth = 2
            node.addChild(line)
        }

        // Power distribution label
        let label = SKLabelNode(fontNamed: "Menlo")
        label.text = "CORE"
        label.fontSize = 6
        label.fontColor = StationPalette.consoleCyan.withAlphaComponent(0.4)
        label.position = CGPoint(x: 0, y: -44)
        node.addChild(label)

        return node
    }

    /// Power distribution panel on the wall.
    static func powerPanel() -> SKNode {
        let node = SKNode()

        // Panel base
        let panel = SKShapeNode(rectOf: CGSize(width: 28, height: 36), cornerRadius: 1)
        panel.fillColor = SKColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1)
        panel.strokeColor = StationPalette.wallTrim.withAlphaComponent(0.4)
        panel.lineWidth = 1
        node.addChild(panel)

        // Status indicators (colored LEDs)
        let ledColors: [SKColor] = [
            StationPalette.consoleSuccess,
            StationPalette.consoleSuccess,
            StationPalette.statusIdle,
            StationPalette.consoleCyan,
        ]
        for (i, color) in ledColors.enumerated() {
            let led = SKShapeNode(circleOfRadius: 2)
            led.fillColor = color.withAlphaComponent(0.5)
            led.strokeColor = .clear
            led.position = CGPoint(x: -6, y: 12 - CGFloat(i) * 7)
            node.addChild(led)

            // Label next to LED
            let lbl = SKSpriteNode(
                color: SKColor(red: 0.14, green: 0.16, blue: 0.22, alpha: 0.5),
                size: CGSize(width: 10, height: 2)
            )
            lbl.position = CGPoint(x: 4, y: 12 - CGFloat(i) * 7)
            node.addChild(lbl)
        }

        return node
    }

    // MARK: - Crew Quarters

    /// Bunk bed — stacked double bed with pillow and blanket.
    static func bunkBed(color: SKColor = SKColor(red: 0.20, green: 0.25, blue: 0.40, alpha: 1)) -> SKNode {
        let node = SKNode()

        // Bed frame
        let frame = SKShapeNode(rectOf: CGSize(width: 32, height: 16), cornerRadius: 1)
        frame.fillColor = SKColor(red: 0.12, green: 0.13, blue: 0.17, alpha: 1)
        frame.strokeColor = SKColor(red: 0.18, green: 0.20, blue: 0.25, alpha: 0.6)
        frame.lineWidth = 0.5
        node.addChild(frame)

        // Mattress
        let mattress = SKSpriteNode(
            color: SKColor(red: 0.18, green: 0.20, blue: 0.26, alpha: 1),
            size: CGSize(width: 28, height: 12)
        )
        mattress.position = CGPoint(x: 0, y: 0)
        node.addChild(mattress)

        // Blanket (colored)
        let blanket = SKSpriteNode(color: color, size: CGSize(width: 20, height: 10))
        blanket.position = CGPoint(x: 2, y: 0)
        node.addChild(blanket)

        // Pillow
        let pillow = SKShapeNode(rectOf: CGSize(width: 8, height: 6), cornerRadius: 2)
        pillow.fillColor = SKColor(red: 0.28, green: 0.30, blue: 0.36, alpha: 1)
        pillow.strokeColor = .clear
        pillow.position = CGPoint(x: -10, y: 0)
        node.addChild(pillow)

        return node
    }

    /// Media screen (TV/entertainment).
    static func mediaScreen() -> SKNode {
        let node = SKNode()

        // Screen frame
        let frame = SKShapeNode(rectOf: CGSize(width: 36, height: 22), cornerRadius: 1)
        frame.fillColor = SKColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1)
        frame.strokeColor = SKColor(red: 0.15, green: 0.17, blue: 0.22, alpha: 0.6)
        frame.lineWidth = 1
        node.addChild(frame)

        // Screen content (colorful static)
        let screen = SKSpriteNode(
            color: SKColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 1),
            size: CGSize(width: 32, height: 18)
        )
        node.addChild(screen)

        // Content bars (like a show playing)
        for i in 0..<3 {
            let bar = SKSpriteNode(
                color: [
                    SKColor(red: 0.3, green: 0.2, blue: 0.5, alpha: 0.3),
                    SKColor(red: 0.2, green: 0.4, blue: 0.3, alpha: 0.3),
                    SKColor(red: 0.4, green: 0.3, blue: 0.2, alpha: 0.3),
                ][i],
                size: CGSize(width: 30, height: 4)
            )
            bar.position = CGPoint(x: 0, y: 5 - CGFloat(i) * 6)
            node.addChild(bar)
        }

        return node
    }

    // MARK: - Galley

    /// Food dispenser / vending machine style.
    static func foodDispenser() -> SKNode {
        let node = SKNode()

        // Cabinet
        let cabinet = SKShapeNode(rectOf: CGSize(width: 22, height: 34), cornerRadius: 1)
        cabinet.fillColor = SKColor(red: 0.14, green: 0.16, blue: 0.22, alpha: 1)
        cabinet.strokeColor = SKColor(red: 0.20, green: 0.22, blue: 0.28, alpha: 0.6)
        cabinet.lineWidth = 1
        node.addChild(cabinet)

        // Display panel
        let display = SKSpriteNode(
            color: SKColor(red: 0.06, green: 0.10, blue: 0.16, alpha: 1),
            size: CGSize(width: 16, height: 10)
        )
        display.position = CGPoint(x: 0, y: 8)
        node.addChild(display)

        // Menu items (colored dots)
        let menuColors: [SKColor] = [.green, .orange, .cyan]
        for (i, color) in menuColors.enumerated() {
            let dot = SKShapeNode(circleOfRadius: 1.5)
            dot.fillColor = color.withAlphaComponent(0.4)
            dot.strokeColor = .clear
            dot.position = CGPoint(x: CGFloat(i - 1) * 5, y: 8)
            node.addChild(dot)
        }

        // Dispensing slot
        let slot = SKSpriteNode(
            color: SKColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1),
            size: CGSize(width: 14, height: 6)
        )
        slot.position = CGPoint(x: 0, y: -4)
        node.addChild(slot)

        // Status LED
        let led = SKShapeNode(circleOfRadius: 1.5)
        led.fillColor = StationPalette.consoleSuccess.withAlphaComponent(0.5)
        led.strokeColor = .clear
        led.position = CGPoint(x: 0, y: -12)
        node.addChild(led)

        return node
    }

    /// Counter/table surface.
    static func counter() -> SKNode {
        let node = SKNode()

        let surface = SKShapeNode(rectOf: CGSize(width: 60, height: 14), cornerRadius: 1)
        surface.fillColor = SKColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)
        surface.strokeColor = SKColor(red: 0.22, green: 0.24, blue: 0.30, alpha: 0.5)
        surface.lineWidth = 0.5
        node.addChild(surface)

        // Surface highlight
        let highlight = SKSpriteNode(
            color: SKColor(red: 0.20, green: 0.22, blue: 0.28, alpha: 0.5),
            size: CGSize(width: 56, height: 2)
        )
        highlight.position = CGPoint(x: 0, y: 5)
        node.addChild(highlight)

        // Items on counter
        // Cup
        let cup = SKShapeNode(rectOf: CGSize(width: 5, height: 6), cornerRadius: 1)
        cup.fillColor = SKColor(red: 0.30, green: 0.35, blue: 0.45, alpha: 0.7)
        cup.strokeColor = .clear
        cup.position = CGPoint(x: -15, y: 4)
        node.addChild(cup)

        // Tray
        let tray = SKSpriteNode(
            color: SKColor(red: 0.22, green: 0.24, blue: 0.30, alpha: 0.6),
            size: CGSize(width: 14, height: 3)
        )
        tray.position = CGPoint(x: 10, y: 3)
        node.addChild(tray)

        return node
    }

    // MARK: - Bio-Dome

    /// A plant / small tree with layered foliage.
    static func plant(size plantSize: CGFloat = 1.0) -> SKNode {
        let node = SKNode()

        let s = plantSize

        // Pot
        let pot = SKShapeNode(rectOf: CGSize(width: 12 * s, height: 8 * s), cornerRadius: 1)
        pot.fillColor = SKColor(red: 0.45, green: 0.30, blue: 0.20, alpha: 0.8) // Terra cotta
        pot.strokeColor = SKColor(red: 0.35, green: 0.22, blue: 0.15, alpha: 0.6)
        pot.lineWidth = 0.5
        pot.position = CGPoint(x: 0, y: -8 * s)
        node.addChild(pot)

        // Pot rim
        let rim = SKSpriteNode(
            color: SKColor(red: 0.50, green: 0.35, blue: 0.25, alpha: 0.8),
            size: CGSize(width: 14 * s, height: 2 * s)
        )
        rim.position = CGPoint(x: 0, y: -4.5 * s)
        node.addChild(rim)

        // Trunk
        let trunk = SKSpriteNode(
            color: SKColor(red: 0.30, green: 0.22, blue: 0.14, alpha: 0.8),
            size: CGSize(width: 3 * s, height: 10 * s)
        )
        trunk.position = CGPoint(x: 0, y: 0)
        node.addChild(trunk)

        // Foliage layers (overlapping circles in multiple greens)
        let greens: [SKColor] = [
            SKColor(red: 0.15, green: 0.40, blue: 0.20, alpha: 0.8),
            SKColor(red: 0.20, green: 0.50, blue: 0.25, alpha: 0.7),
            SKColor(red: 0.18, green: 0.45, blue: 0.22, alpha: 0.75),
            SKColor(red: 0.25, green: 0.55, blue: 0.30, alpha: 0.65),
        ]
        let positions: [(CGFloat, CGFloat, CGFloat)] = [
            (0, 10 * s, 10 * s),
            (-6 * s, 7 * s, 8 * s),
            (6 * s, 7 * s, 8 * s),
            (0, 14 * s, 7 * s),
        ]
        for (i, (px, py, radius)) in positions.enumerated() {
            let leaf = SKShapeNode(circleOfRadius: radius)
            leaf.fillColor = greens[i]
            leaf.strokeColor = .clear
            leaf.position = CGPoint(x: px, y: py)
            node.addChild(leaf)
        }

        return node
    }

    /// Water feature — small decorative pool.
    static func waterFeature() -> SKNode {
        let node = SKNode()

        // Pool basin
        let pool = SKShapeNode(ellipseOf: CGSize(width: 50, height: 24))
        pool.fillColor = SKColor(red: 0.08, green: 0.18, blue: 0.30, alpha: 0.8)
        pool.strokeColor = SKColor(red: 0.15, green: 0.20, blue: 0.28, alpha: 0.5)
        pool.lineWidth = 1
        node.addChild(pool)

        // Water surface shimmer
        let shimmer = SKShapeNode(ellipseOf: CGSize(width: 30, height: 12))
        shimmer.fillColor = SKColor(red: 0.10, green: 0.25, blue: 0.40, alpha: 0.4)
        shimmer.strokeColor = .clear
        shimmer.position = CGPoint(x: -4, y: 2)
        node.addChild(shimmer)

        // Surface highlight
        let glint = SKSpriteNode(
            color: SKColor(white: 1, alpha: 0.08),
            size: CGSize(width: 12, height: 3)
        )
        glint.position = CGPoint(x: -6, y: 3)
        node.addChild(glint)

        // Animate shimmer
        shimmer.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.2, duration: 2.0),
            SKAction.fadeAlpha(to: 0.5, duration: 2.0),
        ])))

        return node
    }

    // MARK: - Training Bay

    /// Exercise equipment (treadmill-like).
    static func exerciseEquipment() -> SKNode {
        let node = SKNode()

        // Base
        let base = SKShapeNode(rectOf: CGSize(width: 24, height: 10), cornerRadius: 1)
        base.fillColor = SKColor(red: 0.14, green: 0.14, blue: 0.20, alpha: 1)
        base.strokeColor = SKColor(red: 0.20, green: 0.22, blue: 0.28, alpha: 0.5)
        base.lineWidth = 0.5
        node.addChild(base)

        // Upright bar
        let upright = SKSpriteNode(
            color: SKColor(red: 0.18, green: 0.20, blue: 0.26, alpha: 0.8),
            size: CGSize(width: 2, height: 18)
        )
        upright.position = CGPoint(x: -8, y: 12)
        node.addChild(upright)

        // Display on upright
        let display = SKShapeNode(rectOf: CGSize(width: 10, height: 6), cornerRadius: 1)
        display.fillColor = SKColor(red: 0.04, green: 0.08, blue: 0.12, alpha: 1)
        display.strokeColor = StationPalette.consoleCyan.withAlphaComponent(0.2)
        display.lineWidth = 0.5
        display.position = CGPoint(x: -8, y: 22)
        node.addChild(display)

        return node
    }

    // MARK: - EVA Bay

    /// Space suit on a rack.
    static func spaceSuitRack() -> SKNode {
        let node = SKNode()

        // Rack frame
        let rack = SKShapeNode(rectOf: CGSize(width: 20, height: 32), cornerRadius: 1)
        rack.fillColor = SKColor(red: 0.12, green: 0.13, blue: 0.18, alpha: 1)
        rack.strokeColor = SKColor(red: 0.18, green: 0.20, blue: 0.25, alpha: 0.5)
        rack.lineWidth = 0.5
        node.addChild(rack)

        // Suit body (white-ish)
        let suit = SKShapeNode(rectOf: CGSize(width: 14, height: 18), cornerRadius: 2)
        suit.fillColor = SKColor(red: 0.55, green: 0.58, blue: 0.62, alpha: 0.8)
        suit.strokeColor = SKColor(red: 0.40, green: 0.42, blue: 0.46, alpha: 0.5)
        suit.lineWidth = 0.5
        suit.position = CGPoint(x: 0, y: 2)
        node.addChild(suit)

        // Helmet (circle on top)
        let helmet = SKShapeNode(circleOfRadius: 6)
        helmet.fillColor = SKColor(red: 0.50, green: 0.53, blue: 0.58, alpha: 0.8)
        helmet.strokeColor = SKColor(red: 0.60, green: 0.63, blue: 0.68, alpha: 0.5)
        helmet.lineWidth = 0.5
        helmet.position = CGPoint(x: 0, y: 14)
        node.addChild(helmet)

        // Visor
        let visor = SKShapeNode(rectOf: CGSize(width: 7, height: 4), cornerRadius: 1)
        visor.fillColor = StationPalette.consoleCyan.withAlphaComponent(0.2)
        visor.strokeColor = StationPalette.consoleCyan.withAlphaComponent(0.3)
        visor.lineWidth = 0.5
        visor.position = CGPoint(x: 0, y: 14)
        node.addChild(visor)

        return node
    }

    // MARK: - Generic

    /// Chair / seating.
    static func chair() -> SKNode {
        let node = SKNode()

        // Seat cushion (circle)
        let seat = SKShapeNode(circleOfRadius: 6)
        seat.fillColor = SKColor(red: 0.18, green: 0.20, blue: 0.28, alpha: 0.8)
        seat.strokeColor = SKColor(red: 0.24, green: 0.26, blue: 0.32, alpha: 0.5)
        seat.lineWidth = 0.5
        node.addChild(seat)

        // Seat highlight
        let highlight = SKShapeNode(circleOfRadius: 3)
        highlight.fillColor = SKColor(red: 0.22, green: 0.24, blue: 0.32, alpha: 0.4)
        highlight.strokeColor = .clear
        highlight.position = CGPoint(x: -1, y: 1)
        node.addChild(highlight)

        return node
    }
}
