import SwiftUI

struct NotificationSettingsView: View {
    @State private var viewModel: NotificationSettingsViewModel

    init(auth: AuthService) {
        _viewModel = State(initialValue: NotificationSettingsViewModel(auth: auth))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        List {
            if let config = Binding($viewModel.config) {
                quietHoursSection(config: config)
                prioritySection(config: config)
                digestSection(config: config)
            } else if viewModel.isLoading {
                loadingSection
            } else if let error = viewModel.errorMessage {
                errorSection(error)
            }
        }
        .scrollContentBackground(.hidden)
        .background(MajorTomTheme.Colors.background)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadConfig()
        }
    }

    // MARK: - Quiet Hours

    @ViewBuilder
    private func quietHoursSection(config: Binding<NotificationConfig>) -> some View {
        Section {
            Toggle(isOn: config.quietHours.enabled) {
                Label("Quiet Hours", systemImage: "moon.fill")
            }
            .listRowBackground(MajorTomTheme.Colors.surface)
            .onChange(of: config.quietHours.enabled.wrappedValue) { _, _ in
                viewModel.saveDebounced()
            }

            if config.quietHours.enabled.wrappedValue {
                DatePicker(
                    "Start",
                    selection: $viewModel.quietHoursStart,
                    displayedComponents: .hourAndMinute
                )
                .listRowBackground(MajorTomTheme.Colors.surface)

                DatePicker(
                    "End",
                    selection: $viewModel.quietHoursEnd,
                    displayedComponents: .hourAndMinute
                )
                .listRowBackground(MajorTomTheme.Colors.surface)

                Text("Only high-priority notifications fire during quiet hours.")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    .listRowBackground(MajorTomTheme.Colors.surface)
            }
        } header: {
            Text("Quiet Hours")
        }
    }

    // MARK: - Priority Threshold

    @ViewBuilder
    private func prioritySection(config: Binding<NotificationConfig>) -> some View {
        Section {
            Picker("Threshold", selection: config.priorityThreshold) {
                ForEach(NotificationSettingsViewModel.thresholdOptions, id: \.value) { option in
                    HStack(spacing: MajorTomTheme.Spacing.sm) {
                        Circle()
                            .fill(priorityColor(for: option.value))
                            .frame(width: 8, height: 8)
                        Text(option.label)
                    }
                    .tag(option.value)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(MajorTomTheme.Colors.surface)
            .onChange(of: config.priorityThreshold.wrappedValue) { _, _ in
                viewModel.saveDebounced()
            }

            Text("Notifications below this threshold are suppressed or batched.")
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                .listRowBackground(MajorTomTheme.Colors.surface)
        } header: {
            Text("Priority Threshold")
        }
    }

    // MARK: - Digest

    @ViewBuilder
    private func digestSection(config: Binding<NotificationConfig>) -> some View {
        Section {
            Toggle(isOn: config.digest.enabled) {
                Label("Digest Mode", systemImage: "tray.full.fill")
            }
            .listRowBackground(MajorTomTheme.Colors.surface)
            .onChange(of: config.digest.enabled.wrappedValue) { _, _ in
                viewModel.saveDebounced()
            }

            if config.digest.enabled.wrappedValue {
                Picker("Interval", selection: config.digest.intervalMinutes) {
                    ForEach(NotificationSettingsViewModel.digestIntervalOptions, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .listRowBackground(MajorTomTheme.Colors.surface)
                .onChange(of: config.digest.intervalMinutes.wrappedValue) { _, _ in
                    viewModel.saveDebounced()
                }

                Text("Low-priority approvals are batched into periodic digest notifications.")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    .listRowBackground(MajorTomTheme.Colors.surface)
            }
        } header: {
            Text("Digest")
        }
    }

    // MARK: - Loading / Error

    private var loadingSection: some View {
        Section {
            HStack {
                ProgressView()
                    .padding(.trailing, MajorTomTheme.Spacing.sm)
                Text("Loading notification settings...")
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            }
            .listRowBackground(MajorTomTheme.Colors.surface)
        }
    }

    private func errorSection(_ error: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
                Text(error)
                    .foregroundStyle(MajorTomTheme.Colors.deny)
                    .font(MajorTomTheme.Typography.caption)
                Button("Retry") {
                    Task { await viewModel.loadConfig() }
                }
                .foregroundStyle(MajorTomTheme.Colors.accent)
            }
            .listRowBackground(MajorTomTheme.Colors.surface)
        }
    }

    // MARK: - Helpers

    private func priorityColor(for level: String) -> Color {
        switch level {
        case "high": MajorTomTheme.Colors.danger
        case "medium": MajorTomTheme.Colors.warning
        case "low": MajorTomTheme.Colors.allow
        default: MajorTomTheme.Colors.textTertiary
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView(auth: AuthService())
    }
}
