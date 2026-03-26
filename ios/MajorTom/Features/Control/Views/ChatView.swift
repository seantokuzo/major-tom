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

        ZStack(alignment: .bottom) {
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

                // Command palette (above input bar)
                if viewModel.showCommandPalette {
                    CommandPaletteView(
                        query: viewModel.commandQuery,
                        onSelectCommand: { command in
                            viewModel.executeCommand(command)
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Context chips
                ContextChipsBar(paths: viewModel.contextPaths) { path in
                    viewModel.removeContextFile(path)
                }

                // Input bar
                inputBar(text: $viewModel.inputText)
            }
            .background(MajorTomTheme.Colors.background)

            // History overlay
            if viewModel.showHistoryOverlay {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        viewModel.showHistoryOverlay = false
                    }

                PromptHistoryOverlay(
                    viewModel: viewModel.historyViewModel,
                    onSelectEntry: { text in
                        viewModel.insertHistoryEntry(text)
                    },
                    isPresented: $viewModel.showHistoryOverlay
                )
                .frame(maxHeight: 400)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: isPermissionExpanded)
        .animation(.spring(duration: 0.3), value: viewModel.showHistoryOverlay)
        .animation(.spring(duration: 0.2), value: viewModel.showCommandPalette)
        .sheet(isPresented: $viewModel.showTemplates) {
            TemplateListView(
                viewModel: viewModel.templateViewModel,
                onSelectTemplate: { content in
                    viewModel.insertTemplate(content)
                }
            )
        }
        .sheet(isPresented: $viewModel.showFileContext) {
            FileContextView(
                relay: viewModel.relay,
                onFilesSelected: { paths in
                    viewModel.addContextFiles(paths)
                },
                isPresented: $viewModel.showFileContext
            )
        }
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
                        if shouldShowTurnSeparator(at: index) {
                            TurnSeparator(timestamp: message.timestamp)
                        }

                        if message.role == .tool {
                            ToolMessageView(message: message)
                                .id(message.id)
                        } else {
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }

                    if viewModel.isStreaming {
                        HStack {
                            StreamingIndicator()
                            Spacer()
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(MajorTomTheme.Spacing.md)

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
        return current.role == .user && previous.role != .user
    }

    // MARK: - Input Bar

    private func inputBar(text: Binding<String>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: MajorTomTheme.Spacing.sm) {
                // Voice input button
                VoiceInputButton(
                    speechService: viewModel.speechService,
                    onTranscription: { transcribed in
                        viewModel.handleTranscription(transcribed)
                    }
                )

                // Text field
                TextField("Send a prompt...", text: text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(MajorTomTheme.Typography.body)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                    .lineLimit(1...5)
                    .onChange(of: viewModel.inputText) { _, newValue in
                        viewModel.handleInputChange(newValue)
                    }
                    .onSubmit {
                        Task { await viewModel.sendPrompt() }
                    }

                // Templates button
                Button {
                    HapticService.buttonTap()
                    viewModel.showTemplates = true
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.body)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }

                // Send button
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
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.height < -50 {
                        HapticService.buttonTap()
                        viewModel.showHistoryOverlay = true
                    }
                }
        )
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
