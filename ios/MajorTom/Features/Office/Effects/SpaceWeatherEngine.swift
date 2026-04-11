import SpriteKit

// MARK: - Space Weather Event

/// Types of cosmetic space weather that affect the station visually.
enum SpaceWeatherEvent: String, CaseIterable {
    case solarFlare     // Golden light wash through windows
    case meteorShower   // Bright streaks across windows
    case nebulaPassage  // Window background color shifts
    case stationRumble  // Scene shake + haptic
    case commsBurst     // Brief console screen flash
}

// MARK: - Space Weather Engine

/// Triggers random cosmetic space weather events on the station.
/// Each event is purely visual — no gameplay impact.
@Observable
@MainActor
final class SpaceWeatherEngine {

    /// Callback to fire visual effects on the scene.
    var onWeatherEvent: ((SpaceWeatherEvent) -> Void)?

    /// Whether weather events are active.
    private(set) var isRunning = false

    /// The last event that fired (for UI display).
    private(set) var lastEvent: SpaceWeatherEvent?

    private var weatherTask: Task<Void, Never>?

    // MARK: - Event Intervals (seconds)
    // Shorter intervals for a lively feel — production would use longer timers.

    private let intervals: [SpaceWeatherEvent: ClosedRange<TimeInterval>] = [
        .solarFlare:    40...90,
        .meteorShower:  50...120,
        .nebulaPassage: 90...180,
        .stationRumble: 60...150,
        .commsBurst:    15...40,
    ]

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Launch independent timers for each event type
        weatherTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                for event in SpaceWeatherEvent.allCases {
                    group.addTask { [weak self] in
                        await self?.eventLoop(for: event)
                    }
                }
            }
        }
    }

    func stop() {
        isRunning = false
        weatherTask?.cancel()
        weatherTask = nil
    }

    // MARK: - Event Loop

    private func eventLoop(for event: SpaceWeatherEvent) async {
        guard let range = intervals[event] else { return }

        // Initial random delay so events don't all fire at once
        let initialDelay = TimeInterval.random(in: 10...range.upperBound)
        try? await Task.sleep(for: .seconds(initialDelay))

        while !Task.isCancelled && isRunning {
            // Fire the event
            await MainActor.run { [weak self] in
                self?.lastEvent = event
                self?.onWeatherEvent?(event)
            }

            // Wait for next occurrence
            let nextInterval = TimeInterval.random(in: range)
            try? await Task.sleep(for: .seconds(nextInterval))
        }
    }

    // MARK: - Visual Effect Builders (SKAction sequences for the scene)

    // Note: solar flare, meteor shower, and nebula effects are implemented
    // directly in OfficeScene.handleWeatherEvent() with camera-attached overlays.
    // The action builders below are only used for rumble (camera shake).

    /// Station rumble: scene shake effect. Duration ~1-2s.
    static func stationRumbleAction() -> SKAction {
        let shakeCount = 8
        var actions: [SKAction] = []
        for _ in 0..<shakeCount {
            let dx = CGFloat.random(in: -3...3)
            let dy = CGFloat.random(in: -3...3)
            actions.append(SKAction.moveBy(x: dx, y: dy, duration: 0.05))
            actions.append(SKAction.moveBy(x: -dx, y: -dy, duration: 0.05))
        }
        return SKAction.sequence(actions)
    }
}
