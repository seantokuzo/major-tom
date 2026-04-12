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
    @State private var showMiniMap = false
    @State private var miniMapDragPosition: SnapPosition? = nil
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
                .ignoresSafeArea()
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

            // Mini-map button (long press to open overlay)
            miniMapButton
        }
        .padding(MajorTomTheme.Spacing.md)
    }

    /// Mini-map button that opens the full overlay on long press.
    private var miniMapButton: some View {
        VStack(spacing: 2) {
            Text("MAP")
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)

            // Tiny 2×4 grid preview
            HStack(spacing: 1) {
                miniMapTinyColumn(types: [.commandBridge, .engineering, .crewQuarters, .galley])
                miniMapTinyColumn(types: [.bioDome, .arboretum, .trainingBay, .evaBay])
            }
            .frame(width: 36, height: 48)
        }
        .padding(MajorTomTheme.Spacing.xs)
        .glassBackground()
        .onLongPressGesture(minimumDuration: 0.4) {
            HapticService.impact(.medium)
            showMiniMap = true
        }
    }

    /// Tiny column for the mini-map button preview.
    private func miniMapTinyColumn(types: [ModuleType]) -> some View {
        VStack(spacing: 1) {
            ForEach(types, id: \.rawValue) { moduleType in
                Rectangle()
                    .fill(Color(uiColor: StationPalette.floorColor(for: moduleType)))
                    .cornerRadius(1)
            }
        }
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

    /// Camera center Y for showing two adjacent rows.
    /// Row pair midpoints: rows 0+1 → 1970, rows 1+2 → 1310, rows 2+3 → 650
    private func cameraCenter(column: Int, tappedRow: Int) -> CGPoint {
        let x: CGFloat = column == 0 ? 300 : 940

        // Tapped room becomes the top room, show it + the row below
        // Exception: last row (3) → show rows 2+3 instead
        let pairY: CGFloat
        switch tappedRow {
        case 0: pairY = 1970   // rows 0+1
        case 1: pairY = 1310   // rows 1+2
        case 2: pairY = 650    // rows 2+3
        case 3: pairY = 650    // rows 2+3 (last row = show it as bottom)
        default: pairY = 1970
        }

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
