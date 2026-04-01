import SwiftUI

struct CIPanelView: View {
    let relay: RelayService
    @State private var autoRefresh = false
    @State private var refreshTimer: Timer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let error = relay.ciError {
                    HStack(spacing: MajorTomTheme.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(MajorTomTheme.Colors.deny)
                        Text(error)
                            .font(MajorTomTheme.Typography.caption)
                            .foregroundStyle(MajorTomTheme.Colors.deny)
                    }
                    .padding(MajorTomTheme.Spacing.md)
                }

                CIRunsView(relay: relay)
            }
            .background(MajorTomTheme.Colors.background)
            .navigationTitle("CI / CD")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: MajorTomTheme.Spacing.sm) {
                        Toggle(isOn: $autoRefresh) {
                            Image(systemName: "arrow.clockwise.circle")
                                .foregroundStyle(autoRefresh ? MajorTomTheme.Colors.allow : MajorTomTheme.Colors.textTertiary)
                        }
                        .toggleStyle(.button)

                        Button {
                            Task { try? await relay.requestCIRuns() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(MajorTomTheme.Colors.accent)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(MajorTomTheme.Colors.background)
        .task {
            try? await relay.requestCIRuns()
        }
        .onChange(of: autoRefresh) { _, enabled in
            if enabled {
                startAutoRefresh()
            } else {
                stopAutoRefresh()
            }
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }

    private func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in
                try? await relay.requestCIRuns()
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
