import SwiftUI

struct AutoApprovalBadge: View {
    let reason: AutoApprovalReason

    var body: some View {
        HStack(spacing: MajorTomTheme.Spacing.xs) {
            Image(systemName: iconName)
                .font(.system(size: 8))
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .default))
        }
        .foregroundStyle(badgeColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(badgeColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var label: String {
        switch reason {
        case .smartSettings, .smartSession:
            return "Smart"
        case .godYolo, .godNormal:
            return "God"
        }
    }

    private var iconName: String {
        switch reason {
        case .smartSettings, .smartSession:
            return "brain"
        case .godYolo:
            return "bolt.fill"
        case .godNormal:
            return "crown.fill"
        }
    }

    private var badgeColor: Color {
        switch reason {
        case .smartSettings, .smartSession:
            return MajorTomTheme.Colors.accent
        case .godYolo:
            return MajorTomTheme.Colors.danger
        case .godNormal:
            return MajorTomTheme.Colors.warning
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        AutoApprovalBadge(reason: .smartSettings)
        AutoApprovalBadge(reason: .smartSession)
        AutoApprovalBadge(reason: .godNormal)
        AutoApprovalBadge(reason: .godYolo)
    }
    .padding()
    .background(MajorTomTheme.Colors.background)
}
