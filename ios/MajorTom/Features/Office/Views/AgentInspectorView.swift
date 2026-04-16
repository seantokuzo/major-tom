import SwiftUI
import SpriteKit

// MARK: - Agent Inspector View

/// Overlay panel showing details about a selected agent.
/// Presented as a sheet when an agent sprite is tapped.
/// Includes text input for sending messages to the agent via relay.
struct AgentInspectorView: View {
    let agent: AgentState
    let activityDescription: String?
    let onRename: (String) -> Void
    let onSendMessage: ((String) -> Void)?
    let onDismiss: () -> Void

    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var messageText = ""
    @State private var spriteScene: InspectorSpriteScene?

    var body: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.md) {
            // Sprite preview + header
            spriteHeader

            Divider()
                .background(MajorTomTheme.Colors.textTertiary)

            // Role & Task (prominent)
            roleAndTask

            // Activity (if at a station)
            if let activity = activityDescription {
                activitySection(activity)
            }

            // Details
            detailRows

            Spacer()

            // Message input (only when connected to relay)
            if onSendMessage != nil {
                messageInput
            }

            // Actions
            actions
        }
        .padding(MajorTomTheme.Spacing.lg)
        .background(MajorTomTheme.Colors.surface)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Components

    private var spriteHeader: some View {
        HStack(spacing: MajorTomTheme.Spacing.md) {
            // Cycling sprite preview
            SpriteView(scene: {
                if let existing = spriteScene { return existing }
                let scene = InspectorSpriteScene(characterType: agent.characterType)
                Task { @MainActor in spriteScene = scene }
                return scene
            }())
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium)
                    .stroke(CharacterCatalog.config(for: agent.characterType).spriteColor.opacity(0.5), lineWidth: 1.5)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(agent.name)
                    .font(MajorTomTheme.Typography.headline)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)

                Text(CharacterCatalog.config(for: agent.characterType).displayName)
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)

                statusBadge
            }

            Spacer()
        }
    }

    private var statusBadge: some View {
        Text(agent.status.rawValue.uppercased())
            .font(.system(.caption2, design: .monospaced, weight: .bold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch agent.status {
        case .spawning: return .gray
        case .walking: return .blue
        case .working: return MajorTomTheme.Colors.allow
        case .idle: return MajorTomTheme.Colors.accent
        case .celebrating: return .yellow
        case .leaving: return MajorTomTheme.Colors.deny
        }
    }

    // MARK: - Role & Task (Prominent)

    private var roleAndTask: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            // Role
            HStack(spacing: MajorTomTheme.Spacing.sm) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                Text(agent.role.capitalized)
                    .font(MajorTomTheme.Typography.headline)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
            }

            // Current task or status
            if let task = agent.currentTask {
                HStack(alignment: .top, spacing: MajorTomTheme.Spacing.sm) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(MajorTomTheme.Colors.allow)
                    Text(task)
                        .font(MajorTomTheme.Typography.body)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(MajorTomTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MajorTomTheme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
    }

    // MARK: - Activity Section

    private func activitySection(_ activity: String) -> some View {
        HStack(spacing: MajorTomTheme.Spacing.sm) {
            Image(systemName: "figure.walk")
                .font(.system(size: 12))
                .foregroundStyle(MajorTomTheme.Colors.accent)
            Text(activity)
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.accent)
        }
        .padding(.horizontal, MajorTomTheme.Spacing.sm)
        .padding(.vertical, MajorTomTheme.Spacing.xs)
        .background(MajorTomTheme.Colors.accentSubtle)
        .clipShape(Capsule())
    }

    private var detailRows: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            detailRow(label: "Agent ID", value: String(agent.id.prefix(12)) + "...")
            detailRow(label: "Desk", value: agent.deskIndex.map { "Desk \($0 + 1)" } ?? "None")
            detailRow(label: "Uptime", value: agent.uptime)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
        }
    }

    // MARK: - Message Input

    private var messageInput: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
            Text("Send Message")
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)

            HStack(spacing: MajorTomTheme.Spacing.sm) {
                TextField("Message to agent...", text: $messageText)
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                    .padding(MajorTomTheme.Spacing.sm)
                    .background(MajorTomTheme.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))

                Button {
                    guard !messageText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    onSendMessage?(messageText)
                    messageText = ""
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(messageText.isEmpty ? MajorTomTheme.Colors.textTertiary : MajorTomTheme.Colors.accent)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: MajorTomTheme.Spacing.md) {
            // Rename button
            Button {
                renameText = agent.name
                isRenaming = true
            } label: {
                Label("Rename", systemImage: "pencil")
                    .font(MajorTomTheme.Typography.caption)
            }
            .buttonStyle(.bordered)
            .tint(MajorTomTheme.Colors.accent)
            .alert("Rename Agent", isPresented: $isRenaming) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    if !renameText.isEmpty {
                        onRename(renameText)
                    }
                }
            } message: {
                Text("Enter a new display name for this agent.")
            }

            Spacer()

            // Dismiss button
            Button {
                onDismiss()
            } label: {
                Label("Close", systemImage: "xmark.circle")
                    .font(MajorTomTheme.Typography.caption)
            }
            .buttonStyle(.bordered)
            .tint(MajorTomTheme.Colors.textTertiary)
        }
    }
}

