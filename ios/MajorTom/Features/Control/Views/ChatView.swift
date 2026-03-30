import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var isPermissionExpanded = false
    @State private var showSessionList = false
    @State private var showActivitySheet = false
    @Environment(\.scenePhase) private var scenePhase
    private let relay: RelayService
    private let storage: SessionStorageService

    init(relay: RelayService, storage: SessionStorageService) {
        self.relay = relay
        self.storage = storage
        _viewModel = State(initialValue: ChatViewModel(relay: relay))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                connectionBar

                if isPermissionExpanded {
                    PermissionModeView(relay: relay)
                        .padding(.horizontal, MajorTomTheme.Spacing.md)
                        .padding(.vertical, MajorTomTheme.Spacing.sm)
                        .background(MajorTomTheme.Colors.surface)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !viewModel.pendingApprovals.isEmpty {
                    approvalsList
                }

                ZStack(alignment: .bottomTrailing) {
                    messagesList
                    if viewModel.showScrollFab { scrollToBottomFab }
                }
                .animation(.spring(duration: 0.3), value: viewModel.showScrollFab)

                if viewModel.showCommandPalette {
                    CommandPaletteView(
                        query: viewModel.commandQuery,
                        onSelectCommand: { viewModel.executeCommand($0) }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                ContextChipsBar(paths: viewModel.contextPaths) { viewModel.removeContextFile($0) }

                // Tool activity floating bar
                if relay.activeTools.count + relay.completedTools.count > 0 {
                    ToolActivityFloatingBar(
                        runningCount: relay.activeTools.count,
                        totalCount: relay.activeTools.count + relay.completedTools.count
                    ) {
                        HapticService.impact(.medium)
                        showActivitySheet = true
                    }
                    .padding(.horizontal, MajorTomTheme.Spacing.md)
                    .padding(.vertical, MajorTomTheme.Spacing.xs)
                }

                inputBar(text: $viewModel.inputText)
            }
            .background(MajorTomTheme.Colors.background)

            if viewModel.showHistoryOverlay {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { viewModel.showHistoryOverlay = false }

                PromptHistoryOverlay(
                    viewModel: viewModel.historyViewModel,
                    onSelectEntry: { viewModel.insertHistoryEntry($0) },
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
            TemplateListView(viewModel: viewModel.templateViewModel) { viewModel.insertTemplate($0) }
        }
        .sheet(isPresented: $viewModel.showFileContext) {
            FileContextView(relay: viewModel.relay, onFilesSelected: { viewModel.addContextFiles($0) }, isPresented: $viewModel.showFileContext)
        }
        .sheet(isPresented: $showSessionList) {
            SessionListView(relay: relay, storage: storage)
        }
        .sheet(isPresented: $showActivitySheet) {
            ToolActivityView(relay: relay)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(MajorTomTheme.Colors.surface)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background { saveCurrentSession() }
        }
        .task {
            if !viewModel.hasSession { await viewModel.startSession() }
        }
    }

    private func saveCurrentSession() {
        guard let session = relay.currentSession else { return }
        storage.saveMessages(relay.chatMessages, for: session.id)
        storage.saveFromSessionInfo(session, messageCount: relay.chatMessages.count)
    }

    // MARK: - Connection Bar

    private var connectionBar: some View {
        HStack(spacing: MajorTomTheme.Spacing.sm) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(viewModel.connectionState.rawValue.capitalized)
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)

            if let session = relay.currentSession {
                Text("·").foregroundStyle(MajorTomTheme.Colors.textTertiary)
                Text(session.workingDir ?? session.id.prefix(8).description)
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            CostBadge(costUsd: viewModel.sessionCostUsd, turnCount: viewModel.sessionTurnCount, inputTokens: viewModel.sessionInputTokens, outputTokens: viewModel.sessionOutputTokens)

            PermissionModePill(mode: relay.permissionMode, godSubMode: relay.godSubMode, isExpanded: isPermissionExpanded) {
                HapticService.buttonTap()
                isPermissionExpanded.toggle()
            }

            Button {
                showSessionList = true
                HapticService.buttonTap()
            } label: {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(MajorTomTheme.Colors.accent)
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

    // MARK: - Approvals

    private var approvalsList: some View {
        Group {
            if viewModel.isDelayMode {
                // TimelineView drives per-second re-renders for countdown timers
                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    approvalsContent(now: context.date)
                }
            } else {
                approvalsContent(now: Date())
            }
        }
        .frame(maxHeight: 400)
        .background(MajorTomTheme.Colors.surface.opacity(0.5))
    }

    private func approvalsContent(now: Date) -> some View {
        ScrollView {
            LazyVStack(spacing: MajorTomTheme.Spacing.md) {
                ForEach(viewModel.pendingApprovals) { request in
                    ApprovalCard(request: request, onDecision: { decision in
                        Task { await viewModel.handleApproval(requestId: request.id, decision: decision) }
                    }, countdownRemaining: viewModel.isDelayMode ? viewModel.countdownFor(request: request, at: now) : nil)
                }
                ForEach(viewModel.recentAutoApproved) { autoTool in
                    ApprovalCard(
                        request: ApprovalRequest(from: ApprovalRequestEvent(type: "approval.auto", requestId: autoTool.id.uuidString, tool: autoTool.tool, description: autoTool.description, details: nil)),
                        onDecision: { _ in },
                        isAutoApproved: true,
                        autoApprovalReason: autoTool.reason
                    )
                }
            }
            .padding(MajorTomTheme.Spacing.md)
        }
    }

    // MARK: - Messages

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: MajorTomTheme.Spacing.sm) {
                    ForEach(viewModel.messages.indices, id: \.self) { index in
                        let message = viewModel.messages[index]
                        if shouldShowTurnSeparator(at: index) { TurnSeparator(timestamp: message.timestamp) }
                        if message.role == .tool {
                            ToolMessageView(message: message).id(message.id)
                        } else {
                            MessageBubble(message: message).id(message.id)
                        }
                    }
                    if viewModel.isStreaming { HStack { StreamingIndicator(); Spacer() } }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(MajorTomTheme.Spacing.md)
                GeometryReader { geo in
                    Color.clear.preference(key: ScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("chatScroll")).maxY)
                }.frame(height: 0)
            }
            .coordinateSpace(name: "chatScroll")
            .background(
                GeometryReader { geo in
                    Color.clear.onAppear {
                        viewModel.scrollViewHeight = geo.size.height
                    }
                    .onChange(of: geo.size.height) { _, newHeight in
                        viewModel.scrollViewHeight = newHeight
                    }
                }
            )
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { viewModel.updateScrollPosition(contentMaxY: $0) }
            .onChange(of: viewModel.messages.count) {
                if viewModel.isNearBottom {
                    withAnimation(.spring(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    viewModel.unreadCount = 0
                } else { viewModel.unreadCount += 1 }
            }
            .onChange(of: viewModel.scrollToBottomTrigger) {
                withAnimation(.spring(duration: 0.3)) { proxy.scrollTo("bottom", anchor: .bottom) }
                viewModel.unreadCount = 0; viewModel.isNearBottom = true; viewModel.showScrollFab = false
            }
        }
    }

    private var scrollToBottomFab: some View {
        Button {
            HapticService.buttonTap()
            viewModel.scrollToBottomTrigger += 1
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "chevron.down").font(.body.weight(.semibold))
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(MajorTomTheme.Colors.surfaceElevated)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                if viewModel.unreadCount > 0 {
                    Text("\(min(viewModel.unreadCount, 99))").font(.caption2.weight(.bold))
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(MajorTomTheme.Colors.accent).clipShape(Capsule())
                        .offset(x: 6, y: -6)
                }
            }
        }
        .padding(.trailing, MajorTomTheme.Spacing.lg)
        .padding(.bottom, MajorTomTheme.Spacing.md)
        .transition(.scale.combined(with: .opacity))
    }

    private func shouldShowTurnSeparator(at index: Int) -> Bool {
        guard index > 0 else { return false }
        return viewModel.messages[index].role == .user && viewModel.messages[index - 1].role != .user
    }

    // MARK: - Input Bar

    private func inputBar(text: Binding<String>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: MajorTomTheme.Spacing.sm) {
                VoiceInputButton(speechService: viewModel.speechService, onTranscription: { viewModel.handleTranscription($0) })
                TextField("Send a prompt...", text: text, axis: .vertical)
                    .textFieldStyle(.plain).font(MajorTomTheme.Typography.body)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary).lineLimit(1...5)
                    .onChange(of: viewModel.inputText) { _, v in viewModel.handleInputChange(v) }
                    .onSubmit { Task { await viewModel.sendPrompt() } }
                Button { HapticService.buttonTap(); viewModel.showTemplates = true } label: {
                    Image(systemName: "doc.on.clipboard").font(.body).foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }
                Button {
                    HapticService.impact(.medium)
                    Task { await viewModel.sendPrompt() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                        .foregroundStyle(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? MajorTomTheme.Colors.textTertiary : MajorTomTheme.Colors.accent)
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(MajorTomTheme.Spacing.md)
            .background(MajorTomTheme.Colors.surface)
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.height < -50 { HapticService.buttonTap(); viewModel.showHistoryOverlay = true }
        })
    }
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

#Preview { ChatView(relay: RelayService(), storage: SessionStorageService()) }
