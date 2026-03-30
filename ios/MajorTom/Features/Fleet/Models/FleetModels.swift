import Foundation

// MARK: - Fleet Data Models

struct FleetStatus {
    var totalWorkers: Int
    var totalSessions: Int
    var aggregateCost: Double
    var aggregateTokens: TokenCount
    var workers: [FleetWorker]
}

struct FleetWorker: Identifiable {
    let workerId: String
    let workingDir: String
    let dirName: String
    var sessionCount: Int
    var uptimeMs: Int
    var restartCount: Int
    var healthy: Bool
    var sessions: [FleetSession]

    var id: String { workerId }
}

struct FleetSession: Identifiable {
    let sessionId: String
    var status: String
    var totalCost: Double
    var turnCount: Int
    var inputTokens: Int
    var outputTokens: Int

    var id: String { sessionId }
}

struct TokenCount {
    var input: Int
    var output: Int
}

// MARK: - Conversion from wire types

extension FleetStatus {
    init(from event: FleetStatusResponseEvent) {
        self.totalWorkers = event.totalWorkers
        self.totalSessions = event.totalSessions
        self.aggregateCost = event.aggregateCost
        self.aggregateTokens = TokenCount(
            input: event.aggregateTokens.input,
            output: event.aggregateTokens.output
        )
        self.workers = event.workers.map { FleetWorker(from: $0) }
    }
}

extension FleetWorker {
    init(from info: FleetWorkerInfo) {
        self.workerId = info.workerId
        self.workingDir = info.workingDir
        self.dirName = info.dirName
        self.sessionCount = info.sessionCount
        self.uptimeMs = info.uptimeMs
        self.restartCount = info.restartCount
        self.healthy = info.healthy
        self.sessions = info.sessions.map { FleetSession(from: $0) }
    }
}

extension FleetSession {
    init(from info: FleetSessionInfo) {
        self.sessionId = info.sessionId
        self.status = info.status
        self.totalCost = info.totalCost
        self.turnCount = info.turnCount
        self.inputTokens = info.inputTokens
        self.outputTokens = info.outputTokens
    }
}
