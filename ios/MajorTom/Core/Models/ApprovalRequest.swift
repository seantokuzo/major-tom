import Foundation
import SwiftUI

struct ApprovalRequest: Identifiable {
    let id: String
    let tool: String
    let description: String
    let details: [String: AnyCodableValue]?
    let receivedAt: Date
    /// Server-provided priority scoring (may be nil for backwards compatibility)
    let priority: ApprovalPriority?

    init(from event: ApprovalRequestEvent) {
        self.id = event.requestId
        self.tool = event.tool
        self.description = event.description
        self.details = event.details
        self.receivedAt = Date()
        self.priority = event.priority
    }

    // MARK: - Priority Level

    /// Server priority level as a typed enum, falling back to client-side danger level
    var priorityLevel: PriorityLevel {
        if let level = priority?.level {
            switch level {
            case "high": return .high
            case "medium": return .medium
            case "low": return .low
            default: return .medium
            }
        }
        // Fallback: map danger level to priority level
        switch dangerLevel {
        case .high: return .high
        case .medium: return .medium
        case .normal: return .low
        }
    }

    enum PriorityLevel: String, CaseIterable {
        case high
        case medium
        case low

        var color: Color {
            switch self {
            case .high: MajorTomTheme.Colors.danger
            case .medium: MajorTomTheme.Colors.warning
            case .low: MajorTomTheme.Colors.allow
            }
        }

        var label: String {
            switch self {
            case .high: "High"
            case .medium: "Medium"
            case .low: "Low"
            }
        }
    }

    // MARK: - Danger Level

    var dangerLevel: DangerLevel {
        DangerScoring.score(tool: tool, description: description, details: details)
    }

    // MARK: - Tool-specific Detail Extraction

    /// The command string for Bash tool requests.
    var command: String? {
        guard tool == "Bash" else { return nil }
        return details?["command"]?.stringValue
            ?? details?["cmd"]?.stringValue
            ?? toolInput?["command"]?.stringValue
    }

    /// Nested tool_input dictionary from relay approval messages.
    private var toolInput: [String: AnyCodableValue]? {
        details?["tool_input"]?.dictionaryValue
    }

    /// The working directory for Bash tool requests.
    var workingDirectory: String? {
        if let v = details?["working_directory"]?.stringValue { return v }
        if let v = details?["workingDirectory"]?.stringValue { return v }
        if let v = details?["cwd"]?.stringValue { return v }
        return toolInput?["working_directory"]?.stringValue
    }

    /// The file path for file operation tools (Edit, Write, Read).
    var filePath: String? {
        if let v = details?["file_path"]?.stringValue { return v }
        if let v = details?["filePath"]?.stringValue { return v }
        if let v = details?["path"]?.stringValue { return v }
        if let v = toolInput?["file_path"]?.stringValue { return v }
        return toolInput?["path"]?.stringValue
    }

    /// The diff content for Edit tool requests (old_string -> new_string).
    var diffContent: String? {
        guard tool == "Edit" else { return nil }
        let oldStr = details?["old_string"]?.stringValue
            ?? details?["oldString"]?.stringValue
        let newStr = details?["new_string"]?.stringValue
            ?? details?["newString"]?.stringValue

        guard let old = oldStr, let new = newStr else { return nil }

        var diff = ""
        for line in old.components(separatedBy: "\n") {
            diff += "- \(line)\n"
        }
        for line in new.components(separatedBy: "\n") {
            diff += "+ \(line)\n"
        }
        return diff
    }

    /// The content preview for Write tool requests (first 10 lines).
    var contentPreview: String? {
        guard tool == "Write" else { return nil }
        guard let content = details?["content"]?.stringValue else { return nil }
        let lines = content.components(separatedBy: "\n")
        let preview = lines.prefix(10).joined(separator: "\n")
        if lines.count > 10 {
            return preview + "\n... (\(lines.count - 10) more lines)"
        }
        return preview
    }

    /// The search pattern for Glob/Grep tool requests.
    var searchPattern: String? {
        return details?["pattern"]?.stringValue
            ?? details?["glob"]?.stringValue
    }

    /// The search path for Glob/Grep tool requests.
    var searchPath: String? {
        return details?["path"]?.stringValue
    }
}
