import SwiftUI

// MARK: - Sprite Response Banner (Wave 4 M2)
//
// In-app toast that surfaces a `/btw` response when it arrives for a sprite
// in a different Office than the one the user is currently viewing. Tapping
// the banner navigates to the origin session's Office.

struct SpriteResponseBanner: View {
    let banner: OfficeSceneManager.CrossSessionBanner
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: MajorTomTheme.Spacing.md) {
            Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                .font(.system(size: 16))
                .foregroundStyle(MajorTomTheme.Colors.allow)

            VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                Text("[\(banner.sessionName)] \(banner.spriteName)")
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                    .lineLimit(1)
                Text(banner.preview)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(MajorTomTheme.Spacing.md)
        .background(MajorTomTheme.Colors.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium)
                .stroke(MajorTomTheme.Colors.allow.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
        .onTapGesture {
            HapticService.selection()
            onTap()
        }
    }
}
