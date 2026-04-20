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
    var titleStore: TabTitleStore
    var terminalViewModel: TerminalViewModel

    @State private var navigationPath = NavigationPath()
    @State private var bannerTask: Task<Void, Never>?
    @State private var renameTarget: String?  // tabId being renamed
    @State private var renameDraft: String = ""

    /// Name shown on office cards. Must stay 1:1 with the terminal tab
    /// bar's label (`TerminalTabBar.displayTitle`) so the user's mental
    /// model of "Office for tab X" matches the tab strip. User-supplied
    /// override wins, otherwise fall back to the shell-supplied tab
    /// title. Do NOT fall back to the cwd basename — that diverged from
    /// the tab bar and broke the 1:1 promise.
    private func displayName(for tab: TerminalTab) -> String {
        titleStore.title(for: tab.tabId) ?? tab.title
    }

    /// Whether this terminal tab has an Office scene created for it.
    private func hasOffice(for tab: TerminalTab) -> Bool {
        sceneManager.viewModel(for: tab.tabId) != nil
    }

    /// Agent count for tabs that have an open Office (0 for tabs without).
    private func agentCount(for tab: TerminalTab) -> Int {
        guard let vm = sceneManager.viewModel(for: tab.tabId) else { return 0 }
        return vm.agents.filter { $0.linkedSubagentId != nil }.count
    }

    /// TabMeta from the relay for this terminal tab, when available.
    /// Present only if claude has run in the tab (SessionStart hook fired).
    private func tabMeta(for tab: TerminalTab) -> TabMeta? {
        relay.tabRegistryStore.tabs[tab.tabId]
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            scrollContent
                .navigationTitle("Offices")
                .navigationBarTitleDisplayMode(.large)
                .background(MajorTomTheme.Colors.background)
                .navigationDestination(for: String.self) { tabId in
                    OfficeView(
                        tabId: tabId,
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
        .alert(
            "Rename Office",
            isPresented: renameAlertBinding,
            presenting: renameTarget
        ) { tabId in
            TextField("Office name", text: $renameDraft)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
            Button("Save") {
                titleStore.setTitle(renameDraft, for: tabId)
                renameTarget = nil
            }
            Button("Reset", role: .destructive) {
                titleStore.setTitle(nil, for: tabId)
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) {
                renameTarget = nil
            }
        } message: { _ in
            Text("This renames the terminal tab too — they share a name.")
        }
    }

    // MARK: - Banner handling (M2)

    private func navigateToBannerSession(_ banner: OfficeSceneManager.CrossSessionBanner) {
        cancelBannerAutoHide()
        // Prefer tabId from the event (Wave 4); fall back to sessionId for
        // legacy cli/vscode sessions that never bind to a tab.
        let target = banner.routeKey
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
        let tabs = terminalViewModel.tabs

        if tabs.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MajorTomTheme.Spacing.md) {
                    ForEach(tabs) { tab in
                        terminalTabCard(tab: tab)
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
            Image(systemName: "apple.terminal")
                .font(.system(size: 48))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            Text("No Terminal Tabs")
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            Text("Open a terminal tab first — each one can have an Office.")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, MajorTomTheme.Spacing.xxl)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Terminal Tab Card

    @ViewBuilder
    private func terminalTabCard(tab: TerminalTab) -> some View {
        if hasOffice(for: tab) {
            openOfficeCard(tab: tab)
        } else {
            createOfficeCard(tab: tab)
        }
    }

    /// Card for a terminal tab that already has an Office scene — tapping
    /// it navigates into the OfficeView.
    private func openOfficeCard(tab: TerminalTab) -> some View {
        let count = agentCount(for: tab)
        let meta = tabMeta(for: tab)
        let sessionCount = meta?.sessions.count ?? 0
        let name = displayName(for: tab)
        let status = meta.map(effectiveStatus(for:)) ?? "idle"

        return Button {
            HapticService.selection()
            navigationPath.append(tab.tabId)
        } label: {
            HStack(spacing: MajorTomTheme.Spacing.md) {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                    .frame(width: 44, height: 44)
                    .background(MajorTomTheme.Colors.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))

                VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                    Text(name)
                        .font(.system(.body, design: .monospaced, weight: .semibold))
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: MajorTomTheme.Spacing.sm) {
                        Label("\(count)", systemImage: "person.fill")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(MajorTomTheme.Colors.textSecondary)

                        Label("\(sessionCount)", systemImage: "bubble.left")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(MajorTomTheme.Colors.textSecondary)

                        statusBadge(status)
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
        .contextMenu {
            Button {
                beginRename(for: tab)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            if titleStore.title(for: tab.tabId) != nil {
                Button(role: .destructive) {
                    titleStore.setTitle(nil, for: tab.tabId)
                } label: {
                    Label("Reset Name", systemImage: "arrow.uturn.backward")
                }
            }
            Divider()
            Button(role: .destructive) {
                HapticService.impact(.medium)
                sceneManager.closeOffice(for: tab.tabId)
            } label: {
                Label("Close Office", systemImage: "xmark.square")
            }
        }
    }

    /// Card for a terminal tab with no Office yet — tapping explicitly
    /// creates the Office scene and navigates into it. Office existence
    /// is 100% user-controlled; we never auto-create based on claude.
    private func createOfficeCard(tab: TerminalTab) -> some View {
        let name = displayName(for: tab)
        let meta = tabMeta(for: tab)
        let subtitle: String = {
            guard let meta else { return "No Office — tap to create" }
            if meta.sessions.isEmpty { return "No Office — tap to create" }
            return "\(meta.sessions.count) claude session\(meta.sessions.count == 1 ? "" : "s") — tap to create Office"
        }()

        return Button {
            HapticService.selection()
            sceneManager.createOffice(for: tab.tabId)
            navigationPath.append(tab.tabId)
        } label: {
            HStack(spacing: MajorTomTheme.Spacing.md) {
                Image(systemName: "plus.square.dashed")
                    .font(.system(size: 24))
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(MajorTomTheme.Colors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))

                VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                    Text(name)
                        .font(.system(.body, design: .monospaced, weight: .medium))
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                        .lineLimit(1)

                    Text(subtitle)
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
        .contextMenu {
            Button {
                beginRename(for: tab)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            if titleStore.title(for: tab.tabId) != nil {
                Button(role: .destructive) {
                    titleStore.setTitle(nil, for: tab.tabId)
                } label: {
                    Label("Reset Name", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    // MARK: - Rename

    private func beginRename(for tab: TerminalTab) {
        HapticService.impact(.medium)
        renameDraft = titleStore.title(for: tab.tabId) ?? ""
        renameTarget = tab.tabId
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
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
