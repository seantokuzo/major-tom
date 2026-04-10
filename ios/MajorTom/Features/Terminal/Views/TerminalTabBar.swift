import SwiftUI

/// Horizontal scrolling tab bar for terminal multi-tab support.
///
/// Sits above the WKWebView terminal area. Shows tabs with titles from
/// xterm title sequences, highlights the active tab, and provides close
/// buttons on each tab plus a "+" button to create new tabs.
struct TerminalTabBar: View {
    /// The list of open terminal tabs.
    let tabs: [TerminalTab]

    /// Callback when a tab is tapped to switch to it.
    let onSelectTab: (UUID) -> Void

    /// Callback when the close button on a tab is tapped.
    let onCloseTab: (UUID) -> Void

    /// Callback when the "+" button is tapped to create a new tab.
    let onCreateTab: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MajorTomTheme.Spacing.xs) {
                ForEach(tabs) { tab in
                    tabButton(for: tab)
                }

                // New tab button
                newTabButton
            }
            .padding(.horizontal, MajorTomTheme.Spacing.sm)
            .padding(.vertical, MajorTomTheme.Spacing.xs)
        }
        .frame(height: 36)
        .background(MajorTomTheme.Colors.surface)
    }

    // MARK: - Tab Button

    private func tabButton(for tab: TerminalTab) -> some View {
        HStack(spacing: MajorTomTheme.Spacing.xs) {
            Text(tab.title)
                .font(.system(size: 12, weight: tab.isActive ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(tab.isActive ? MajorTomTheme.Colors.accent : MajorTomTheme.Colors.textSecondary)
                .lineLimit(1)

            // Close button
            Button {
                onCloseTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tab.isActive ? MajorTomTheme.Colors.textSecondary : MajorTomTheme.Colors.textTertiary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close \(tab.title)")
        }
        .padding(.horizontal, MajorTomTheme.Spacing.sm)
        .padding(.vertical, MajorTomTheme.Spacing.xs)
        .background(tabBackground(isActive: tab.isActive))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    tab.isActive ? MajorTomTheme.Colors.accent.opacity(0.4) : Color.clear,
                    lineWidth: 1
                )
        )
        .onTapGesture {
            onSelectTab(tab.id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(tab.title), tab\(tab.isActive ? ", active" : "")")
    }

    // MARK: - New Tab Button

    private var newTabButton: some View {
        Button {
            onCreateTab()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .frame(width: 28, height: 28)
                .background(MajorTomTheme.Colors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New tab")
        .accessibilityHint("Creates a new terminal tab")
    }

    // MARK: - Helpers

    private func tabBackground(isActive: Bool) -> Color {
        isActive ? MajorTomTheme.Colors.surfaceElevated : MajorTomTheme.Colors.surface
    }
}
