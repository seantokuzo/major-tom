import SwiftUI
import SpriteKit

// MARK: - Office Sheet State

/// Enum to consolidate sheet presentations and avoid .sheet conflicts.
private enum OfficeSheetType: Identifiable {
    case inspector
    case gallery

    var id: String {
        switch self {
        case .inspector: return "inspector"
        case .gallery: return "gallery"
        }
    }
}

// MARK: - Office View

/// SwiftUI wrapper for the SpriteKit office scene.
/// Manages the bridge between OfficeViewModel state changes and the SKScene.
struct OfficeView: View {
    @Bindable var viewModel: OfficeViewModel
    var relay: RelayService?

    @State private var activeSheet: OfficeSheetType?
    @State private var scene: OfficeScene = {
        let scene = OfficeScene()
        scene.size = CGSize(width: StationLayout.sceneWidth, height: StationLayout.sceneHeight)
        scene.scaleMode = .aspectFit
        return scene
    }()

    /// Space weather engine for cosmetic atmospheric events.
    @State private var spaceWeather = SpaceWeatherEngine()

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

            // Top overlay: agent count + controls
            VStack {
                topBar
                Spacer()
            }
        }
        .onAppear {
            // Wire theme + mood engines to the scene
            scene.themeEngine = viewModel.themeEngine
            scene.moodEngine = viewModel.moodEngine

            // Start engines
            viewModel.themeEngine.start()
            viewModel.moodEngine.start()

            scene.onAgentTapped = { agentId in
                if let agent = viewModel.agents.first(where: { $0.id == agentId }) {
                    HapticService.selection()
                    viewModel.selectAgent(agent)
                }
            }

            // Start activity cycling
            viewModel.activityManager.startCycling { [weak scene] agentId, station in
                if let station {
                    scene?.moveAgentToStation(id: agentId, stationType: station.type)
                }
            }

            // Wire space weather engine to the scene
            scene.spaceWeatherEngine = spaceWeather
            spaceWeather.onWeatherEvent = { [weak scene] event in
                scene?.handleWeatherEvent(event)
            }
            spaceWeather.start()

            // Populate idle sprites if no agents present
            if viewModel.agents.isEmpty {
                viewModel.populateIdleSprites()
            }
        }
        .onDisappear {
            // Stop engines + activity cycling when view disappears
            viewModel.themeEngine.stop()
            viewModel.moodEngine.stop()
            viewModel.activityManager.stopCycling()
            spaceWeather.stop()
        }
        .onChange(of: viewModel.selectedAgentId) { _, newValue in
            if newValue != nil {
                activeSheet = .inspector
            } else if activeSheet == .inspector {
                activeSheet = nil
            }
        }
        .onChange(of: viewModel.showCharacterGallery) { _, show in
            if show {
                activeSheet = .gallery
            } else if activeSheet == .gallery {
                activeSheet = nil
            }
        }
        .sheet(item: $activeSheet) { sheetType in
            switch sheetType {
            case .inspector:
                if let agent = viewModel.selectedAgent {
                    AgentInspectorView(
                        agent: agent,
                        activityDescription: viewModel.activityManager.activityDescription(for: agent.id),
                        onRename: { newName in
                            viewModel.renameAgent(id: agent.id, newName: newName)
                            scene.updateAgentName(id: agent.id, name: newName)
                        },
                        onSendMessage: relay != nil ? { message in
                            guard let sessionId = relay?.currentSession?.id, !sessionId.isEmpty else { return }
                            Task {
                                try? await relay?.sendAgentMessage(
                                    sessionId: sessionId,
                                    agentId: agent.id,
                                    text: message
                                )
                            }
                        } : nil,
                        onDismiss: {
                            HapticService.impact(.medium)
                            viewModel.dismissInspector()
                        }
                    )
                }
            case .gallery:
                CharacterGalleryView(onDismiss: {
                    viewModel.showCharacterGallery = false
                })
            }
        }
        .onChange(of: activeSheet) { _, newValue in
            // Sync sheet dismissal back to view model state
            if newValue == nil {
                if viewModel.selectedAgentId != nil {
                    viewModel.dismissInspector()
                }
                if viewModel.showCharacterGallery {
                    viewModel.showCharacterGallery = false
                }
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Agent count
            Label(
                "\(viewModel.agents.count) agent\(viewModel.agents.count == 1 ? "" : "s")",
                systemImage: "person.2.fill"
            )
            .font(MajorTomTheme.Typography.caption)
            .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            .padding(.horizontal, MajorTomTheme.Spacing.md)
            .padding(.vertical, MajorTomTheme.Spacing.sm)
            .glassBackground()

            Spacer()

            // Character gallery button
            Button {
                viewModel.showCharacterGallery = true
            } label: {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(.system(size: 16))
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .padding(MajorTomTheme.Spacing.sm)
                    .glassBackground()
            }

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
            // Try to assign to an activity station first
            if let station = viewModel.activityManager.assignStation(for: agent.id) {
                scene.moveAgentToStation(id: agent.id, stationType: station.type)
            } else {
                // Fall back to break area behavior
                let config = CharacterCatalog.config(for: agent.characterType)
                if let destination = config.breakBehaviors.randomElement() {
                    let areaType = breakDestinationToArea(destination)
                    scene.moveAgentToBreakArea(id: agent.id, areaType: areaType)
                } else {
                    scene.updateAgentStatus(id: agent.id, status: .idle)
                }
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

#Preview {
    OfficeView(viewModel: OfficeViewModel())
}
