import Foundation

// MARK: - Analytics Response Models

struct AnalyticsTimeSeriesEntry: Codable, Identifiable {
    let period: String
    let cost: Double
    let inputTokens: Int
    let outputTokens: Int
    let cacheTokens: Int
    let turnCount: Int

    var id: String { period }
}

struct AnalyticsBySession: Codable, Identifiable {
    let sessionId: String
    let workingDir: String
    let totalCost: Double
    let totalTokens: Int
    let turnCount: Int

    var id: String { sessionId }
}

struct AnalyticsByModel: Codable, Identifiable {
    let model: String
    let cost: Double
    let tokens: Int
    let turnCount: Int

    var id: String { model }
}

struct AnalyticsByTool: Codable, Identifiable {
    let tool: String
    let count: Int
    let avgDurationMs: Int

    var id: String { tool }
}

struct AnalyticsTotals: Codable {
    let cost: Double
    let inputTokens: Int
    let outputTokens: Int
    let turnCount: Int
    let sessionCount: Int
}

struct AnalyticsResponse: Codable {
    let timeSeries: [AnalyticsTimeSeriesEntry]
    let bySession: [AnalyticsBySession]
    let byModel: [AnalyticsByModel]
    let byTool: [AnalyticsByTool]
    let totals: AnalyticsTotals
}

// MARK: - Time Range

enum AnalyticsTimeRange: String, CaseIterable, Identifiable {
    case day = "24h"
    case week = "7d"
    case month = "30d"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: "24h"
        case .week: "7 Days"
        case .month: "30 Days"
        }
    }

    var fromDate: Date {
        let now = Date()
        switch self {
        case .day: return now.addingTimeInterval(-24 * 60 * 60)
        case .week: return now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .month: return now.addingTimeInterval(-30 * 24 * 60 * 60)
        }
    }

    var groupBy: String {
        switch self {
        case .day: "hour"
        case .week: "day"
        case .month: "day"
        }
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class AnalyticsViewModel {
    var data: AnalyticsResponse?
    var isLoading = false
    var error: String?
    var timeRange: AnalyticsTimeRange = .day

    private let auth: AuthService

    init(auth: AuthService) {
        self.auth = auth
    }

    var totalCost: Double {
        data?.totals.cost ?? 0
    }

    func fetchAnalytics() async {
        isLoading = true
        error = nil

        let fromISO = ISO8601DateFormatter().string(from: timeRange.fromDate)
        let toISO = ISO8601DateFormatter().string(from: Date())
        let groupBy = timeRange.groupBy

        let scheme = auth.serverURL.contains("://") ? "" : "http://"
        let baseURL = "\(scheme)\(auth.serverURL)"
        let urlString = "\(baseURL)/api/analytics?from=\(fromISO)&to=\(toISO)&groupBy=\(groupBy)"

        guard let url = URL(string: urlString) else {
            error = "Invalid URL"
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let cookie = auth.sessionCookie {
            request.setValue("mt-session=\(cookie)", forHTTPHeaderField: "Cookie")
        }

        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                error = "Invalid response"
                isLoading = false
                return
            }

            if httpResponse.statusCode == 200 {
                let decoder = JSONDecoder()
                data = try decoder.decode(AnalyticsResponse.self, from: responseData)
            } else if httpResponse.statusCode == 401 {
                error = "Authentication required"
            } else {
                error = "HTTP \(httpResponse.statusCode)"
            }
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func setTimeRange(_ range: AnalyticsTimeRange) {
        timeRange = range
        Task {
            await fetchAnalytics()
        }
    }
}
