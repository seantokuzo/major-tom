import Foundation

struct ApprovalRequest: Identifiable {
    let id: String
    let tool: String
    let description: String
    let details: [String: AnyCodableValue]?
    let receivedAt: Date

    init(from event: ApprovalRequestEvent) {
        self.id = event.requestId
        self.tool = event.tool
        self.description = event.description
        self.details = event.details
        self.receivedAt = Date()
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
    }

    /// The working directory for Bash tool requests.
    var workingDirectory: String? {
        return details?["working_directory"]?.stringValue
            ?? details?["workingDirectory"]?.stringValue
            ?? details?["cwd"]?.stringValue
    }

    /// The file path for file operation tools (Edit, Write, Read).
    var filePath: String? {
        return details?["file_path"]?.stringValue
            ?? details?["filePath"]?.stringValue
            ?? details?["path"]?.stringValue
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
