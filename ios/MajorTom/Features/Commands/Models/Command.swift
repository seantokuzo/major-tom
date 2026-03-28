import Foundation

struct SlashCommand: Identifiable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let action: CommandAction

    init(name: String, icon: String, description: String, action: CommandAction) {
        self.id = name
        self.name = name
        self.icon = icon
        self.description = description
        self.action = action
    }
}

enum CommandAction {
    case newSession
    case clearChat
    case switchModel
    case compactMode
    case help
    case showCost
    case cancel
    case templates
    case history
    case devices
}

// MARK: - All Commands

extension SlashCommand {
    static let allCommands: [SlashCommand] = [
        SlashCommand(
            name: "new",
            icon: "plus.circle",
            description: "Start a new session",
            action: .newSession
        ),
        SlashCommand(
            name: "clear",
            icon: "trash",
            description: "Clear chat messages",
            action: .clearChat
        ),
        SlashCommand(
            name: "model",
            icon: "cpu",
            description: "Switch Claude model",
            action: .switchModel
        ),
        SlashCommand(
            name: "compact",
            icon: "rectangle.compress.vertical",
            description: "Toggle compact mode",
            action: .compactMode
        ),
        SlashCommand(
            name: "help",
            icon: "questionmark.circle",
            description: "Show available commands",
            action: .help
        ),
        SlashCommand(
            name: "cost",
            icon: "dollarsign.circle",
            description: "Show session cost",
            action: .showCost
        ),
        SlashCommand(
            name: "cancel",
            icon: "xmark.octagon",
            description: "Cancel current operation",
            action: .cancel
        ),
        SlashCommand(
            name: "templates",
            icon: "doc.text",
            description: "Open prompt templates",
            action: .templates
        ),
        SlashCommand(
            name: "history",
            icon: "clock.arrow.circlepath",
            description: "Open prompt history",
            action: .history
        ),
        SlashCommand(
            name: "devices",
            icon: "desktopcomputer",
            description: "Show connected devices",
            action: .devices
        ),
    ]

    static func search(_ query: String) -> [SlashCommand] {
        guard !query.isEmpty else { return allCommands }

        let lowered = query.lowercased()
        return allCommands.filter { command in
            fuzzyMatch(query: lowered, target: command.name.lowercased()) ||
            command.description.lowercased().contains(lowered)
        }
    }

    private static func fuzzyMatch(query: String, target: String) -> Bool {
        var queryIndex = query.startIndex
        var targetIndex = target.startIndex

        while queryIndex < query.endIndex && targetIndex < target.endIndex {
            if query[queryIndex] == target[targetIndex] {
                queryIndex = query.index(after: queryIndex)
            }
            targetIndex = target.index(after: targetIndex)
        }

        return queryIndex == query.endIndex
    }
}
