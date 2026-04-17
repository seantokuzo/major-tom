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
/// Now session-aware: gets its viewModel and scene from OfficeSceneManager.
struct OfficeView: View {
    let sessionId: String
    var sceneManager: OfficeSceneManager
    var relay: RelayService?

    @State private var activeSheet: OfficeSheetType?
    @State private var showMiniMap = false

    /// Space weather engine for cosmetic atmospheric events.
    @State private var spaceWeather = SpaceWeatherEngine()

    /// Previous agent states for diffing.
    @State private var previousAgentIds: Set<String> = []
    @State private var previousStatuses: [String: AgentStatus] = [:]

    /// Snapshot of sprite IDs with the green unread-glow attached, for diffing.
    @State private var previousUnreadIds: Set<String> = []

    /// Snapshot of bubble-preview sprite IDs that have already been rendered.
    @State private var firedPreviewIds: Set<String> = []

    /// Activated scene — populated in onAppear, avoids side effects in body.
    @State private var activatedScene: OfficeScene?

    @Environment(\.dismiss) private var dismiss

    /// Resolved viewModel from the scene manager.
    private var viewModel: OfficeViewModel? {
        sceneManager.viewModel(for: sessionId)
    }

    /// Resolved scene — reads from @State (set in onAppear) or peeks without side effects.
    private var currentScene: OfficeScene? {
        activatedScene ?? sceneManager.peekScene(for: sessionId)
    }

