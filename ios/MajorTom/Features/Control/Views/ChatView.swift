import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel

    init(relay: RelayService) {
        _viewModel = State(initialValue: ChatViewModel(relay: relay))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            // Connection status bar
            connectionBar

            // Messages + inline approvals
            messagesList

            // Pending approvals (vertical stack)
            if !viewModel.pendingApprovals.isEmpty {
                approvalsList
            }

            // Input bar
            inputBar(text: $viewModel.inputText)
        }
        .background(MajorTomTheme.Colors.background)
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

#Preview {
    ChatView(relay: RelayService())
}
