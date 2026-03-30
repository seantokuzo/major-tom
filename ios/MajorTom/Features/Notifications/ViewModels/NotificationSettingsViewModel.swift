import Foundation

// MARK: - Notification Config Model

struct NotificationConfig: Codable {
    var quietHours: QuietHoursConfig
    var priorityThreshold: String // "high" | "medium" | "low"
    var digest: DigestConfig

    struct QuietHoursConfig: Codable {
        var enabled: Bool
        var start: String // "HH:MM"
        var end: String   // "HH:MM"
    }

    struct DigestConfig: Codable {
        var enabled: Bool
        var intervalMinutes: Int
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class NotificationSettingsViewModel {
    var config: NotificationConfig?
    var isLoading = false
    var errorMessage: String?

    private let auth: AuthService

    init(auth: AuthService) {
        self.auth = auth
    }

    // MARK: - Priority Threshold Options

    static let thresholdOptions: [(label: String, value: String)] = [
        ("All", "low"),
        ("Medium+", "medium"),
        ("High Only", "high"),
    ]

    static let digestIntervalOptions: [Int] = [1, 2, 5, 10, 15]

    // MARK: - Time Helpers

    var quietHoursStart: Date {
        get { parseTime(config?.quietHours.start ?? "22:00") }
        set { config?.quietHours.start = formatTime(newValue); saveDebounced() }
    }

    var quietHoursEnd: Date {
        get { parseTime(config?.quietHours.end ?? "07:00") }
        set { config?.quietHours.end = formatTime(newValue); saveDebounced() }
    }

    // MARK: - API Calls

    func loadConfig() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = makeURL("/api/config/notifications") else {
            errorMessage = "Invalid server URL"
            return
        }

        var request = URLRequest(url: url)
        addAuthCookie(to: &request)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                errorMessage = "Failed to load settings"
                return
            }
            config = try JSONDecoder().decode(NotificationConfig.self, from: data)
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
    }

    func saveConfig() async {
        guard let config else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = makeURL("/api/config/notifications") else {
            errorMessage = "Invalid server URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthCookie(to: &request)

        do {
            request.httpBody = try JSONEncoder().encode(config)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                errorMessage = "Failed to save settings"
                return
            }
            self.config = try JSONDecoder().decode(NotificationConfig.self, from: data)
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    // MARK: - Debounced Save

    private var saveTask: Task<Void, Never>?

    func saveDebounced() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await saveConfig()
        }
    }

    // MARK: - Helpers

    private func makeURL(_ path: String) -> URL? {
        let serverURL = auth.serverURL
        let scheme = serverURL.contains("://") ? "" : "http://"
        return URL(string: "\(scheme)\(serverURL)\(path)")
    }

    private func addAuthCookie(to request: inout URLRequest) {
        if let cookie = auth.sessionCookie {
            request.setValue("session=\(cookie)", forHTTPHeaderField: "Cookie")
        }
    }

    private func parseTime(_ time: String) -> Date {
        let components = time.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { return Date() }
        let calendar = Calendar.current
        return calendar.date(
            from: DateComponents(hour: components[0], minute: components[1])
        ) ?? Date()
    }

    private func formatTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }
}
