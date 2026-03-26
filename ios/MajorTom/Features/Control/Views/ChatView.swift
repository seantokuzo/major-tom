import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var isPermissionExpanded = false
    private let relay: RelayService

    init(relay: RelayService) {
        self.relay = relay
        _viewModel = State(initialValue: ChatViewModel(relay: relay))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            // Connection status bar + cost + permission pill
            connectionBar

            // Expandable permission mode picker
            if isPermissionExpanded {
                PermissionModeView(relay: relay)
                    .padding(.horizontal, MajorTomTheme.Spacing.md)
                    .padding(.vertical, MajorTomTheme.Spacing.sm)
                    .background(MajorTomTheme.Colors.surface)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Pending approvals (vertical stack)
            if !viewModel.pendingApprovals.isEmpty {
                approvalsList
            }

            // Messages with smart scroll
            ZStack(alignment: .bottomTrailing) {
                messagesList

                // Scroll-to-bottom FAB
                if viewModel.showScrollFab {
                    scrollToBottomFab
                }
            }

            // Input bar
            inputBar(text: $viewModel.inputText)
        }
        .background(MajorTomTheme.Colors.background)
        .animation(.spring(duration: 0.3), value: isPermissionExpanded)
        .task {
            if !viewModel.hasSession {
                await viewModel.startSession()
            }
        }
    }

    // MARK: - Connection Bar

    private var connectionBar: some View {
        HStack(spacing: MajorTomTheme.Spacing.sm) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(viewModel.connectionState.rawValue.capitalized)
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)

            Spacer()

            // Cost badge
            CostBadge(
                costUsd: viewModel.sessionCostUsd,
                turnCount: viewModel.sessionTurnCount,
                inputTokens: viewModel.sessionInputTokens,
                outputTokens: viewModel.sessionOutputTokens
            )

            PermissionModePill(
                mode: relay.permissionMode,
                godSubMode: relay.godSubMode,
                isExpanded: isPermissionExpanded
            ) {
                HapticService.buttonTap()
                isPermissionExpanded.toggle()
            }
        }
        .padding(.horizontal, MajorTomTheme.Spacing.lg)
        .padding(.vertical, MajorTomTheme.Spacing.sm)
        .background(MajorTomTheme.Colors.surface)
    }

    private var statusColor: Color {
        switch viewModel.connectionState {
        case .connected: MajorTomTheme.Colors.allow
        case .connecting, .reconnecting: MajorTomTheme.Colors.accent
        case .disconnected: MajorTomTheme.Colors.deny
        }
    }

    // MARK: - Approvals (Vertical Stack)

    private var approvalsList: some View {
        ScrollView {
            LazyVStack(spacing: MajorTomTheme.Spacing.md) {
                // Pending approvals
                ForEach(viewModel.pendingApprovals) { request in
                    let countdown: Int? = viewModel.isDelayMode
                        ? viewModel.countdownFor(request: request)
                        : nil

                    ApprovalCard(
                        request: request,
                        onDecision: { decision in
                            Task {
                                await viewModel.handleApproval(requestId: request.id, decision: decision)
                            }
                        },
                        countdownRemaining: countdown
                    )
                }

                // Recent auto-approved tools (dimmed)
                ForEach(viewModel.recentAutoApproved) { autoTool in
                    ApprovalCard(
                        request: ApprovalRequest(
                            from: ApprovalRequestEvent(
                                type: "approval.auto",
                                requestId: autoTool.id.uuidString,
                                tool: autoTool.tool,
                                description: autoTool.description,
                                details: nil
                            )
                        ),
                        onDecision: { _ in },
                        isAutoApproved: true
                    )
                }
            }
            .padding(MajorTomTheme.Spacing.md)
        }
        .frame(maxHeight: 400)
        .background(MajorTomTheme.Colors.surface.opacity(0.5))
    }

    // MARK: - Messages List (Smart Scroll)

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: MajorTomTheme.Spacing.sm) {
                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                        // Turn separator: insert between user→assistant transitions
                        if shouldShowTurnSeparator(at: index) {
                            TurnSeparator(timestamp: message.timestamp)
                        }

                        // Route to appropriate view
                        if message.role == .tool {
                            ToolMessageView(message: message)
                                .id(message.id)
                        } else {
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }

                    // Streaming indicator
                    if viewModel.isStreaming {
                        HStack {
                            StreamingIndicator()
                            Spacer()
                        }
                    }

                    // Scroll anchor
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(MajorTomTheme.Spacing.md)

                // Track scroll position
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geometry.frame(in: .named("chatScroll")).maxY
                        )
                }
                .frame(height: 0)
            }
            .coordinateSpace(name: "chatScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { maxY in
                viewModel.updateScrollPosition(contentMaxY: maxY)
            }
            .onChange(of: viewModel.messages.count) {
                if viewModel.isNearBottom {
                    withAnimation(.spring(duration: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    viewModel.unreadCount = 0
                } else {
                    viewModel.unreadCount += 1
                }
            }
            .onChange(of: viewModel.scrollToBottomTrigger) {
                withAnimation(.spring(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                viewModel.unreadCount = 0
                viewModel.isNearBottom = true
                viewModel.showScrollFab = false
            }
        }
    }

    // MARK: - Scroll to Bottom FAB

    private var scrollToBottomFab: some View {
        Button {
            HapticService.buttonTap()
            viewModel.scrollToBottomTrigger += 1
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(MajorTomTheme.Colors.surfaceElevated)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)

                // Unread badge
                if viewModel.unreadCount > 0 {
                    Text("\(min(viewModel.unreadCount, 99))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(MajorTomTheme.Colors.accent)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -6)
                }
            }
        }
        .padding(.trailing, MajorTomTheme.Spacing.lg)
        .padding(.bottom, MajorTomTheme.Spacing.md)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Turn Separator Logic

    private func shouldShowTurnSeparator(at index: Int) -> Bool {
        guard index > 0 else { return false }
        let messages = viewModel.messages
        let current = messages[index]
        let previous = messages[index - 1]

        // Show separator when transitioning from non-user to user (new turn)
        return current.role == .user && previous.role != .user
    }

    // MARK: - Input Bar

    private func inputBar(text: Binding<String>) -> some View {
        HStack(spacing: MajorTomTheme.Spacing.md) {
            TextField("Send a prompt...", text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                .lineLimit(1...5)
                .onSubmit {
                    Task { await viewModel.sendPrompt() }
                }

            Button {
                Task { await viewModel.sendPrompt() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? MajorTomTheme.Colors.textTertiary
                            : MajorTomTheme.Colors.accent
                    )
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(MajorTomTheme.Spacing.md)
        .background(MajorTomTheme.Colors.surface)
    }
}

// MARK: - Scroll Offset Preference Key

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    ChatView(relay: RelayService())
}
