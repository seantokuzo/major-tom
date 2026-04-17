import Foundation

// MARK: - Tool Humanizer (Wave 5)

/// Maps raw Claude Code tool names to short, humanized labels shown in the
/// per-sprite tool-event speech bubble.
///
/// Input-awareness is kept intentionally minimal — the bubble is a terse status
/// ("reading files…") not a preview of arguments. If the caller wants to
/// specialize a label (e.g. show the file name on a Read), they can extend this
/// enum in the future; for Wave 5 we keep labels fixed per tool.
enum ToolHumanizer {

    /// Return a short humanized label for a tool call.
    /// Case-insensitive on the tool name.
    static func label(for tool: String, input: [String: AnyCodableValue]? = nil) -> String {
        _ = input  // Reserved for future input-aware labels (file names, commands, etc.)
        let normalizedTool = tool.lowercased()
        switch normalizedTool {
        case "read":          return "reading files…"
        case "write":         return "writing code…"
        case "edit":          return "editing code…"
        case "bash":          return "running commands…"
        case "grep":          return "searching…"
        case "glob":          return "finding files…"
        case "task":          return "spawning helper…"
        case "websearch":     return "searching the web…"
        case "webfetch":      return "fetching a page…"
        case "todowrite":     return "updating todos…"
        case "notebookedit":  return "editing notebook…"
        default:              return "working…"
        }
    }
}
