import Foundation

/// Checks GitHub releases API for new versions of Ground Control.
///
/// Polls on launch and periodically (every 6 hours). Publishes the latest
/// release tag so the UI can show a non-intrusive "update available" banner.
/// Never blocks anything — purely informational.
@Observable
final class UpdateChecker {
    /// Latest available version from GitHub (e.g. "0.2.0"), or nil if up-to-date / unknown.
    private(set) var latestVersion: String?

    /// URL of the latest release page, for the user to open in a browser.
    private(set) var releaseURL: URL?

    /// Whether an update is available (latestVersion > currentVersion).
    private(set) var updateAvailable = false

    /// Last error from the check (cleared on success).
    private(set) var lastError: String?

    /// When we last checked.
    private(set) var lastChecked: Date?

    /// Periodic check interval (6 hours).
    private let checkInterval: TimeInterval = 6 * 60 * 60

    /// Active periodic check task.
    private var periodicTask: Task<Void, Never>?

    private let session: URLSession

    // MARK: - Constants

    private static let owner = "seantokuzo"
    private static let repo = "major-tom"

    /// Current app version from the bundle (falls back to Info.plist value).
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - Init

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }

    // MARK: - Lifecycle

    /// Start periodic checking. Safe to call multiple times.
    func startChecking() {
        stopChecking()
        periodicTask = Task { [weak self] in
            guard let self else { return }
            // Check immediately on start
            await self.check()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.checkInterval))
                guard !Task.isCancelled else { break }
                await self.check()
            }
        }
    }

    /// Stop periodic checking.
    func stopChecking() {
        periodicTask?.cancel()
        periodicTask = nil
    }

    // MARK: - Check

    /// Perform a single update check against the GitHub releases API.
    @MainActor
    func check() async {
        let urlString = "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        // Identify ourselves to avoid aggressive rate limiting
        request.setValue("GroundControl/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = "Invalid response"
                return
            }

            // 404 = no releases yet, 403 = rate limited — both non-fatal
            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 404 {
                    // No releases published yet — nothing to do
                    lastError = nil
                    updateAvailable = false
                } else {
                    lastError = "GitHub API returned \(httpResponse.statusCode)"
                }
                lastChecked = Date()
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remoteVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

            latestVersion = remoteVersion
            releaseURL = URL(string: release.htmlURL)
            updateAvailable = isNewer(remote: remoteVersion, local: Self.currentVersion)
            lastError = nil
            lastChecked = Date()
        } catch is CancellationError {
            // Task cancelled — don't update state
        } catch {
            lastError = error.localizedDescription
            lastChecked = Date()
        }
    }

    // MARK: - Version Comparison

    /// Simple semver comparison: returns true if `remote` > `local`.
    private func isNewer(remote: String, local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, localParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}

// MARK: - GitHub API Model

/// Minimal model for GitHub Releases API response.
private struct GitHubRelease: Codable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
