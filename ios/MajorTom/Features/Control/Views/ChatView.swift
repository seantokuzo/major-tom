import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var activityViewModel: ToolActivityViewModel
    @State private var showActivitySheet = false

    private let relay: RelayService

    init(relay: RelayService) {
        self.relay = relay
        _viewModel = State(initialValue: ChatViewModel(relay: relay))
        _activityViewModel = State(initialValue: ToolActivityViewModel(relay: relay))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            // Connection status bar
            connectionBar

            // Pending approvals
            if !viewModel.pendingApprovals.isEmpty {
                approvalsList
            }

            // Messages
            messagesList

            // Tool activity floating bar
            if activityViewModel.totalToolCount > 0 {
                ToolActivityFloatingBar(
                    runningCount: activityViewModel.runningCount,
                    totalCount: activityViewModel.totalToolCount
                ) {
                    HapticService.impact(.medium)
                    showActivitySheet = true
                }
                .padding(.horizontal, MajorTomTheme.Spacing.md)
                .padding(.vertical, MajorTomTheme.Spacing.xs)
            }

            // Input bar
            inputBar(text: $viewModel.inputText)
        }
        .background(MajorTomTheme.Colors.background)
        .sheet(isPresented: $showActivitySheet) {
            ToolActivityView(relay: relay)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(MajorTomTheme.Colors.surface)
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
