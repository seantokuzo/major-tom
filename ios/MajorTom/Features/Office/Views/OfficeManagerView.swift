import SwiftUI

// MARK: - Office Manager View

/// Root view for the Office tab. Displays a card grid of sessions,
/// letting users create/navigate per-session Offices.
/// Uses NavigationStack to push into individual OfficeViews.
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
                .navigationDestination(for: String.self) { sessionId in
                    OfficeView(
                        sessionId: sessionId,
                        sceneManager: sceneManager,
                        relay: relay
                    )
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
        if sceneManager.viewModel(for: banner.sessionId) == nil
            || sceneManager.peekScene(for: banner.sessionId) == nil {
            sceneManager.createOffice(for: banner.sessionId)
        }
        navigationPath = NavigationPath()
        navigationPath.append(banner.sessionId)
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
        let allSessions = relay.sessionList
        let activeSessions = allSessions.filter { activeIds.contains($0.id) }
        let unlinkedSessions = allSessions.filter { !activeIds.contains($0.id) }

        if allSessions.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MajorTomTheme.Spacing.lg) {
                    // Active offices
                    if !activeSessions.isEmpty {
                        sectionHeader("Active Offices")
                        ForEach(activeSessions) { session in
                            activeOfficeCard(session: session)
                        }
                    }

                    // Unlinked sessions
                    if !unlinkedSessions.isEmpty {
                        sectionHeader("Available Sessions")
                        ForEach(unlinkedSessions) { session in
                            unlinkedSessionCard(session: session)
                        }
                    }
                }
                .padding(.horizontal, MajorTomTheme.Spacing.lg)
                .padding(.top, MajorTomTheme.Spacing.sm)
                .padding(.bottom, MajorTomTheme.Spacing.xxl)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: MajorTomTheme.Spacing.lg) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 48))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            Text("No Active Sessions")
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            Text("Connect to a relay and start a session to create an office.")
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

    private func activeOfficeCard(session: SessionMetaInfo) -> some View {
        let agentCount = sceneManager.viewModel(for: session.id)?.agents.filter { $0.linkedSubagentId != nil }.count ?? 0

        return Button {
            HapticService.selection()
            navigationPath.append(session.id)
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
                    Text(session.workingDirName)
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: MajorTomTheme.Spacing.sm) {
                        Label("\(agentCount)", systemImage: "person.fill")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(MajorTomTheme.Colors.textSecondary)

                        statusBadge(session.status)
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

    // MARK: - Unlinked Session Card

    private func unlinkedSessionCard(session: SessionMetaInfo) -> some View {
        Button {
            HapticService.selection()
            sceneManager.createOffice(for: session.id)
            navigationPath.append(session.id)
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
                    Text(session.workingDirName)
                        .font(.system(.body, design: .monospaced, weight: .medium))
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                        .lineLimit(1)

                    Text("Tap to create office")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
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
