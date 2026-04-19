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
///
/// Tab-Keyed Offices (Wave 4) — keyed by `tabId`, not sessionId. A tab can
/// host multiple concurrent Claude sessions; legacy cli/vscode Offices use
/// their sessionId as a synthetic tabId (resolved inside `OfficeSceneManager`).
struct OfficeView: View {
    let tabId: String
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

    /// Snapshot of sprite IDs with role aura active, for diffing.
    @State private var previousAuraIds: Set<String> = []

    /// Snapshot of sprite IDs with an active tool bubble, for diffing.
    @State private var previousToolLabels: [String: String] = [:]

    /// Sprite IDs whose tool bubble is currently suppressed (response bubble
    /// is holding the slot for 5s). Used to restore when the hold expires.
    @State private var toolBubbleHolds: Set<String> = []

    /// Per-sprite restore tasks for the 5s tool-bubble hold. Tracked so a new
    /// preview arriving within an existing 5s window cancels the previous
    /// restore Task — otherwise two overlapping timers would clear the hold
    /// early.
    @State private var toolBubbleHoldTasks: [String: Task<Void, Never>] = [:]

    /// Snapshot of sprite progress metrics for diffing.
    @State private var previousProgressMetrics: [String: OfficeViewModel.ProgressMetrics] = [:]

    /// Snapshot of sprite IDs currently grayed out as disconnected, for diffing.
    @State private var previousDisconnectedIds: Set<String> = []

    /// Activated scene — populated in onAppear, avoids side effects in body.
    @State private var activatedScene: OfficeScene?

    /// Tracks whether the camera is on the leftmost column. Drives the
    /// NavigationStack interactive-pop gesture — edge-swipe back should
    /// only fire when the user can't pan further left, otherwise a
    /// normal pan-to-column-1 gesture accidentally pops the view.
    @State private var isAtFirstColumn: Bool = true

    @Environment(\.dismiss) private var dismiss

    /// Resolved viewModel from the scene manager.
    private var viewModel: OfficeViewModel? {
        sceneManager.viewModel(for: tabId)
    }

