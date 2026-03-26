import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var showSessionList = false
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

        VStack(spacing: 0) {
            // Connection status bar
            connectionBar

            // Pending approvals
            if !viewModel.pendingApprovals.isEmpty {
                approvalsList
            }

            // Messages
            messagesList

            // Input bar
            inputBar(text: $viewModel.inputText)
        }
        .background(MajorTomTheme.Colors.background)
        .sheet(isPresented: $showSessionList) {
            SessionListView(relay: relay, storage: storage)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                saveCurrentSession()
            }
        }
        .task {
            if !viewModel.hasSession {
                await viewModel.startSession()
            }
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
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(viewModel.connectionState.rawValue.capitalized)
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)

            if let session = relay.currentSession {
                Text("·")
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                Text(session.workingDir ?? session.id.prefix(8).description)
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

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
    ChatView(relay: RelayService(), storage: SessionStorageService())
}
