import SwiftUI

struct ToolActivityView: View {
    @State private var viewModel: ToolActivityViewModel

    init(relay: RelayService) {
        _viewModel = State(initialValue: ToolActivityViewModel(relay: relay))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            dragHandle

            // Header
            header

            // Tab picker
            tabPicker

            // Tool list
            toolList
        }
        .background(MajorTomTheme.Colors.surface)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: MajorTomTheme.Radius.large,
                topTrailingRadius: MajorTomTheme.Radius.large
            )
        )
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(MajorTomTheme.Colors.textTertiary)
            .frame(width: 36, height: 5)
            .padding(.top, MajorTomTheme.Spacing.sm)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label {
                Text("Tools")
                    .font(MajorTomTheme.Typography.headline)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
            } icon: {
                Image(systemName: "wrench.and.screwdriver")
                    .foregroundStyle(MajorTomTheme.Colors.accent)
            }

            if viewModel.runningCount > 0 {
                Text("\(viewModel.runningCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(MajorTomTheme.Colors.accent)
                    .clipShape(Capsule())
            }

            Spacer()

            if viewModel.failedCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text("\(viewModel.failedCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(MajorTomTheme.Colors.deny)
            }

            Text("\(viewModel.totalToolCount) total")
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
        }
        .padding(.horizontal, MajorTomTheme.Spacing.lg)
        .padding(.top, MajorTomTheme.Spacing.md)
        .padding(.bottom, MajorTomTheme.Spacing.sm)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(ToolActivityViewModel.Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.selectedTab = tab
                    }
                    HapticService.selection()
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            viewModel.selectedTab == tab
                                ? MajorTomTheme.Colors.textPrimary
                                : MajorTomTheme.Colors.textTertiary
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, MajorTomTheme.Spacing.sm)
                        .background(
                            viewModel.selectedTab == tab
                                ? MajorTomTheme.Colors.surfaceElevated
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, MajorTomTheme.Spacing.md)
        .padding(.vertical, MajorTomTheme.Spacing.xs)
    }

    // MARK: - Tool List

    private var toolList: some View {
        Group {
            let tools = viewModel.displayedTools
            if tools.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(tools) { tool in
                                ToolActivityRow(
                                    activity: tool,
                                    autoApproval: viewModel.autoApproval(for: tool)
                                )
                                .id(tool.id)

                                if tool.id != tools.last?.id {
                                    Divider()
                                        .overlay(MajorTomTheme.Colors.textTertiary.opacity(0.2))
                                        .padding(.leading, 52)
                                }
                            }
                        }
                        .padding(.bottom, MajorTomTheme.Spacing.lg)
                    }
                    .onChange(of: viewModel.activeTools.count) {
                        // List is sorted newest-first, so the most recent active tool is at the top
                        if let newest = viewModel.displayedTools.first {
                            withAnimation(.spring(duration: 0.3)) {
                                proxy.scrollTo(newest.id, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: MajorTomTheme.Spacing.md) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 32))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            Text(viewModel.selectedTab == .active ? "No active tools" : "No tools used yet")
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, MajorTomTheme.Spacing.xxl)
    }
}

// MARK: - Floating Tool Bar (for ChatView integration)

struct ToolActivityFloatingBar: View {
    let runningCount: Int
    let totalCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: MajorTomTheme.Spacing.sm) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MajorTomTheme.Colors.accent)

                if runningCount > 0 {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(MajorTomTheme.Colors.accent)
                        Text("\(runningCount) running")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MajorTomTheme.Colors.accent)
                    }
                } else if totalCount > 0 {
                    Text("\(totalCount) tools used")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }
            .padding(.horizontal, MajorTomTheme.Spacing.md)
            .padding(.vertical, MajorTomTheme.Spacing.sm)
            .background(MajorTomTheme.Colors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
            .overlay(
                RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small)
                    .stroke(MajorTomTheme.Colors.accent.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Activity Panel") {
    ToolActivityView(relay: RelayService())
        .frame(height: 400)
        .background(MajorTomTheme.Colors.background)
}

#Preview("Floating Bar - Running") {
    ToolActivityFloatingBar(runningCount: 3, totalCount: 7) {}
        .padding()
        .background(MajorTomTheme.Colors.background)
}

#Preview("Floating Bar - Idle") {
    ToolActivityFloatingBar(runningCount: 0, totalCount: 12) {}
        .padding()
        .background(MajorTomTheme.Colors.background)
}
