import Foundation

// MARK: - Sprite Messaging State
//
// Per-sprite state machine for the `/btw` modal flow (Wave 4).
//
//   .idle                         — fresh input; no pending message
//   .pending(messageId, question) — user sent; waiting for response
//   .ready(messageId, question,   — response received; "Cool Beans" dismisses
//            response, wasDropped)
//
// Transitions:
//   idle + send   → pending
//   pending + `sprite.response(delivered)` → ready
//   pending + `sprite.response(dropped)`   → ready (synthetic text)
//   ready + "Cool Beans"                    → idle
//
// Drafts are ephemeral per-sprite UI state (TextField @State in the view) and
// are discarded whenever the inspector is closed / re-targeted.

enum SpriteMessagingState: Equatable {
    case idle
    case pending(messageId: String, question: String)
    case ready(messageId: String, question: String, response: String, wasDropped: Bool)

    /// True while awaiting a response.
    var isPending: Bool {
        if case .pending = self { return true }
        return false
    }

    /// True when there's a response waiting for the user to read.
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// The question text currently being displayed (pending or ready state).
    var question: String? {
        switch self {
        case .idle: return nil
        case .pending(_, let q): return q
        case .ready(_, let q, _, _): return q
        }
    }

    /// The response text (only available in .ready).
    var response: String? {
        if case .ready(_, _, let r, _) = self { return r }
        return nil
    }

    /// Message ID for correlating with `sprite.response` (pending or ready).
    var messageId: String? {
        switch self {
        case .idle: return nil
        case .pending(let id, _): return id
        case .ready(let id, _, _, _): return id
        }
    }
}

// MARK: - Queued Sprite Message
//
// Buffered in OfficeViewModel when the relay is disconnected. Flushed in FIFO
// order once the connection comes back (scenario #5).

struct QueuedSpriteMessage: Identifiable, Equatable {
    let id: String           // messageId — matches the one kept in .pending state
    let sessionId: String
    let spriteHandle: String
    let subagentId: String
    let text: String
    let createdAt: Date
}
