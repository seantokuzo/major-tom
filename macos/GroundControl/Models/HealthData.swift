import Foundation

/// Parsed response from the relay's `/api/admin/status` endpoint.
///
/// Used by `RelayClient` to feed the Dashboard view with live server metrics.
/// All properties are `Codable` for direct JSON decoding from the relay.
struct HealthData: Codable, Equatable, Sendable {
    let status: String
    let uptime: Double
    let clients: [ConnectedClient]
    let sessions: [ActiveSession]
    let memory: MemoryUsage
    let tmuxWindowCount: Int

    /// Fallback for when the relay is unreachable.
    static let offline = HealthData(
        status: "offline",
        uptime: 0,
        clients: [],
        sessions: [],
        memory: MemoryUsage(rss: 0, heapUsed: 0, heapTotal: 0, external: 0),
        tmuxWindowCount: 0
    )
}

// MARK: - Nested Types

struct ConnectedClient: Codable, Equatable, Identifiable, Sendable {
    let ip: String
    let userAgent: String
    let connectedAt: String

    var id: String { "\(ip)-\(connectedAt)" }

    /// Human-readable connection duration relative to now.
    var connectionDuration: String {
        guard let date = ISO8601DateFormatter().date(from: connectedAt) else {
            return "unknown"
        }
        let interval = Date.now.timeIntervalSince(date)
        return Self.formatDuration(interval)
    }

    /// Short device description parsed from user-agent.
    var deviceSummary: String {
        if userAgent.contains("iPhone") { return "iPhone" }
        if userAgent.contains("iPad") { return "iPad" }
        if userAgent.contains("Macintosh") || userAgent.contains("Mac OS") { return "Mac" }
        if userAgent.contains("Android") { return "Android" }
        if userAgent.contains("Windows") { return "Windows" }
        if userAgent.contains("Linux") { return "Linux" }
        if userAgent == "unknown" { return "Unknown Device" }
        // Truncate long UAs
        let trimmed = String(userAgent.prefix(40))
        return trimmed.count < userAgent.count ? "\(trimmed)..." : trimmed
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds) / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours < 24 {
            return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
        }
        let days = hours / 24
        return "\(days)d \(hours % 24)h"
    }
}

struct ActiveSession: Codable, Equatable, Identifiable, Sendable {
    let sessionId: String
    let workDir: String
    let status: String
    let startedAt: String

    var id: String { sessionId }

    /// Short display name from the working directory.
    var workDirName: String {
        (workDir as NSString).lastPathComponent
    }
}

struct MemoryUsage: Codable, Equatable, Sendable {
    let rss: Int
    let heapUsed: Int
    let heapTotal: Int
    let external: Int

    /// RSS formatted as human-readable string (e.g. "142 MB").
    var rssFormatted: String { Self.formatBytes(rss) }
    /// Heap used formatted.
    var heapUsedFormatted: String { Self.formatBytes(heapUsed) }
    /// Heap total formatted.
    var heapTotalFormatted: String { Self.formatBytes(heapTotal) }
    /// Heap utilization as a fraction (0..1).
    var heapUtilization: Double {
        guard heapTotal > 0 else { return 0 }
        return Double(heapUsed) / Double(heapTotal)
    }

    private static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024
        return String(format: "%.2f GB", gb)
    }
}
