import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var dragOffset: CGFloat = 0

    init(relay: RelayService) {
        _viewModel = State(initialValue: ChatViewModel(relay: relay))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Connection status bar
                connectionBar

                // Pending approvals
                if !viewModel.pendingApprovals.isEmpty {
                    approvalsList
                }

                // Messages
                messagesList

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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MajorTomTheme.Spacing.md) {
                ForEach(viewModel.pendingApprovals) { request in
                    ApprovalCard(request: request) { decision in
                        Task {
                            await viewModel.handleApproval(requestId: request.id, decision: decision)
                        }
                    }
                    .frame(width: 300)
                }
            }
            .padding(MajorTomTheme.Spacing.md)
        }
        .background(MajorTomTheme.Colors.surface.opacity(0.5))
    }

    // MARK: - Messages

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: MajorTomTheme.Spacing.sm) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(MajorTomTheme.Spacing.md)
            }
            .onChange(of: viewModel.messages.count) {
                if let last = viewModel.messages.last {
                    withAnimation(.spring(duration: 0.3)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
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

                // Templates button
                Button {
                    HapticService.buttonTap()
                    viewModel.showTemplates = true
                } label: {
                    Image(systemName: "doc.text")
                        .font(.body)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }
            }
            .padding(MajorTomTheme.Spacing.md)
            .background(MajorTomTheme.Colors.surface)
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        if value.translation.height < -30 {
                            HapticService.buttonTap()
                            viewModel.showHistoryOverlay = true
                        }
                    }
            )
        }
    }
}

#Preview {
    ChatView(relay: RelayService())
}
