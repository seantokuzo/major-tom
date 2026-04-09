import Foundation
import SwiftUI

/// A single parsed log entry from the relay's pino JSON output.
struct LogEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let message: String
    let rawJSON: String
    let extra: [String: Any]

    /// Pino log levels mapped to display metadata.
    enum LogLevel: Int, CaseIterable, Comparable {
        case trace = 10
        case debug = 20
        case info = 30
        case warn = 40
        case error = 50
        case fatal = 60

        var displayName: String {
            switch self {
            case .trace: "TRACE"
            case .debug: "DEBUG"
            case .info: "INFO"
            case .warn: "WARN"
            case .error: "ERROR"
            case .fatal: "FATAL"
            }
        }

        var color: Color {
            switch self {
            case .trace: .gray
            case .debug: .blue
            case .info: .green
            case .warn: .yellow
            case .error: .red
            case .fatal: .purple
            }
        }

        var sfSymbol: String {
            switch self {
            case .trace: "ant"
            case .debug: "ladybug"
            case .info: "info.circle"
            case .warn: "exclamationmark.triangle"
            case .error: "xmark.circle"
            case .fatal: "bolt.circle"
            }
        }

        static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        /// Attempt to parse a pino numeric level to a LogLevel.
        /// Falls back to nearest known level for non-standard values.
        init(pinoLevel: Int) {
            switch pinoLevel {
            case ...10: self = .trace
            case 11...20: self = .debug
            case 21...30: self = .info
            case 31...40: self = .warn
            case 41...50: self = .error
            default: self = .fatal
            }
        }
    }

    // MARK: - Standard pino fields to strip from "extra"

    private static let standardFields: Set<String> = [
        "level", "time", "pid", "hostname", "name", "msg", "v",
    ]

    // MARK: - Parsing

    /// Parse a pino JSON line into a LogEntry.
    /// Returns nil only if the line is completely empty.
    static func parse(line: String) -> LogEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // Non-JSON line — treat as INFO with raw text
            return LogEntry(
                id: UUID(),
                timestamp: Date(),
                level: .info,
                message: trimmed,
                rawJSON: trimmed,
                extra: [:]
            )
        }

        // Parse pino fields
        let pinoLevel = json["level"] as? Int ?? 30
        let level = LogLevel(pinoLevel: pinoLevel)

        let message = json["msg"] as? String ?? json["message"] as? String ?? ""

        // Parse timestamp — pino uses epoch millis in "time"
        let timestamp: Date
        if let timeMs = json["time"] as? Double {
            timestamp = Date(timeIntervalSince1970: timeMs / 1000.0)
        } else if let timeMs = json["time"] as? Int {
            timestamp = Date(timeIntervalSince1970: Double(timeMs) / 1000.0)
        } else {
            timestamp = Date()
        }

        // Collect extra fields (everything beyond standard pino fields)
        var extra: [String: Any] = [:]
        for (key, value) in json where !standardFields.contains(key) {
            extra[key] = value
        }

        return LogEntry(
            id: UUID(),
            timestamp: timestamp,
            level: level,
            message: message,
            rawJSON: trimmed,
            extra: extra
        )
    }
}
