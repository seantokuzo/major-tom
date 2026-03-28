import SwiftUI

// MARK: - Danger Level

enum DangerLevel: String, CaseIterable {
    case high
    case medium
    case normal

    var color: Color {
        switch self {
        case .high: MajorTomTheme.Colors.danger
        case .medium: MajorTomTheme.Colors.warning
        case .normal: MajorTomTheme.Colors.allow
        }
    }

    var icon: String {
        switch self {
        case .high: "exclamationmark.triangle.fill"
        case .medium: "exclamationmark.circle.fill"
        case .normal: "checkmark.shield.fill"
        }
    }

    var label: String {
        switch self {
        case .high: "High Risk"
        case .medium: "Medium Risk"
        case .normal: "Safe"
        }
    }
}

// MARK: - Danger Scoring Service

enum DangerScoring {

    // Bash commands that are high danger
    private static let highDangerBashPatterns: [String] = [
        "rm ", "rm\t", "rmdir",
        "kill ", "kill\t", "killall",
        "sudo ",
        "chmod ", "chown ",
        "git push --force", "git push -f ",
        "mkfs", "dd if=",
        ":(){ :|:& };:", // fork bomb
        "> /dev/", "mv / ",
        "curl | sh", "curl | bash", "wget | sh", "wget | bash",
    ]

    // Bash commands that are medium danger
    private static let mediumDangerBashPatterns: [String] = [
        "npm install", "npm i ",
        "pip install", "pip3 install",
        "brew install",
        "cargo install",
        "gem install",
        "apt install", "apt-get install",
        "git reset", "git checkout --",
        "git clean",
        "docker ", "podman ",
    ]

    // Sensitive file paths for Write operations
    private static let sensitivePaths: [String] = [
        ".env", ".env.", "credentials",
        ".ssh/", ".gnupg/", ".aws/",
        "/etc/", "/usr/", "/bin/", "/sbin/",
        ".gitconfig", ".bashrc", ".zshrc", ".profile",
        "package.json", "Podfile", "Gemfile",
        "Cargo.toml", "go.mod",
    ]

    // Config file patterns for Edit operations
    private static let configPatterns: [String] = [
        ".json", ".yml", ".yaml", ".toml",
        ".env", ".config", ".rc",
        "Makefile", "Dockerfile",
        ".lock",
    ]

    /// Score the danger level of an approval request.
    static func score(tool: String, description: String, details: [String: AnyCodableValue]?) -> DangerLevel {
        let toolLower = tool.lowercased()
        let descLower = description.lowercased()

        // Extract command string from details, tool_input, or description
        let toolInput = details?["tool_input"]?.dictionaryValue
        let command = details?["command"]?.stringValue
            ?? toolInput?["command"]?.stringValue
            ?? description

        switch toolLower {
        case "bash":
            return scoreBash(command: command, descLower: descLower)

        case "write":
            return scoreWrite(details: details, descLower: descLower)

        case "edit":
            return scoreEdit(details: details, descLower: descLower)

        case "read", "glob", "grep":
            return .normal

        default:
            // Unknown tools get medium by default
            return .medium
        }
    }

    // MARK: - Tool-specific Scoring

    private static func scoreBash(command: String, descLower: String) -> DangerLevel {
        let cmdLower = command.lowercased()
        let checkString = cmdLower + " " + descLower

        // Check high danger patterns
        for pattern in highDangerBashPatterns {
            if checkString.contains(pattern) {
                return .high
            }
        }

        // Check medium danger patterns
        for pattern in mediumDangerBashPatterns {
            if checkString.contains(pattern) {
                return .medium
            }
        }

        return .normal
    }

    private static func scoreWrite(details: [String: AnyCodableValue]?, descLower: String) -> DangerLevel {
        let toolInput = details?["tool_input"]?.dictionaryValue
        let filePath = details?["file_path"]?.stringValue
            ?? details?["filePath"]?.stringValue
            ?? toolInput?["file_path"]?.stringValue

        let pathLower = (filePath ?? descLower).lowercased()

        // Check for sensitive paths
        for sensitive in sensitivePaths {
            if pathLower.contains(sensitive) {
                return .high
            }
        }

        // All Write operations are at least medium risk
        return .medium
    }

    private static func scoreEdit(details: [String: AnyCodableValue]?, descLower: String) -> DangerLevel {
        let toolInput = details?["tool_input"]?.dictionaryValue
        let filePath = details?["file_path"]?.stringValue
            ?? details?["filePath"]?.stringValue
            ?? toolInput?["file_path"]?.stringValue
            ?? ""

        let pathLower = filePath.lowercased() + descLower

        // Check sensitive paths first (higher severity than config)
        for sensitive in sensitivePaths {
            if pathLower.contains(sensitive) {
                return .high
            }
        }

        // Check for config files
        for pattern in configPatterns {
            if pathLower.contains(pattern) {
                return .medium
            }
        }

        return .normal
    }
}
