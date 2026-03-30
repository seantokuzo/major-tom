import SwiftUI

struct FleetStatusBadge: View {
    let workerCount: Int
    let healthLevel: FleetHealthLevel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .medium))

                Text("\(workerCount)")
                    .font(.system(.caption, design: .default, weight: .bold))

                Circle()
                    .fill(healthColor)
                    .frame(width: 6, height: 6)
            }
            .foregroundStyle(MajorTomTheme.Colors.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MajorTomTheme.Colors.surfaceElevated)
            .clipShape(Capsule())
        }
    }

    private var healthColor: Color {
        switch healthLevel {
        case .green: MajorTomTheme.Colors.allow
        case .yellow: MajorTomTheme.Colors.warning
        case .red: MajorTomTheme.Colors.deny
        }
    }
}

#Preview {
    HStack(spacing: MajorTomTheme.Spacing.md) {
        FleetStatusBadge(workerCount: 3, healthLevel: .green, onTap: {})
        FleetStatusBadge(workerCount: 2, healthLevel: .yellow, onTap: {})
        FleetStatusBadge(workerCount: 1, healthLevel: .red, onTap: {})
        FleetStatusBadge(workerCount: 0, healthLevel: .green, onTap: {})
    }
    .padding()
    .background(MajorTomTheme.Colors.background)
}
