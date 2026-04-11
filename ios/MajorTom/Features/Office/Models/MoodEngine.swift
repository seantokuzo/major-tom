import Foundation
import SpriteKit

// MARK: - Agent Mood

/// Mood states for agents — derived from session events, not set directly.
enum AgentMood: String, CaseIterable {
    case happy
    case neutral
    case focused
    case bored
    case frustrated
    case excited
}

// MARK: - Mood Inputs

/// Tracks per-agent event data used to derive current mood.
struct MoodInputs {
    /// Timestamp of last tool/work event
    var lastActivityTime: Date = Date()
    /// Number of consecutive tool errors or denials
    var consecutiveErrors: Int = 0
    /// Whether a task was just completed
    var justCompletedTask: Bool = false
    /// When justCompletedTask was set (for auto-decay)
    var completedAt: Date = .distantPast
    /// When agent started continuous work (nil if not working)
    var workStartTime: Date?
    /// Total errors since last task completion (resets on completion)
    var recentErrors: Int = 0
}

// MARK: - Mood Visuals

/// Visual parameters for sprite rendering based on mood.
struct MoodVisuals {
    let tintColor: SKColor
    let tintOpacity: CGFloat
    let pulse: Bool
    let pulseSpeed: CGFloat  // radians per second
}

extension AgentMood {

    /// Visual config for each mood state.
    var visuals: MoodVisuals {
        switch self {
        case .happy:
            return MoodVisuals(
                tintColor: SKColor(red: 1.0, green: 0.86, blue: 0.39, alpha: 1),
                tintOpacity: 0.12,
                pulse: false,
                pulseSpeed: 0
            )
        case .neutral:
            return MoodVisuals(
                tintColor: .clear,
                tintOpacity: 0,
                pulse: false,
                pulseSpeed: 0
            )
        case .focused:
            return MoodVisuals(
                tintColor: SKColor(red: 0.31, green: 0.55, blue: 1.0, alpha: 1),
                tintOpacity: 0.10,
                pulse: false,
                pulseSpeed: 0
            )
        case .bored:
            return MoodVisuals(
                tintColor: SKColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1),
                tintOpacity: 0.15,
                pulse: false,
                pulseSpeed: 0
            )
        case .frustrated:
            return MoodVisuals(
                tintColor: SKColor(red: 1.0, green: 0.24, blue: 0.24, alpha: 1),
                tintOpacity: 0.12,
                pulse: true,
                pulseSpeed: 3
            )
        case .excited:
            return MoodVisuals(
                tintColor: SKColor(red: 1.0, green: 0.78, blue: 0.2, alpha: 1),
                tintOpacity: 0.15,
                pulse: true,
                pulseSpeed: 5
            )
        }
    }
}

// MARK: - Mood Speech

extension AgentMood {

    /// Speech bubble quips per mood. Returns nil for moods with no special speech.
    var speechPool: [String]? {
        switch self {
        case .happy, .neutral:
            return nil
        case .focused:
            return ["..."]
        case .bored:
            return [
                "Anyone want coffee?",
                "Is it 5pm yet?",
                "*yawns*",
                "So bored...",
                "*stretches*",
                "Waiting for PR review...",
                "*stares into void*",
                "Maybe I should refactor something",
            ]
        case .frustrated:
            return [
                "This test is killing me",
                "WHY won't this compile",
                "UGHHHH",
                "Who wrote this code",
                "I need a break",
                "...seriously?",
                "FML",
                "Stack Overflow please save me",
            ]
        case .excited:
            return [
                "LET'S GOOO!",
                "Shipped it!",
                "PR approved!",
                "YESSS!",
                "We did it!",
                "Deploy time!",
                "Another one done!",
                "On a roll!",
            ]
        }
    }

    /// Pick a random speech quip, or nil if this mood doesn't speak.
    func pickSpeech() -> String? {
        guard let pool = speechPool, !pool.isEmpty else { return nil }
        return pool.randomElement()
    }

    /// The emote associated with this mood (if any).
    var emote: EmoteType? {
        switch self {
        case .happy:      return .heart
        case .neutral:    return nil
        case .focused:    return .thought
        case .bored:      return .zzz
        case .frustrated: return .wrench
        case .excited:    return .exclamation
        }
    }
}

