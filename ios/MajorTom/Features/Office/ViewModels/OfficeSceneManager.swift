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
        if let existing = offices[sessionId] {
            offices[sessionId]?.lastAccessed = Date()
            return existing
        }

        let vm = OfficeViewModel()
        vm.sessionId = sessionId

        let scene = makeScene()

        let entry = OfficeEntry(
            viewModel: vm,
            scene: scene,
            lastAccessed: Date()
        )
        offices[sessionId] = entry

        // Populate idle sprites for the fresh office
        vm.populateIdleSprites()

        // Request current sprite state from relay for this session
        relay?.requestSpriteState(for: sessionId)

        evictIfNeeded(excluding: sessionId)
        return entry
    }

    /// Returns the scene for a session. If the scene was evicted (cold), rebuilds it
    /// from the viewModel's current agent state.
    func scene(for sessionId: String) -> OfficeScene? {
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

        // If viewModel has existing agents, the scene will pick them up
        // via OfficeView's onChange(of: viewModel.agents) sync.
        // If viewModel has no agents (never received events), request state from relay.
        if entry.viewModel.agents.filter({ !$0.id.hasPrefix("idle-") }).isEmpty {
            relay?.requestSpriteState(for: sessionId)
        }

        evictIfNeeded(excluding: sessionId)
        return scene
    }

    /// Closes an Office for a session. Destroys both scene and viewModel.
    /// Does NOT affect the terminal session on the relay.
    func closeOffice(for sessionId: String) {
        guard let entry = offices[sessionId] else { return }
        entry.scene?.isPaused = true
        offices.removeValue(forKey: sessionId)
    }

    /// Session IDs that have Offices created (for OfficeManagerView).
    var linkedSessionIds: Set<String> {
        Set(offices.keys)
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