    var body: some View {
        Group {
            if let viewModel, let scene = currentScene {
                officeContent(viewModel: viewModel, scene: scene)
            } else {
                // Office was closed or not yet created — show placeholder
                VStack(spacing: MajorTomTheme.Spacing.lg) {
                    Image(systemName: "building.2.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    Text("Office not available")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MajorTomTheme.Colors.background)
            }
        }
        .task {
            // Activate the scene at the top level so it runs regardless of which
            // branch rendered (content vs placeholder). If the scene was LRU-evicted,
            // this triggers a cold rebuild and populates @State so the view re-renders.
            activatedScene = sceneManager.activateOffice(for: sessionId)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let vm = viewModel {
                    Text("\(vm.agents.count) agents")
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sceneManager.closeOffice(for: sessionId)
                    dismiss()
                } label: {
                    Label("Close Office", systemImage: "xmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                }
            }
        }
    }

    // MARK: - Office Content

    @ViewBuilder
    private func officeContent(viewModel: OfficeViewModel, scene: OfficeScene) -> some View {
        ZStack {
            // SpriteKit scene
            SpriteView(scene: scene)
                .ignoresSafeArea(.all, edges: .bottom)
                .onChange(of: viewModel.agents, initial: true) { _, newAgents in
                    syncScene(with: newAgents, viewModel: viewModel, scene: scene)
                }
                .onChange(of: viewModel.unreadResponseSpriteIds, initial: true) { _, ids in
                    syncUnreadGlows(ids: ids, scene: scene)
                }
                .onChange(of: viewModel.pendingBubblePreviews, initial: true) { _, previews in
                    fireBubblePreviews(previews, viewModel: viewModel, scene: scene)
                }
                .onChange(of: ObjectIdentifier(scene)) { _, _ in
                    // Scene identity changed (cold rebuild after LRU eviction) —
                    // reset diffing state so all currently-unread glows/previews
                    // are re-applied to the fresh scene instead of skipped.
                    previousUnreadIds = []
                    firedPreviewIds = []
                    syncUnreadGlows(ids: viewModel.unreadResponseSpriteIds, scene: scene)
                    fireBubblePreviews(viewModel.pendingBubblePreviews, viewModel: viewModel, scene: scene)
                }
                .onChange(of: relay?.connectionState) { _, newState in
                    if newState == .connected, let sid = viewModel.sessionId {
                        relay?.flushQueuedSpriteMessages(for: sid)
                    }
                }

            // Top overlay: agent count + controls
            VStack {
                topBar(viewModel: viewModel, scene: scene)
                Spacer()
            }

            // Mini-map overlay (shown on long-press of MAP button)
            if showMiniMap {
                miniMapOverlay(scene: scene)
            }
        }
        .onAppear {
            // Resume the SKScene update loop when the Office tab becomes visible.
            scene.isPaused = false
            // Wire theme + mood engines and furniture registry to the scene
            scene.themeEngine = viewModel.themeEngine
            scene.moodEngine = viewModel.moodEngine
            // Wire scene's furniture registry into the activity engine
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

            // Start activity cycling
            viewModel.activityEngine.startCycling { [weak scene, weak viewModel] agentId, _ in
                guard let viewModel, let scene else { return }
                viewModel.activityAnimator.stopPhase(for: agentId, furnitureNodes: scene.furnitureNodes)
                guard let agent = viewModel.agents.first(where: { $0.id == agentId }) else { return }
                let room = scene.currentRoom(for: agentId) ?? ModuleType.crewQuarters.rawValue
                if let assignment = viewModel.activityEngine.assignActivity(
                    agentId: agentId,
                    characterType: agent.characterType,
                    currentRoom: room
                ) {
                    scene.moveAgentToActivity(id: agentId, assignment: assignment) { sprite in
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
            // Pause the SKScene update loop
            scene.isPaused = true
            // Stop engines + activity cycling
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
                    SpriteInspectorView(
                        agent: agent,
                        viewModel: viewModel,
                        activityDescription: viewModel.activityEngine.activityDescription(for: agent.id),
                        onRename: { newName in
                            viewModel.renameAgent(id: agent.id, newName: newName)
                            scene.updateAgentName(id: agent.id, name: newName)
                        },
                        onSendLinkedMessage: relay.map { relayRef in
                            { queued in
                                let connected = relayRef.connectionState == .connected
                                if connected {
                                    Task { await relayRef.sendSpriteMessage(queued) }
                                }
                                return connected
                            }
                        },
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
                        viewModel.shuffleCrew()
                    }
                )
            }
        }
        .onChange(of: activeSheet) { _, newValue in
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

    private func topBar(viewModel: OfficeViewModel, scene: OfficeScene) -> some View {
        HStack(spacing: MajorTomTheme.Spacing.sm) {
            // Map button
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

    private func miniMapOverlay(scene: OfficeScene) -> some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture {
                    showMiniMap = false
                }

            VStack(spacing: 16) {
                Text("STATION MAP")
                    .font(.system(.headline, design: .monospaced, weight: .bold))
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)

                HStack(spacing: 8) {
                    VStack(spacing: 4) {
                        miniMapRoom(.commandBridge, column: 0, row: 0, scene: scene)
                        miniMapRoom(.engineering, column: 0, row: 1, scene: scene)
                        miniMapRoom(.crewQuarters, column: 0, row: 2, scene: scene)
                        miniMapRoom(.galley, column: 0, row: 3, scene: scene)
                    }
                    VStack(spacing: 4) {
                        miniMapRoom(.bioDome, column: 1, row: 0, scene: scene)
                        miniMapRoom(.arboretum, column: 1, row: 1, scene: scene)
                        miniMapRoom(.trainingBay, column: 1, row: 2, scene: scene)
                        miniMapRoom(.evaBay, column: 1, row: 3, scene: scene)
                    }
                }

                Text("Tap a room to navigate")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }
        }
        .transition(.opacity)
    }

    private func cameraCenter(column: Int, tappedRow: Int) -> CGPoint {
        let colX = column == 0 ? StationLayout.col1X : StationLayout.col2X
        let x = colX + StationLayout.roomWidth / 2
        let rh = StationLayout.roomHeight
        let ch = StationLayout.corridorHeight
        let effectiveRow = min(tappedRow, 2)
        let topOfPair = StationLayout.sceneHeight - CGFloat(effectiveRow) * (rh + ch)
        let pairY = topOfPair - rh - ch / 2
        return CGPoint(x: x, y: pairY)
    }

    private func miniMapRoom(_ moduleType: ModuleType, column: Int, row: Int, scene: OfficeScene) -> some View {
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

    // MARK: - /btw Visuals Sync (Wave 4)

    /// Apply green-glow adds/removes based on viewModel.unreadResponseSpriteIds.
    private func syncUnreadGlows(ids: Set<String>, scene: OfficeScene) {
        let additions = ids.subtracting(previousUnreadIds)
        let removals = previousUnreadIds.subtracting(ids)
        for id in additions {
            scene.showUnreadResponseGlow(on: id)
        }
        for id in removals {
            scene.hideUnreadResponseGlow(on: id)
        }
        previousUnreadIds = ids
    }

    /// Fire pending bubble previews once per sprite.
    private func fireBubblePreviews(_ previews: [String: String], viewModel: OfficeViewModel, scene: OfficeScene) {
        for (spriteId, text) in previews where !firedPreviewIds.contains(spriteId) {
            scene.showResponsePreviewBubble(on: spriteId, text: shortPreview(text))
            firedPreviewIds.insert(spriteId)
            viewModel.consumeBubblePreview(for: spriteId)
        }
        // Clean up fired IDs that no longer have pending previews (e.g. after
        // Cool Beans dropped state), so next response re-fires.
        firedPreviewIds = firedPreviewIds.intersection(Set(previews.keys))
    }

    /// Truncate long responses for the speech-bubble preview.
    private func shortPreview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 77)
        return String(trimmed[..<idx]) + "…"
    }

    // MARK: - Scene Sync

    private func syncScene(with agents: [AgentState], viewModel: OfficeViewModel, scene: OfficeScene) {
        let currentIds = Set(agents.map(\.id))

        for agent in agents where !previousAgentIds.contains(agent.id) {
            scene.addAgent(id: agent.id, name: agent.name, characterType: agent.characterType)
            if let deskIndex = agent.deskIndex {
                scene.highlightDesk(deskIndex, occupied: true)
                scene.moveAgentToDesk(id: agent.id, deskIndex: deskIndex)
            }
        }

        for id in previousAgentIds where !currentIds.contains(id) {
            viewModel.activityAnimator.stopPhase(for: id, furnitureNodes: scene.furnitureNodes)
            scene.removeAgent(id: id)
        }

        for agent in agents {
            let previousStatus = previousStatuses[agent.id]
            if previousStatus != agent.status {
                handleStatusChange(agent: agent, from: previousStatus, viewModel: viewModel, scene: scene)
            }
        }

        previousAgentIds = currentIds
        previousStatuses = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0.status) })
    }

    private func handleStatusChange(agent: AgentState, from previousStatus: AgentStatus?, viewModel: OfficeViewModel, scene: OfficeScene) {
        switch agent.status {
        case .spawning:
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
            assignIdleActivity(for: agent, viewModel: viewModel, scene: scene)

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

    private func assignIdleActivity(for agent: AgentState, viewModel: OfficeViewModel, scene: OfficeScene) {
        let isIdleSprite = agent.id.hasPrefix("idle-")

        let doAssign = { [viewModel, scene] in
            guard let current = viewModel.agents.first(where: { $0.id == agent.id }),
                  current.status == .idle else { return }

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
            let delay = Double.random(in: 0.5...2.5)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                doAssign()
            }
        } else {
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
    NavigationStack {
        OfficeView(
            sessionId: "preview",
            sceneManager: {
                let mgr = OfficeSceneManager()
                mgr.createOffice(for: "preview")
                return mgr
            }(),
            relay: nil
        )
    }
}