// MARK: - Mood Derivation

/// Derive the current mood from accumulated inputs.
/// Priority order: excited > frustrated > bored > focused > happy > neutral.
func deriveMood(from inputs: MoodInputs) -> AgentMood {
    let now = Date()
    let idleSeconds = now.timeIntervalSince(inputs.lastActivityTime)

    // Excited: just completed a task (decays after 30s)
    if inputs.justCompletedTask, now.timeIntervalSince(inputs.completedAt) < 30 {
        return .excited
    }

    // Frustrated: 2+ consecutive errors
    if inputs.consecutiveErrors >= 2 {
        return .frustrated
    }

    // Focused: working continuously for >2 minutes (prioritized over bored)
    if let workStart = inputs.workStartTime, now.timeIntervalSince(workStart) > 120 {
        return .focused
    }

    // Bored: idle for >3 minutes (skipped while workStartTime is non-nil)
    if inputs.workStartTime == nil, idleSeconds > 180 {
        return .bored
    }

    // Happy: no recent errors and active
    if inputs.recentErrors == 0, idleSeconds < 180 {
        return .happy
    }

    return .neutral
}

// MARK: - Mood Engine

/// Manages per-agent mood state. Updates every 30 seconds on a timer.
/// ViewModel feeds events (activity, error, completion, idle) into this engine;
/// OfficeScene reads moods for visual effects.
@Observable
final class MoodEngine {

    // MARK: - State

    /// Current mood per agent ID.
    private(set) var moods: [String: AgentMood] = [:]

    /// Derivation inputs per agent ID (not published — internal bookkeeping).
    private var inputs: [String: MoodInputs] = [:]

    /// 30-second update timer.
    private var updateTimer: Timer?

    // MARK: - Queries

    /// Get the current mood for an agent.
    func mood(for agentId: String) -> AgentMood {
        moods[agentId] ?? .neutral
    }

    // MARK: - Agent Lifecycle

    /// Register a new agent with default (neutral) mood.
    func addAgent(_ agentId: String) {
        inputs[agentId] = MoodInputs()
        moods[agentId] = .neutral
    }

    /// Remove an agent.
    func removeAgent(_ agentId: String) {
        inputs.removeValue(forKey: agentId)
        moods.removeValue(forKey: agentId)
    }

    // MARK: - Event Recording

    /// Record a work activity (tool call, code generation, etc.).
    func recordActivity(_ agentId: String) {
        guard var input = inputs[agentId] else { return }
        input.lastActivityTime = Date()
        if input.workStartTime == nil {
            input.workStartTime = Date()
        }
        input.consecutiveErrors = 0
        inputs[agentId] = input
    }

    /// Record a tool error or denial.
    func recordError(_ agentId: String) {
        guard var input = inputs[agentId] else { return }
        input.consecutiveErrors += 1
        input.recentErrors += 1
        input.lastActivityTime = Date()
        inputs[agentId] = input
    }

    /// Record task completion.
    func recordCompletion(_ agentId: String) {
        guard var input = inputs[agentId] else { return }
        input.justCompletedTask = true
        input.completedAt = Date()
        input.consecutiveErrors = 0
        input.recentErrors = 0
        input.workStartTime = nil
        inputs[agentId] = input
    }

    /// Record agent going idle.
    func recordIdle(_ agentId: String) {
        guard var input = inputs[agentId] else { return }
        input.workStartTime = nil
        inputs[agentId] = input
    }

    // MARK: - Lifecycle

    /// Start periodic mood updates (every 30 seconds).
    func start() {
        guard updateTimer == nil else { return }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.updateAllMoods()
        }
    }

    /// Stop periodic updates.
    func stop() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    /// Recalculate all agent moods.
    func updateAllMoods() {
        for (agentId, var input) in inputs {
            // Decay justCompletedTask after 30s
            if input.justCompletedTask, Date().timeIntervalSince(input.completedAt) > 30 {
                input.justCompletedTask = false
                inputs[agentId] = input
            }
            moods[agentId] = deriveMood(from: input)
        }
    }

    /// Reset all state.
    func reset() {
        moods.removeAll()
        inputs.removeAll()
    }
}
