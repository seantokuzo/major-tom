import SwiftUI
import SpriteKit

// MARK: - Character Gallery View

/// A swipeable horizontal carousel showing all 9 character types.
/// Each card shows a large sprite preview, character name, and description.
/// Idle animation plays on each preview card.
struct CharacterGalleryView: View {
    let onDismiss: () -> Void

    @State private var selectedIndex: Int = 0

    private let characters = CharacterCatalog.all

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            // Character carousel
            TabView(selection: $selectedIndex) {
                ForEach(Array(characters.enumerated()), id: \.offset) { index, config in
                    characterCard(config: config)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(maxHeight: .infinity)

            // Page indicator label
            pageIndicator
        }
        .background(MajorTomTheme.Colors.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Character Gallery")
                .font(MajorTomTheme.Typography.title)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, MajorTomTheme.Spacing.lg)
        .padding(.top, MajorTomTheme.Spacing.lg)
        .padding(.bottom, MajorTomTheme.Spacing.md)
    }

    // MARK: - Character Card

    private func characterCard(config: CharacterConfig) -> some View {
        VStack(spacing: MajorTomTheme.Spacing.lg) {
            // Sprite preview
            spritePreview(config: config)

            // Character info
            VStack(spacing: MajorTomTheme.Spacing.sm) {
                Text(config.displayName)
                    .font(MajorTomTheme.Typography.headline)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)

                Text(characterDescription(for: config.type))
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, MajorTomTheme.Spacing.xl)
            }

            // Traits
            traitsView(config: config)

            Spacer()
        }
        .padding(MajorTomTheme.Spacing.lg)
    }

    private func spritePreview(config: CharacterConfig) -> some View {
        CachedSpritePreview(config: config)
    }

    private func traitsView(config: CharacterConfig) -> some View {
        HStack(spacing: MajorTomTheme.Spacing.sm) {
            // Type badge
            let isDog = [CharacterType.dachshund, .cattleDog, .schnauzerBlack, .schnauzerPepper].contains(config.type)
            traitBadge(
                icon: isDog ? "pawprint.fill" : "person.fill",
                text: isDog ? "Dog" : "Human",
                color: config.spriteColor
            )

            // Break behavior count
            traitBadge(
                icon: "cup.and.saucer.fill",
                text: "\(config.breakBehaviors.count) hangouts",
                color: MajorTomTheme.Colors.accent
            )

            // Special trait
            if config.needsBlanket {
                traitBadge(
                    icon: "bed.double.fill",
                    text: "Needs blanket",
                    color: MajorTomTheme.Colors.warning
                )
            }
        }
    }

    private func traitBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(.caption2, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, MajorTomTheme.Spacing.sm)
        .padding(.vertical, MajorTomTheme.Spacing.xs)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        Text("\(selectedIndex + 1) / \(characters.count)")
            .font(MajorTomTheme.Typography.codeFontSmall)
            .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            .padding(.bottom, MajorTomTheme.Spacing.lg)
    }

    // MARK: - Character Descriptions

    private func characterDescription(for type: CharacterType) -> String {
        switch type {
        case .dev:
            return "The classic coder. Lives on caffeine, thrives under pressure, and always has headphones on."
        case .officeWorker:
            return "Keeps the wheels turning. Organized, reliable, and always has a spreadsheet ready."
        case .pm:
            return "Herds cats for a living. Loves standup meetings and Gantt charts."
        case .clown:
            return "Office morale officer. Brings joy, chaos, and occasional whoopee cushions."
        case .frankenstein:
            return "The office wildcard. Bolts included. Surprisingly good at pair programming."
        case .dachshund:
            return "Long boi. Requires a blanket at all times. Expert at fitting under desks."
        case .cattleDog:
            return "High energy herder. Will round up the team for meetings whether you like it or not."
        case .schnauzerBlack:
            return "Distinguished and dignified. The office elder. Judges silently from their corner."
        case .schnauzerPepper:
            return "Salt and pepper wisdom. Best beard in the office, no contest."
        }
    }
}

// MARK: - Cached Sprite Preview

/// Wraps the SpriteKit scene in a @State so it's created once and reused across re-renders.
private struct CachedSpritePreview: View {
    let config: CharacterConfig
    @State private var scene: CharacterPreviewScene

    init(config: CharacterConfig) {
        self.config = config
        _scene = State(initialValue: CharacterPreviewScene(characterType: config.type))
    }

    var body: some View {
        SpriteView(scene: scene)
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.large))
            .overlay(
                RoundedRectangle(cornerRadius: MajorTomTheme.Radius.large)
                    .stroke(config.spriteColor.opacity(0.5), lineWidth: 2)
            )
            .shadow(color: config.spriteColor.opacity(0.3), radius: 8, y: 4)
    }
}

// MARK: - Character Preview Scene

/// A small SpriteKit scene that shows a single character with idle animation.
final class CharacterPreviewScene: SKScene {
    private let characterType: CharacterType

    init(characterType: CharacterType) {
        self.characterType = characterType
        super.init(size: CGSize(width: 120, height: 120))
        scaleMode = .aspectFit
        backgroundColor = SKColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1.0)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)

        // Build and add a scaled-up version of the pixel art
        let pixelArt = PixelArtBuilder.build(for: characterType)
        pixelArt.setScale(3.0) // 3x scale for preview
        pixelArt.position = CGPoint(x: 0, y: 0)
        addChild(pixelArt)

        // Add idle bobbing animation
        let bob = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 4, duration: 0.8),
            SKAction.moveBy(x: 0, y: -4, duration: 0.8),
        ])
        pixelArt.run(SKAction.repeatForever(bob))
    }
}

// MARK: - Preview

#Preview {
    CharacterGalleryView(onDismiss: {})
}