// MARK: - Inspector Sprite Scene

/// SpriteKit scene that cycles through all available textures for a character.
/// Shows standing directions, walk frames, and activity poses — 2 seconds each.
final class InspectorSpriteScene: SKScene {
    private let characterType: CharacterType

    init(characterType: CharacterType) {
        self.characterType = characterType
        super.init(size: CGSize(width: 80, height: 80))
        scaleMode = .aspectFit
        backgroundColor = SKColor(red: 0.10, green: 0.10, blue: 0.13, alpha: 1.0)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        super.didMove(to: view)

        let atlas = SKTextureAtlas(named: "CrewSprites")
        let name = characterType.rawValue

        // Collect all available textures for this character
        var textures: [SKTexture] = []

        // Standing directions
        for dir in ["front", "back", "left", "right"] {
            let key = "\(name)_\(dir)"
            if atlas.textureNames.contains(key) {
                textures.append(atlas.textureNamed(key))
            }
        }

        // Walk frames
        for frame in ["walkLeft1", "walkLeft2", "walkRight1", "walkRight2"] {
            let key = "\(name)_\(frame)"
            if atlas.textureNames.contains(key) {
                textures.append(atlas.textureNamed(key))
            }
        }

        // Activity poses (humans)
        for pose in ["sitting", "sleeping", "working", "exercising"] {
            let key = "\(name)_\(pose)"
            if atlas.textureNames.contains(key) {
                textures.append(atlas.textureNamed(key))
            }
        }

        // Activity poses (dogs)
        for pose in ["running", "sniffing"] {
            let key = "\(name)_\(pose)"
            if atlas.textureNames.contains(key) {
                textures.append(atlas.textureNamed(key))
            }
        }

        guard let first = textures.first else { return }

        for tex in textures { tex.filteringMode = .nearest }

        let sprite = SKSpriteNode(texture: first, size: CrewSpriteBuilder.size(for: characterType))
        sprite.setScale(1.12)
        sprite.position = .zero
        addChild(sprite)

        // Gentle bob
        sprite.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 3, duration: 0.7),
            .moveBy(x: 0, y: -3, duration: 0.7),
        ])))

        // Cycle through all textures
        guard textures.count > 1 else { return }
        var actions: [SKAction] = []
        for tex in textures.dropFirst() {
            actions.append(.wait(forDuration: 2.0))
            actions.append(.run { sprite.texture = tex })
        }
        // Loop back to first
        actions.append(.wait(forDuration: 2.0))
        actions.append(.run { sprite.texture = first })
        sprite.run(.repeatForever(.sequence(actions)))
    }
}

#Preview {
    AgentInspectorView(
        agent: AgentState(
            id: "preview-1",
            name: "Alice",
            role: "frontend",
            characterType: .captain,
            status: .working,
            currentTask: "Building the login page",
            deskIndex: 0
        ),
        activityDescription: nil,
        onRename: { _ in },
        onSendMessage: { _ in },
        onDismiss: {}
    )
}
