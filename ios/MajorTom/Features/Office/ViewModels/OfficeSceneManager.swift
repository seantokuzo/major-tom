import Foundation
import SpriteKit

// MARK: - Office Scene Manager

/// Manages per-session OfficeViewModel + OfficeScene pairs.
/// Each active session can have its own Office with independent agent state and scene.
/// Scenes are LRU-evicted beyond `maxWarmScenes` to control memory (~30-60MB each).
@Observable
@MainActor
final class OfficeSceneManager {

    // MARK: - Types

    struct OfficeEntry {
        let viewModel: OfficeViewModel
        var scene: OfficeScene?
        var lastAccessed: Date
        /// True when `createOffice` was called (full office with scene + idle sprites).
        /// False for lightweight entries created by `ensureViewModel`.
        var hasOffice: Bool = false
    }

    // MARK: - State

    /// Per-session offices keyed by sessionId.
    private(set) var offices: [String: OfficeEntry] = [:]

    /// Maximum number of warm (in-memory) scenes before LRU eviction kicks in.
    static let maxWarmScenes = 2

    /// Relay service reference for sending sprite.state.request on cold rebuild.
    weak var relay: RelayService?

    // MARK: - Public API

    /// Returns the OfficeViewModel for a session, or nil if no Office exists.
    func viewModel(for sessionId: String) -> OfficeViewModel? {
        offices[sessionId]?.viewModel
    }

    /// Creates a new Office for a session (viewModel + scene).
    /// Returns the newly created entry. If an Office already exists, returns it.
    @discardableResult
    func createOffice(for sessionId: String) -> OfficeEntry {
        if var existing = offices[sessionId] {
            // If the entry already has a scene (full office), just touch LRU and return.
            if existing.scene != nil {
                offices[sessionId]?.lastAccessed = Date()
                return existing
            }

            // Upgrade a lightweight ensureViewModel entry: create scene, populate idle sprites,
            // request sprite state — everything a fresh createOffice would do.
            let scene = makeScene()
            existing.scene = scene
            existing.lastAccessed = Date()
            existing.hasOffice = true
            offices[sessionId] = existing

            existing.viewModel.populateIdleSprites()
            relay?.requestSpriteState(for: sessionId)

            evictIfNeeded(excluding: sessionId)
            return existing
        }

        let vm = OfficeViewModel()
        vm.sessionId = sessionId

        let scene = makeScene()

        let entry = OfficeEntry(
            viewModel: vm,
            scene: scene,
            lastAccessed: Date(),
            hasOffice: true
        )
        offices[sessionId] = entry

        // Populate idle sprites for the fresh office
        vm.populateIdleSprites()

        // Request current sprite state from relay for this session
        relay?.requestSpriteState(for: sessionId)

        evictIfNeeded(excluding: sessionId)
        return entry
    }

    /// Side-effect-free scene peek — returns the current scene (or nil) without
    /// touching LRU timestamps or triggering cold rebuilds.
    /// Safe to call from SwiftUI computed properties / view body.
    func peekScene(for sessionId: String) -> OfficeScene? {
        offices[sessionId]?.scene
    }

    /// Activates an office for viewing: touches LRU, cold-rebuilds the scene if
    /// evicted, and syncs existing agent state into a fresh scene.
    /// Call from `.onAppear` or other imperative contexts — NOT from view body.
    @discardableResult
    func activateOffice(for sessionId: String) -> OfficeScene? {
        guard var entry = offices[sessionId] else { return nil }

        // Touch LRU timestamp
        entry.lastAccessed = Date()
        offices[sessionId] = entry

        // If scene exists, return it
        if let scene = entry.scene {
            return scene
        }

        // Cold rebuild: create a new scene, restore from viewModel state
        let scene = makeScene()
        offices[sessionId]?.scene = scene

        // Sync any existing agents into the fresh scene so they render immediately
        // (onChange won't fire for the initial value on a newly created scene).
        let vm = entry.viewModel
        for agent in vm.agents {
            scene.addAgent(id: agent.id, name: agent.name, characterType: agent.characterType)
            if let deskIndex = agent.deskIndex {
                scene.highlightDesk(deskIndex, occupied: true)
                scene.moveAgentToDesk(id: agent.id, deskIndex: deskIndex)
            }
            switch agent.status {
            case .working:
                scene.updateAgentStatus(id: agent.id, status: .working)
            case .idle:
                scene.updateAgentStatus(id: agent.id, status: .idle)
            default:
                break
            }
        }

        // If viewModel has no real agents, request state from relay.
        if vm.agents.filter({ !$0.id.hasPrefix("idle-") }).isEmpty {
            relay?.requestSpriteState(for: sessionId)
        }

        evictIfNeeded(excluding: sessionId)
        return scene
    }

    /// Creates a lightweight OfficeViewModel entry (no scene) for a session so
    /// agent events can accumulate before the user opens an Office.
    @discardableResult
    func ensureViewModel(for sessionId: String) -> OfficeViewModel {
        if let existing = offices[sessionId] {
            return existing.viewModel
        }
        let vm = OfficeViewModel()
        vm.sessionId = sessionId

        let entry = OfficeEntry(
            viewModel: vm,
            scene: nil,
            lastAccessed: Date()
        )
        offices[sessionId] = entry
        return vm
    }

    /// Closes an Office for a session. Destroys both scene and viewModel.
    /// Does NOT affect the terminal session on the relay.
    func closeOffice(for sessionId: String) {
        guard let entry = offices[sessionId] else { return }
        entry.scene?.isPaused = true
        offices.removeValue(forKey: sessionId)
    }

    /// Session IDs that have Offices created (for OfficeManagerView).
    /// Excludes lightweight entries created by `ensureViewModel` that were never upgraded.
    var linkedSessionIds: Set<String> {
        Set(offices.filter { $0.value.hasOffice }.keys)
    }

    // MARK: - Private

    /// Create a fresh OfficeScene with the standard dimensions.
    private func makeScene() -> OfficeScene {
        let scene = OfficeScene()
        scene.size = CGSize(width: StationLayout.sceneWidth, height: StationLayout.sceneHeight)
        scene.scaleMode = .aspectFill
        return scene
    }

    /// LRU eviction: destroy scenes beyond maxWarmScenes (keep viewModel alive).
    private func evictIfNeeded(excluding activeSessionId: String) {
        let warmEntries = offices.filter { $0.value.scene != nil && $0.key != activeSessionId }

        guard warmEntries.count >= Self.maxWarmScenes else { return }

        // Sort by lastAccessed ascending (oldest first)
        let sorted = warmEntries.sorted { $0.value.lastAccessed < $1.value.lastAccessed }

        // Evict oldest entries until we're under the threshold
        let evictCount = warmEntries.count - Self.maxWarmScenes + 1  // +1 for the active one
        for entry in sorted.prefix(evictCount) {
            offices[entry.key]?.scene?.isPaused = true
            offices[entry.key]?.scene = nil
        }
    }
}
