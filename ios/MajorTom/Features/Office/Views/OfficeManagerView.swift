import SwiftUI

// MARK: - Office Manager View

/// Root view for the Office tab. Displays a card grid of terminal tabs
/// hosting Claude sessions, letting users create/navigate per-tab Offices.
/// Uses NavigationStack to push into individual OfficeViews (keyed by tabId).
///
/// Tab-Keyed Offices (Wave 4) — the data source is `relay.tabRegistryStore`,
/// populated by `tab.list.response` + `tab.session.*` broadcasts from the
/// relay. Legacy `cli`/`vscode` SDK sessions are not surfaced here (they
/// continue to work via the synthetic-tabId fallback path inside
/// `OfficeSceneManager`, but aren't listed as tabs).
struct OfficeManagerView: View {
    var sceneManager: OfficeSceneManager
    var relay: RelayService

    @State private var navigationPath = NavigationPath()
    @State private var bannerTask: Task<Void, Never>?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            scrollContent
                .navigationTitle("Offices")
                .navigationBarTitleDisplayMode(.large)
                .background(MajorTomTheme.Colors.background)
                .navigationDestination(for: String.self) { tabId in
                    OfficeView(
                        sessionId: tabId,
                        sceneManager: sceneManager,
                        relay: relay
                    )
                }
                .task {
                    // Fetch the latest tab list when the Office tab becomes
                    // visible. Fixes the "sessionList never populated" bug
                    // the session-keyed Office Manager had — the old code
                    // relied on sessionList being pushed by the relay
                    // pre-connection, which didn't always happen.
                    try? await relay.requestTabList()
                }
        }
        .overlay(alignment: .top) {
            if let banner = sceneManager.pendingCrossSessionBanner {
                SpriteResponseBanner(
                    banner: banner,
                    onTap: { navigateToBannerSession(banner) },
                    onDismiss: { cancelBannerAutoHide() }
                )
                .padding(.horizontal, MajorTomTheme.Spacing.lg)
                .padding(.top, MajorTomTheme.Spacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: sceneManager.pendingCrossSessionBanner)
        .onChange(of: sceneManager.pendingCrossSessionBanner) { _, newBanner in
            rescheduleBannerAutoHide(for: newBanner)
        }
    }

    // MARK: - Banner handling (M2)

    private func navigateToBannerSession(_ banner: OfficeSceneManager.CrossSessionBanner) {
        cancelBannerAutoHide()
        // Banner still carries sessionId today — routed through the smart
        // lookup on OfficeSceneManager. Wave 4 commit #5 threads tabId
        // onto the banner so cross-session taps navigate by tabId.
        let target = banner.sessionId
        if sceneManager.viewModel(for: target) == nil
            || sceneManager.peekScene(for: target) == nil {
            sceneManager.createOffice(for: target)
        }
        navigationPath = NavigationPath()
        navigationPath.append(target)
    }

    private func rescheduleBannerAutoHide(for banner: OfficeSceneManager.CrossSessionBanner?) {
        bannerTask?.cancel()
        guard banner != nil else { return }
        bannerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            sceneManager.dismissCrossSessionBanner()
        }
    }

    private func cancelBannerAutoHide() {
        bannerTask?.cancel()
        bannerTask = nil
        sceneManager.dismissCrossSessionBanner()
    }

    // MARK: - Content

    @ViewBuilder
    private var scrollContent: some View {
        let activeIds = sceneManager.linkedSessionIds
        let allTabs = sortedTabs(relay.tabRegistryStore.tabs)
        let activeTabs = allTabs.filter { activeIds.contains($0.tabId) }
        let availableTabs = allTabs.filter {
            !activeIds.contains($0.tabId)
                && !$0.sessions.isEmpty
                && $0.status != "closed"
        }

        if allTabs.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MajorTomTheme.Spacing.lg) {
                    // Active offices — tabs the user has already materialized
                    if !activeTabs.isEmpty {
                        sectionHeader("Active Offices")
                        ForEach(activeTabs) { tab in
                            activeOfficeCard(tab: tab)
                        }
                    }

                    // Available tabs — have active claude sessions, not yet opened
                    if !availableTabs.isEmpty {
                        sectionHeader("Available Tabs")
                        ForEach(availableTabs) { tab in
                            availableTabCard(tab: tab)
                        }
                    }
                }
                .padding(.horizontal, MajorTomTheme.Spacing.lg)
                .padding(.top, MajorTomTheme.Spacing.sm)
                .padding(.bottom, MajorTomTheme.Spacing.xxl)
            }
        }
    }

    /// Sort tabs newest-first by `lastSeenAt`, falling back to `createdAt`
    /// when the relay hasn't populated timestamps yet.
    private func sortedTabs(_ tabs: [String: TabMeta]) -> [TabMeta] {
        tabs.values.sorted { lhs, rhs in
            let lhsKey = lhs.lastSeenAt.isEmpty ? lhs.createdAt : lhs.lastSeenAt
            let rhsKey = rhs.lastSeenAt.isEmpty ? rhs.createdAt : rhs.lastSeenAt
            return lhsKey > rhsKey
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: MajorTomTheme.Spacing.lg) {
            Spacer()
            Image(systemName: "apple.terminal")
                .font(.system(size: 48))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            Text("No Claude Tabs Yet")
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            Text("Run `claude` in a terminal tab to spin up an office.")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, MajorTomTheme.Spacing.xxl)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(.caption, design: .monospaced, weight: .bold))
            .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            .padding(.top, MajorTomTheme.Spacing.sm)
    }

    // MARK: - Active Office Card

    private func activeOfficeCard(tab: TabMeta) -> some View {
        let vm = sceneManager.viewModel(for: tab.tabId)
        let agentCount = vm?.agents.filter { $0.linkedSubagentId != nil }.count ?? 0
        let displayName = tab.workingDirName.isEmpty ? "Terminal" : tab.workingDirName

        return Button {
            HapticService.selection()
            navigationPath.append(tab.tabId)
        } label: {
            HStack(spacing: MajorTomTheme.Spacing.md) {
                // Icon
                Image(systemName: "building.2.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                    .frame(width: 44, height: 44)
                    .background(MajorTomTheme.Colors.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))

                // Info
                VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                    Text(displayName)
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: MajorTomTheme.Spacing.sm) {
                        Label("\(agentCount)", systemImage: "person.fill")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(MajorTomTheme.Colors.textSecondary)

                        Label("\(tab.sessions.count)", systemImage: "bubble.left")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(MajorTomTheme.Colors.textSecondary)

                        statusBadge(effectiveStatus(for: tab))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }
            .padding(MajorTomTheme.Spacing.md)
            .background(MajorTomTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium)
                    .stroke(MajorTomTheme.Colors.accent.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Available Tab Card

    private func availableTabCard(tab: TabMeta) -> some View {
        let displayName = tab.workingDirName.isEmpty ? "Terminal" : tab.workingDirName
        return Button {
            HapticService.selection()
            sceneManager.createOffice(for: tab.tabId)
            navigationPath.append(tab.tabId)
        } label: {
            HStack(spacing: MajorTomTheme.Spacing.md) {
                // Icon
                Image(systemName: "plus.square.dashed")
                    .font(.system(size: 24))
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(MajorTomTheme.Colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))

                // Info
                VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                    Text(displayName)
                        .font(.system(.body, design: .monospaced, weight: .medium))
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: MajorTomTheme.Spacing.sm) {
                        Text("Tap to create office")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(MajorTomTheme.Colors.textTertiary)

                        statusBadge(effectiveStatus(for: tab))
                    }
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }
            .padding(MajorTomTheme.Spacing.md)
            .background(MajorTomTheme.Colors.surface.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status Badge

    /// Normalize the relay-supplied status to one of `active` / `idle` /
    /// `closed` based on whether any sessions are still running in the tab.
    private func effectiveStatus(for tab: TabMeta) -> String {
        if tab.status == "closed" { return "closed" }
        return tab.sessions.isEmpty ? "idle" : "active"
    }

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "active": MajorTomTheme.Colors.allow
        case "idle": MajorTomTheme.Colors.accent
        default: MajorTomTheme.Colors.textTertiary
        }

        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(status)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}
