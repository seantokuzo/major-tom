import Foundation

// MARK: - Crew Roster

/// Manages which human characters are actively rendered on screen.
/// All dogs are always shown. Humans are limited to `maxIdleHumans` (default 6).
/// Users can set a preferred order — preferred characters always fill first,
/// remaining slots are randomly filled from the unpreferred pool.
///
/// Overflow: when a workflow spawns more subagents than there are available idle
/// sprites, the system pulls from the unrendered human pool. Those overflow
/// sprites work until their task completes, then disappear (not returned to idle).
@Observable
@MainActor
final class CrewRoster {

    // MARK: - Persisted State

    /// User's preferred humans in priority order.
    /// First N fill idle slots; extras become the overflow priority pool.
    private(set) var preferredOrder: [CharacterType] {
        didSet { save() }
    }

    /// The current randomization seed — changes on shuffle.
    /// Used to deterministically pick random crew from the non-preferred pool.
    private var shuffleSeed: UInt64 {
        didSet { save() }
    }

    // MARK: - Init

    init() {
        // Load persisted state
        let defaults = UserDefaults.standard

        if let savedNames = defaults.stringArray(forKey: Self.preferredKey) {
            self.preferredOrder = savedNames.compactMap { CharacterType(rawValue: $0) }
        } else {
            self.preferredOrder = []
        }

        self.shuffleSeed = UInt64(UInt(bitPattern: defaults.integer(forKey: Self.seedKey)))
        if shuffleSeed == 0 {
            shuffleSeed = UInt64.random(in: 1...UInt64.max)
        }
    }

    // MARK: - Public API

    /// Get the active human crew for idle display.
    /// Returns up to `count` humans: preferred first, then random fill.
    func activeHumans(count: Int) -> [CharacterType] {
        let allHumans = CharacterType.allCases.filter { !$0.isDog }

        // Start with preferred humans (up to count)
        var active = Array(preferredOrder.prefix(count))

        // Fill remaining slots with random non-preferred humans
        let remaining = count - active.count
        if remaining > 0 {
            let unpreferred = allHumans.filter { !preferredOrder.contains($0) }
            let shuffled = seededShuffle(unpreferred)
            active.append(contentsOf: shuffled.prefix(remaining))
        }

        return active
    }

    /// Check if a character is part of the active crew (would be rendered when idle).
    func isActiveCrew(_ character: CharacterType, maxCount: Int) -> Bool {
        activeHumans(count: maxCount).contains(character)
    }

    /// Get the next overflow human — for when >maxIdleHumans subagents spawn.
    /// Returns humans not in the active crew, in preference order then random.
    func overflowHuman(excluding claimed: Set<CharacterType>, maxIdleCount: Int) -> CharacterType? {
        let active = Set(activeHumans(count: maxIdleCount))
        let allHumans = CharacterType.allCases.filter { !$0.isDog }

        // First try preferred overflow (characters 7+ in preference list)
        let preferredOverflow = preferredOrder.dropFirst(maxIdleCount)
        for char in preferredOverflow where !claimed.contains(char) && !active.contains(char) {
            return char
        }

        // Then random from the remaining pool
        let pool = allHumans.filter { !claimed.contains($0) && !active.contains($0) && !preferredOrder.contains($0) }
        return pool.randomElement()
    }

    /// Re-randomize the non-preferred crew selection.
    func shuffle() {
        shuffleSeed = UInt64.random(in: 1...UInt64.max)
    }

    /// Set the user's preferred crew order.
    func setPreferredOrder(_ order: [CharacterType]) {
        preferredOrder = order.filter { !$0.isDog } // Dogs are always shown, not selectable
    }

    /// Clear all preferences — fully random selection.
    func clearPreferences() {
        preferredOrder = []
    }

    // MARK: - Private

    private static let preferredKey = "crewRoster.preferredOrder"
    private static let seedKey = "crewRoster.shuffleSeed"

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(preferredOrder.map(\.rawValue), forKey: Self.preferredKey)
        defaults.set(Int(bitPattern: UInt(shuffleSeed)), forKey: Self.seedKey)
    }

    /// Deterministic shuffle using the stored seed — same seed = same crew until shuffled.
    private func seededShuffle(_ array: [CharacterType]) -> [CharacterType] {
        guard !array.isEmpty else { return [] }
        var rng = SeededRNG(seed: shuffleSeed)
        var result = array
        for i in stride(from: result.count - 1, through: 1, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            result.swapAt(i, j)
        }
        return result
    }
}

// MARK: - Seeded RNG

/// Simple xorshift64 PRNG for deterministic crew shuffling.
private struct SeededRNG {
    var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
