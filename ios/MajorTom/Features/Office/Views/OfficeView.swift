import SwiftUI
import SpriteKit

// MARK: - Office Sheet State

/// Enum to consolidate sheet presentations and avoid .sheet conflicts.
private enum OfficeSheetType: Identifiable {
    case inspector
    case gallery
    case crewPicker

    var id: String {
        switch self {
        case .inspector: return "inspector"
        case .gallery: return "gallery"
        case .crewPicker: return "crewPicker"
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
    @State private var showMiniMap = false
    @State private var scene: OfficeScene = {
        let scene = OfficeScene()
        scene.size = CGSize(width: StationLayout.sceneWidth, height: StationLayout.sceneHeight)
        scene.scaleMode = .aspectFill
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
                .ignoresSafeArea(.all, edges: .bottom)
                .onChange(of: viewModel.agents) { _, newAgents in
                    syncScene(with: newAgents)
                }

            // Top overlay: agent count + controls
            VStack {
                topBar
                Spacer()
            }

            // Mini-map overlay (shown on long-press of MAP button)
            if showMiniMap {
                miniMapOverlay
            }
        }
        .onAppear {
            // Resume the SKScene update loop when the Office tab becomes visible.
            // Paired with `scene.isPaused = true` in `.onDisappear` — idle tabs
            // should not be running the 60fps SpriteKit render/update loop.
            scene.isPaused = false
            // Wire theme + mood engines and furniture registry to the scene
            scene.themeEngine = viewModel.themeEngine
            scene.moodEngine = viewModel.moodEngine
            // Wire scene's furniture registry into the activity engine
            // (scene owns it because didMove runs before onAppear)
            viewModel.activityEngine.setFurnitureRegistry(scene.furnitureRegistry)

            // Start engines
            viewModel.themeEngine.start()
            viewModel.moodEngine.start()

            scene.onAgentTapped = { agentId in
                if let agent = viewModel.agents.first(where: { $0.id == agentId }) {
                    HapticService.selection()
                    viewModel.selectAgent(agent)
                }
            }

            // Start activity cycling — when an activity expires, reassign
            viewModel.activityEngine.startCycling { [weak scene, weak viewModel] agentId, _ in
                guard let viewModel, let scene else { return }

                // Stop the outgoing activity's animation phase
                viewModel.activityAnimator.stopPhase(for: agentId, furnitureNodes: scene.furnitureNodes)

                guard let agent = viewModel.agents.first(where: { $0.id == agentId }) else { return }
                let room = scene.currentRoom(for: agentId) ?? ModuleType.crewQuarters.rawValue
                if let assignment = viewModel.activityEngine.assignActivity(
                    agentId: agentId,
                    characterType: agent.characterType,
                    currentRoom: room
                ) {
                    scene.moveAgentToActivity(id: agentId, assignment: assignment) { sprite in
                        // Start animation phase when agent arrives at new activity
                        if let definition = ActivityRegistry.shared.activity(byId: assignment.activityId) {
                            viewModel.activityAnimator.startPhase(
                                agentId: agentId,
                                assignment: assignment,
                                definition: definition,
                                sprite: sprite,
                                furnitureNodes: scene.furnitureNodes,
                                furnitureRegistry: viewModel.activityEngine.furnitureRegistry
                            )
                        }
                    }
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
            // Pause the SKScene update loop so a hidden Office tab does not burn
            // CPU/battery running updateParallax, applyAgentMoods, etc.
            scene.isPaused = true
            // Stop engines + activity cycling when view disappears
            viewModel.activityAnimator.stopAll(furnitureNodes: scene.furnitureNodes)
            viewModel.themeEngine.stop()
            viewModel.moodEngine.stop()
            viewModel.activityEngine.stopCycling()
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
                        activityDescription: viewModel.activityEngine.activityDescription(for: agent.id),
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
            case .crewPicker:
                CrewPickerView(
                    crewRoster: viewModel.crewRoster,
                    onDismiss: {
                        activeSheet = nil
                        // Repopulate with new preferences
                        viewModel.shuffleCrew()
                    }
                )
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
        HStack(spacing: MajorTomTheme.Spacing.sm) {
            // Map button (opens full mini-map overlay)
            Button {
                HapticService.impact(.light)
                showMiniMap = true
            } label: {
                Image(systemName: "map.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .padding(MajorTomTheme.Spacing.sm)
                    .glassBackground()
            }
            .accessibilityLabel("Open station map")
            .accessibilityHint("Shows the full station overview to jump between rooms")

            // Office options menu
            Menu {
                Section("\(viewModel.agents.count) agent\(viewModel.agents.count == 1 ? "" : "s")") {
                    Button {
                        HapticService.impact(.light)
                        viewModel.shuffleCrew()
                    } label: {
                        Label("Shuffle Crew", systemImage: "shuffle")
                    }

                    Button {
                        activeSheet = .crewPicker
                    } label: {
                        Label("Select Crew", systemImage: "person.2.badge.gearshape")
                    }

                    Button {
                        viewModel.showCharacterGallery = true
                    } label: {
                        Label("Character Gallery", systemImage: "person.crop.rectangle.stack")
                    }
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .padding(MajorTomTheme.Spacing.sm)
                    .glassBackground()
            }
            .accessibilityLabel("Office options")
            .accessibilityHint("Crew shuffle, picker, and character gallery")

            Spacer()
        }
        .padding(MajorTomTheme.Spacing.md)
    }

    // MARK: - Mini-Map Overlay

    /// Full-screen mini-map overlay showing the 2×4 station grid.
    /// Tapping a room pair navigates there and dismisses the overlay.
    private var miniMapOverlay: some View {
        ZStack {
            // Semi-transparent backdrop
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture {
                    showMiniMap = false
                }

            VStack(spacing: 16) {
                Text("STATION MAP")
                    .font(.system(.headline, design: .monospaced, weight: .bold))
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)

                // 2×4 grid of rooms — tap any room to navigate
                HStack(spacing: 8) {
                    // Column 1 (top to bottom = row 0 to row 3)
                    VStack(spacing: 4) {
                        miniMapRoom(.commandBridge, column: 0, row: 0)
                        miniMapRoom(.engineering, column: 0, row: 1)
                        miniMapRoom(.crewQuarters, column: 0, row: 2)
                        miniMapRoom(.galley, column: 0, row: 3)
                    }
                    // Column 2
                    VStack(spacing: 4) {
                        miniMapRoom(.bioDome, column: 1, row: 0)
                        miniMapRoom(.arboretum, column: 1, row: 1)
                        miniMapRoom(.trainingBay, column: 1, row: 2)
                        miniMapRoom(.evaBay, column: 1, row: 3)
                    }
                }

                Text("Tap a room to navigate")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }
        }
        .transition(.opacity)
    }

    /// Camera center for showing two adjacent rows. Derives X from column,
    /// Y from row pair midpoints using StationLayout dimensions.
    private func cameraCenter(column: Int, tappedRow: Int) -> CGPoint {
        let colX = column == 0 ? StationLayout.col1X : StationLayout.col2X
        let x = colX + StationLayout.roomWidth / 2

        // Each row is roomHeight + corridorHeight. Row pair midpoint:
        // rows N and N+1 → midY between bottom of N+1 and top of N
        let rh = StationLayout.roomHeight
        let ch = StationLayout.corridorHeight

        // Tapped room becomes the top room, show it + the row below
        // Exception: last row (3) → show rows 2+3 instead
        let effectiveRow = min(tappedRow, 2) // Clamp so row 3 maps to pair 2+3

        // Row 0 is at top (highest Y). Row pair N starts at:
        // topY = sceneHeight - (N * (rh + ch))
        // bottomY = topY - 2*rh - ch
        // midY = (topY + bottomY) / 2 = topY - rh - ch/2
        let topOfPair = StationLayout.sceneHeight - CGFloat(effectiveRow) * (rh + ch)
        let pairY = topOfPair - rh - ch / 2

        return CGPoint(x: x, y: pairY)
    }

    /// A single room cell in the mini-map overlay.
    private func miniMapRoom(_ moduleType: ModuleType, column: Int, row: Int) -> some View {
        return Button {
            let center = cameraCenter(column: column, tappedRow: row)
            scene.snapToCenter(center)
            showMiniMap = false
        } label: {
            VStack(spacing: 2) {
                Text(moduleType.displayName)
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 140, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(uiColor: StationPalette.floorColor(for: moduleType)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
            viewModel.activityAnimator.stopPhase(for: id, furnitureNodes: scene.furnitureNodes)
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
            viewModel.activityAnimator.stopPhase(for: agent.id, furnitureNodes: scene.furnitureNodes)
            if let deskIndex = agent.deskIndex {
                scene.moveAgentToDesk(id: agent.id, deskIndex: deskIndex)
            } else {
                scene.updateAgentStatus(id: agent.id, status: .working)
            }

        case .idle:
            assignIdleActivity(for: agent)

        case .celebrating:
            scene.celebrateAgent(id: agent.id)

        case .leaving:
            viewModel.activityAnimator.stopPhase(for: agent.id, furnitureNodes: scene.furnitureNodes)
            if let deskIndex = agent.deskIndex {
                scene.highlightDesk(deskIndex, occupied: false)
            }
            scene.moveAgentToDoor(id: agent.id)
        }
    }

    /// Assign an activity to an idle agent. Idle-prefix sprites get a staggered
    /// delay (0.5–2.5s) so they don't all start walking in the same frame.
    private func assignIdleActivity(for agent: AgentState) {
        let isIdleSprite = agent.id.hasPrefix("idle-")

        let doAssign = { [viewModel, scene] in
            // Re-verify agent still exists and is idle — staggered tasks can
            // outlive the agent (remove/claim during the 0.5–2.5s delay would
            // otherwise occupy furniture for a ghost sprite).
            guard let current = viewModel.agents.first(where: { $0.id == agent.id }),
                  current.status == .idle else { return }

            // Stop any existing animation phase before reassigning
            viewModel.activityAnimator.stopPhase(for: agent.id, furnitureNodes: scene.furnitureNodes)

            let room = scene.currentRoom(for: agent.id) ?? ModuleType.crewQuarters.rawValue
            if let assignment = viewModel.activityEngine.assignActivity(
                agentId: agent.id,
                characterType: agent.characterType,
                currentRoom: room
            ) {
                let agentId = agent.id
                let animator = viewModel.activityAnimator
                let sceneRef = scene
                let registry = viewModel.activityEngine.furnitureRegistry
                scene.moveAgentToActivity(id: agentId, assignment: assignment) { sprite in
                    if let definition = ActivityRegistry.shared.activity(byId: assignment.activityId) {
                        animator.startPhase(
                            agentId: agentId,
                            assignment: assignment,
                            definition: definition,
                            sprite: sprite,
                            furnitureNodes: sceneRef.furnitureNodes,
                            furnitureRegistry: registry
                        )
                    }
                }
            } else {
                let config = CharacterCatalog.config(for: agent.characterType)
                if let destination = config.breakBehaviors.randomElement() {
                    let areaType = breakDestinationToArea(destination)
                    scene.moveAgentToBreakArea(id: agent.id, areaType: areaType)
                } else {
                    scene.updateAgentStatus(id: agent.id, status: .idle)
                }
            }
        }

        if isIdleSprite {
            // Stagger idle sprites so they don't stampede
            let delay = Double.random(in: 0.5...2.5)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                doAssign()
            }
        } else {
            // Real agents assigned immediately
            doAssign()
        }
    }

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
