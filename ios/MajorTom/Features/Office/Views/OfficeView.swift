import SwiftUI
import SpriteKit

// MARK: - Office View

/// SwiftUI wrapper for the SpriteKit office scene.
/// Manages the bridge between OfficeViewModel state changes and the SKScene.
struct OfficeView: View {
    @Bindable var viewModel: OfficeViewModel
    @State private var scene: OfficeScene = {
        let scene = OfficeScene()
        scene.size = CGSize(width: OfficeLayout.sceneWidth, height: OfficeLayout.sceneHeight)
        scene.scaleMode = .aspectFit
        return scene
    }()

    /// Previous agent states for diffing.
    @State private var previousAgentIds: Set<String> = []
    @State private var previousStatuses: [String: AgentStatus] = [:]

    var body: some View {
        ZStack {
            // SpriteKit scene
            SpriteView(scene: scene)
                .ignoresSafeArea()
                .onChange(of: viewModel.agents) { _, newAgents in
                    syncScene(with: newAgents)
                }

            // Top overlay: agent count + mini-map placeholder
            VStack {
                topBar
                Spacer()
            }
        }
        .onAppear {
            scene.onAgentTapped = { agentId in
                if let agent = viewModel.agents.first(where: { $0.id == agentId }) {
                    HapticService.selection()
                    viewModel.selectAgent(agent)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.selectedAgentId != nil },
            set: { if !$0 { viewModel.dismissInspector() } }
        )) {
            if let agent = viewModel.selectedAgent {
                AgentInspectorView(
                    agent: agent,
                    onRename: { newName in
                        viewModel.renameAgent(id: agent.id, newName: newName)
                        scene.updateAgentName(id: agent.id, name: newName)
                    },
                    onDismiss: {
                        HapticService.impact(.medium)
                        viewModel.dismissInspector()
                    }
                )
            }
        }
        .hapticOnSheet(isPresented: viewModel.selectedAgentId != nil)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Agent count
            Label("\(viewModel.agents.count) agents", systemImage: "person.2.fill")
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .padding(.horizontal, MajorTomTheme.Spacing.md)
                .padding(.vertical, MajorTomTheme.Spacing.sm)
                .glassBackground()

            Spacer()

            // Mini-map placeholder
            miniMapPlaceholder
        }
        .padding(MajorTomTheme.Spacing.md)
    }

    /// Placeholder for the mini-map concept.
    private var miniMapPlaceholder: some View {
        VStack(spacing: 2) {
            Text("MAP")
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)

            // Tiny colored rectangles representing office areas
            HStack(spacing: 1) {
                Rectangle().fill(Color(red: 0.15, green: 0.20, blue: 0.25))
                Rectangle().fill(Color(red: 0.18, green: 0.18, blue: 0.22))
            }
            .frame(width: 50, height: 15)

            HStack(spacing: 1) {
                Rectangle().fill(Color(red: 0.22, green: 0.18, blue: 0.20))
                Rectangle().fill(Color(red: 0.20, green: 0.20, blue: 0.18))
                Rectangle().fill(Color(red: 0.20, green: 0.18, blue: 0.15))
            }
            .frame(width: 50, height: 12)
        }
        .padding(MajorTomTheme.Spacing.xs)
        .glassBackground()
    }

    // MARK: - Scene Sync

    /// Diff the current agent list against previous state and update the scene.
    private func syncScene(with agents: [AgentState]) {
        let currentIds = Set(agents.map(\.id))

        // Add new agents
        for agent in agents where !previousAgentIds.contains(agent.id) {
            scene.addAgent(id: agent.id, name: agent.name, characterType: agent.characterType)

            // Move to desk if assigned
            if let deskIndex = agent.deskIndex {
                scene.highlightDesk(deskIndex, occupied: true)
                scene.moveAgentToDesk(id: agent.id, deskIndex: deskIndex)
            }
        }

        // Remove departed agents
        for id in previousAgentIds where !currentIds.contains(id) {
            scene.removeAgent(id: id)
        }

        // Update status changes
        for agent in agents {
            let previousStatus = previousStatuses[agent.id]
            if previousStatus != agent.status {
                handleStatusChange(agent: agent, from: previousStatus)
            }
        }

        // Update tracking
        previousAgentIds = currentIds
        previousStatuses = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0.status) })
    }

    /// Handle an agent's status transition in the scene.
    private func handleStatusChange(agent: AgentState, from previousStatus: AgentStatus?) {
        switch agent.status {
        case .spawning:
            // Already handled in addAgent
            break

        case .walking:
            scene.updateAgentStatus(id: agent.id, status: .walking)

        case .working:
            if let deskIndex = agent.deskIndex {
                scene.moveAgentToDesk(id: agent.id, deskIndex: deskIndex)
            } else {
                scene.updateAgentStatus(id: agent.id, status: .working)
            }

        case .idle:
            // Pick a random break area based on character config
            let config = CharacterCatalog.config(for: agent.characterType)
            if let destination = config.breakBehaviors.randomElement() {
                let areaType = breakDestinationToArea(destination)
                scene.moveAgentToBreakArea(id: agent.id, areaType: areaType)
            } else {
                scene.updateAgentStatus(id: agent.id, status: .idle)
            }

        case .celebrating:
            scene.celebrateAgent(id: agent.id)

        case .leaving:
            if let deskIndex = agent.deskIndex {
                scene.highlightDesk(deskIndex, occupied: false)
            }
            scene.moveAgentToDoor(id: agent.id)
        }
    }

    /// Map BreakDestination enum to OfficeAreaType.
    private func breakDestinationToArea(_ destination: BreakDestination) -> OfficeAreaType {
        switch destination {
        case .breakRoom: return .breakRoom
        case .kitchen: return .kitchen
        case .dogCorner: return .dogCorner
        case .dogPark: return .dogPark
        case .gym: return .gym
        case .rollercoaster: return .rollercoaster
        }
    }
}

