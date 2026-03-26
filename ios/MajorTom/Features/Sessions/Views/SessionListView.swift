import SwiftUI

struct SessionListView: View {
    @State private var viewModel: SessionListViewModel
    @Environment(\.dismiss) private var dismiss

    init(relay: RelayService, storage: SessionStorageService) {
        _viewModel = State(initialValue: SessionListViewModel(relay: relay, storage: storage))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            ZStack {
                MajorTomTheme.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if viewModel.sessions.isEmpty && !viewModel.isLoading {
                        emptyState
                    } else {
                        sessionsList
                    }

                    // New session input area
                    if viewModel.showNewSessionInput {
                        newSessionBar
                    }
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MajorTomTheme.Colors.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.spring(duration: 0.3)) {
                            viewModel.showNewSessionInput.toggle()
                        }
                        HapticService.buttonTap()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(MajorTomTheme.Colors.accent)
                    }
                }
            }
            .task {
                await viewModel.refreshSessions()
            }
        }
    }

    // MARK: - Sessions List

    private var sessionsList: some View {
        ScrollView {
            LazyVStack(spacing: MajorTomTheme.Spacing.sm) {
                ForEach(viewModel.sessions) { session in
                    Button {
                        Task {
                            await viewModel.switchToSession(session)
                            dismiss()
                        }
                    } label: {
                        SessionRowView(
                            session: session,
                            isCurrentSession: session.id == viewModel.currentSessionId
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(MajorTomTheme.Spacing.md)
        }
        .refreshable {
            await viewModel.refreshSessions()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: MajorTomTheme.Spacing.lg) {
            Spacer()

            Image(systemName: "terminal.fill")
                .font(.system(size: 48))
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)

            Text("No Sessions")
                .font(MajorTomTheme.Typography.title)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)

            Text("Start a new session to begin\nworking with Claude Code.")
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await viewModel.startNewSession()
                    dismiss()
                }
            } label: {
                Label("New Session", systemImage: "plus")
                    .font(MajorTomTheme.Typography.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, MajorTomTheme.Spacing.xl)
                    .padding(.vertical, MajorTomTheme.Spacing.md)
                    .background(MajorTomTheme.Colors.accent)
                    .clipShape(Capsule())
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - New Session Bar

    private var newSessionBar: some View {
        @Bindable var viewModel = viewModel

        return VStack(spacing: MajorTomTheme.Spacing.sm) {
            Divider()
                .background(MajorTomTheme.Colors.textTertiary)

            HStack(spacing: MajorTomTheme.Spacing.md) {
                TextField("Working directory (optional)", text: $viewModel.newSessionWorkingDir)
                    .textFieldStyle(.plain)
                    .font(MajorTomTheme.Typography.body)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button {
                    Task {
                        await viewModel.startNewSession()
                        dismiss()
                    }
                } label: {
                    Text("Start")
                        .font(MajorTomTheme.Typography.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, MajorTomTheme.Spacing.lg)
                        .padding(.vertical, MajorTomTheme.Spacing.sm)
                        .background(MajorTomTheme.Colors.accent)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, MajorTomTheme.Spacing.lg)
            .padding(.vertical, MajorTomTheme.Spacing.sm)
        }
        .background(MajorTomTheme.Colors.surface)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

#Preview {
    SessionListView(relay: RelayService(), storage: SessionStorageService())
        .preferredColorScheme(.dark)
}
