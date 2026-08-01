import Foundation

/// Feature flags for in-development phases of the app.
///
/// Stored in `UserDefaults` so flips survive app restarts without a rebuild.
/// Flags default to `false` — each keyed-off flag represents an in-flight
/// phase that is not yet ready to light up for real users. When a phase
/// ships in full, the flag is removed alongside the old code path.
///
/// This enum is intentionally kept (even when empty) so future flags have
/// a landing pad without re-introducing a file-level dance.
enum FeatureFlags {
    // No active flags.
}

// TEMPORARY — deliberate compile error to prove the CI iOS gate can go RED.
// This commit is reverted immediately after the red run is observed.
// See PR #202.
enum RedPathProof {
    static let deliberatelyBroken: Int = "this is not an Int"
}