    /// Resolved scene — reads from @State (set in onAppear) or peeks without side effects.
    private var currentScene: OfficeScene? {
        activatedScene ?? sceneManager.peekScene(for: tabId)
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
            activatedScene = sceneManager.activateOffice(for: tabId)
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
                    sceneManager.closeOffice(for: tabId)
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
                .background(SwipeBackGestureToggle(isEnabled: isAtFirstColumn))
                .onAppear {
                    // Initial state: scene starts on col1Top (see OfficeScene init).
                    isAtFirstColumn = snapIsFirstColumn(scene.activeSnapPosition)
                    scene.onSnapPositionChanged = { position in
                        isAtFirstColumn = snapIsFirstColumn(position)
                    }
                }
                .onDisappear {
                    // OfficeSceneManager retains scenes across navigations;
                    // clear the callback so popped OfficeViews don't get
                    // stale state updates and the view's @State bag isn't
                    // kept alive past the SwiftUI teardown.
                    scene.onSnapPositionChanged = nil
                }
                .onChange(of: viewModel.agents, initial: true) { _, newAgents in
                    syncScene(with: newAgents, viewModel: viewModel, scene: scene)
                }
                .onChange(of: viewModel.unreadResponseSpriteIds, initial: true) { _, ids in
                    syncUnreadGlows(ids: ids, scene: scene)
                }
                .onChange(of: viewModel.pendingBubblePreviews, initial: true) { _, previews in
                    fireBubblePreviews(previews, viewModel: viewModel, scene: scene)
                }
                .onChange(of: viewModel.spriteAuraActive, initial: true) { _, ids in
                    syncRoleAuras(ids: ids, viewModel: viewModel, scene: scene)
                }
                .onChange(of: viewModel.spriteToolLabels, initial: true) { _, labels in
                    syncToolBubbles(labels: labels, scene: scene)
                }
                .onChange(of: viewModel.spriteProgressMetrics, initial: true) { _, metrics in
                    syncProgressMetrics(metrics: metrics, scene: scene)
                }
                .onChange(of: viewModel.disconnectedSpriteIds, initial: true) { _, ids in
                    syncDisconnectedStates(ids: ids, scene: scene)
                }
                .onChange(of: ObjectIdentifier(scene)) { _, _ in
                    // Scene identity changed (cold rebuild after LRU eviction) —
                    // reset diffing state so all currently-unread glows/previews
                    // are re-applied to the fresh scene instead of skipped.
                    previousUnreadIds = []
                    firedPreviewIds = []
                    previousAuraIds = []
                    previousToolLabels = [:]
                    previousProgressMetrics = [:]
                    previousDisconnectedIds = []
                    toolBubbleHolds = []
                    for (_, task) in toolBubbleHoldTasks { task.cancel() }
                    toolBubbleHoldTasks = [:]
                    syncUnreadGlows(ids: viewModel.unreadResponseSpriteIds, scene: scene)
                    fireBubblePreviews(viewModel.pendingBubblePreviews, viewModel: viewModel, scene: scene)
                    syncRoleAuras(ids: viewModel.spriteAuraActive, viewModel: viewModel, scene: scene)
                    syncToolBubbles(labels: viewModel.spriteToolLabels, scene: scene)
                    syncProgressMetrics(metrics: viewModel.spriteProgressMetrics, scene: scene)
                    syncDisconnectedStates(ids: viewModel.disconnectedSpriteIds, scene: scene)
                }
                .onChange(of: relay?.connectionState) { _, newState in
                    handleConnectionStateChange(newState, viewModel: viewModel)
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
    ///
    /// M3 priority: if a tool bubble is currently showing on this sprite, yield
    /// to the response bubble for 5 seconds, then restore the tool bubble if
    /// it's still active. The green glow persists independently on the sprite.
    private func fireBubblePreviews(_ previews: [String: String], viewModel: OfficeViewModel, scene: OfficeScene) {
        for (spriteId, text) in previews where !firedPreviewIds.contains(spriteId) {
            // M3: hide active tool bubble for the 5s response window.
            if viewModel.spriteToolLabels[spriteId] != nil {
                scene.hideToolBubble(on: spriteId)
                toolBubbleHolds.insert(spriteId)
                // Cancel any existing restore task for this sprite so a second
                // preview inside the 5s window doesn't let a stale timer clear
                // the hold early.
                toolBubbleHoldTasks[spriteId]?.cancel()
                // After 5s, if the tool is still active, re-show it.
                let task = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    if let label = viewModel.spriteToolLabels[spriteId] {
                        scene.showToolBubble(on: spriteId, label: label)
                    }
                    toolBubbleHolds.remove(spriteId)
                    toolBubbleHoldTasks[spriteId] = nil
                }
                toolBubbleHoldTasks[spriteId] = task
            }
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

    // MARK: - Wave 5 Sync Helpers

    /// Apply role-aura adds/removes to the scene based on `spriteAuraActive`.
    /// The canonical role comes from the matching AgentState.
    private func syncRoleAuras(ids: Set<String>, viewModel: OfficeViewModel, scene: OfficeScene) {
        let additions = ids.subtracting(previousAuraIds)
        let removals = previousAuraIds.subtracting(ids)
        for id in additions {
            let role = viewModel.agents.first(where: { $0.id == id })?.canonicalRole
            scene.showRoleAura(on: id, canonicalRole: role)
        }
        for id in removals {
            scene.hideRoleAura(on: id)
        }
        previousAuraIds = ids
    }

    /// Apply tool-bubble updates: show new bubbles, swap labels when changed,
    /// hide when removed. Respects the M3 hold set (response bubble is
    /// holding the slot for 5 seconds).
    private func syncToolBubbles(labels: [String: String], scene: OfficeScene) {
        let currentIds = Set(labels.keys)
        let previousIds = Set(previousToolLabels.keys)

        // Additions + label changes
        for (id, label) in labels {
            let prev = previousToolLabels[id]
            if prev != label && !toolBubbleHolds.contains(id) {
                scene.showToolBubble(on: id, label: label)
            }
        }

        // Removals
        for id in previousIds.subtracting(currentIds) {
            scene.hideToolBubble(on: id)
        }

        previousToolLabels = labels
    }

    /// Apply progress indicator updates: update text when changed, hide when removed.
    private func syncProgressMetrics(metrics: [String: OfficeViewModel.ProgressMetrics], scene: OfficeScene) {
        let currentIds = Set(metrics.keys)
        let previousIds = Set(previousProgressMetrics.keys)

        for (id, m) in metrics {
            let prev = previousProgressMetrics[id]
            if prev != m {
                scene.updateProgressIndicator(on: id, toolCount: m.toolCount, tokenCount: m.tokenCount)
            }
        }

        for id in previousIds.subtracting(currentIds) {
            scene.hideProgressIndicator(on: id)
        }

        previousProgressMetrics = metrics
    }

    // MARK: - Wave 6 Sync Helpers

    /// Apply gray-out / restore to sprites based on `disconnectedSpriteIds`.
    /// Additions get the desaturated "reconnecting" treatment; removals have
    /// the treatment cleared so the sprite returns to full color.
    private func syncDisconnectedStates(ids: Set<String>, scene: OfficeScene) {
        let additions = ids.subtracting(previousDisconnectedIds)
        let removals = previousDisconnectedIds.subtracting(ids)
        for id in additions {
            scene.showDisconnectedState(on: id)
        }
        for id in removals {
            scene.hideDisconnectedState(on: id)
        }
        previousDisconnectedIds = ids
    }

    /// Debounced disconnect/reconnect handler (S4). The debounce itself lives
    /// on `OfficeViewModel` so the pending Task survives view appear/disappear
    /// cycles — this function only dispatches connection-state transitions to
    /// the view model and triggers relay-side side effects on reconnect.
    ///
    /// - On `.disconnected` or `.reconnecting`: ask the view model to start
    ///   the 1-second debounce. A quick reconnect cancels it before any
    ///   gray-out is applied.
    /// - On `.connected`: ask the view model to resolve, then flush queued
    ///   sprite messages and re-request sprite state from the relay so the
    ///   scene reconciles any subagents that completed/spawned during the drop.
    private func handleConnectionStateChange(_ newState: ConnectionState?, viewModel: OfficeViewModel) {
        switch newState {
        case .disconnected, .reconnecting:
            viewModel.beginDisconnectDebounce()

        case .connected:
            viewModel.resolveReconnect()
            if let sid = viewModel.sessionId {
                relay?.flushQueuedSpriteMessages(for: sid)
                relay?.requestSpriteState(for: sid)
            }

        case .connecting, nil:
            break
        }
    }

    // MARK: - Scene Sync

    private func syncScene(with agents: [AgentState], viewModel: OfficeViewModel, scene: OfficeScene) {
        let currentIds = Set(agents.map(\.id))

        for agent in agents where !previousAgentIds.contains(agent.id) {
            scene.addAgent(id: agent.id, name: agent.name, characterType: agent.characterType)
            if let deskIndex = agent.deskIndex {
                scene.highlightDesk(deskIndex, occupied: true)
                scene.moveAgentToDesk(id: agent.id, deskIndex: deskIndex)
            } else if let overflowPosition = agent.overflowPosition {
                // S5: programmatic overflow placement in Command Bridge floor space.
                scene.moveAgentToOverflow(id: agent.id, position: overflowPosition)
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
            } else if let overflowPosition = agent.overflowPosition {
                // S5: overflow fallback — walk to the claimed floor position.
                scene.moveAgentToOverflow(id: agent.id, position: overflowPosition)
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

    /// Whether a snap position represents the leftmost column of rooms.
    /// Used to gate the NavigationStack interactive-pop gesture.
    private func snapIsFirstColumn(_ position: SnapPosition) -> Bool {
        switch position {
        case .col1Top, .col1Bottom: return true
        default: return false
        }
    }
}

// MARK: - Swipe-back gesture control

/// Toggles the parent UINavigationController's `interactivePopGestureRecognizer`
/// so edge-swipe back is disabled while the user is panning the Office scene
/// and re-enabled only when the camera is parked on the leftmost column.
private struct SwipeBackGestureToggle: UIViewRepresentable {
    let isEnabled: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        DispatchQueue.main.async { apply(isEnabled, from: view) }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async { apply(isEnabled, from: view) }
    }

    static func dismantleUIView(_ view: UIView, coordinator: ()) {
        // Re-enable on teardown so the rest of the app isn't left stuck
        // with the pop gesture disabled.
        apply(true, from: view)
    }

    @discardableResult
    private static func apply(_ enabled: Bool, from view: UIView) -> Bool {
        var responder: UIResponder? = view
        while let r = responder {
            if let nav = r as? UINavigationController {
                nav.interactivePopGestureRecognizer?.isEnabled = enabled
                return true
            }
            responder = r.next
        }
        return false
    }

    private func apply(_ enabled: Bool, from view: UIView) {
        Self.apply(enabled, from: view)
    }
}

#Preview {
    NavigationStack {
        OfficeView(
            tabId: "preview",
            sceneManager: {
                let mgr = OfficeSceneManager()
                mgr.createOffice(for: "preview")
                return mgr
            }(),
            relay: nil
        )
    }
}
