import SwiftUI

// MARK: - Enhanced Approval Card

struct ApprovalCard: View {
    let request: ApprovalRequest
    let onDecision: (ApprovalDecision) -> Void
    var isAutoApproved: Bool = false
    var autoApprovalReason: AutoApprovalReason? = nil
    var countdownRemaining: Int? = nil

    @State private var isExpanded = false
    @State private var dragOffset: CGFloat = 0

    private let swipeThreshold: CGFloat = 100

    var body: some View {
        ZStack {
            // Swipe reveal backgrounds
            swipeBackground

            // Main card content
            cardContent
                .offset(x: dragOffset)
                .gesture(swipeGesture)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragOffset)
        }
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
        .opacity(isAutoApproved ? 0.5 : 1.0)
        .overlay(autoApprovedBadge, alignment: .topTrailing)
        .overlay(countdownOverlay)
    }

    // MARK: - Swipe Background

    private var swipeBackground: some View {
        HStack(spacing: 0) {
            // Right swipe = Allow (green)
            ZStack {
                MajorTomTheme.Colors.allow
                VStack(spacing: MajorTomTheme.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                    Text("Allow")
                        .font(MajorTomTheme.Typography.headline)
                }
                .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)

            Spacer()

            // Left swipe = Deny (red)
            ZStack {
                MajorTomTheme.Colors.deny
                VStack(spacing: MajorTomTheme.Spacing.xs) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                    Text("Deny")
                        .font(MajorTomTheme.Typography.headline)
                }
                .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Card Content

    private var cardContent: some View {
        HStack(spacing: 0) {
            // Danger level left border
            Rectangle()
                .fill(request.dangerLevel.color)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.md) {
                // Header: tool name + danger indicator
                headerRow

                // Description
                Text(request.description)
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .lineLimit(isExpanded ? nil : 3)

                // Tool-specific details (expandable)
                if isExpanded {
                    toolDetails
                }

                // Expand/collapse toggle
                if hasExpandableContent {
                    expandToggle
                }

                // Action buttons
                if !isAutoApproved {
                    actionButtons
                }
            }
            .padding(MajorTomTheme.Spacing.lg)
        }
        .background(MajorTomTheme.Colors.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium)
                .stroke(request.dangerLevel.color.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: MajorTomTheme.Spacing.sm) {
            Image(systemName: request.dangerLevel.icon)
                .foregroundStyle(request.dangerLevel.color)
                .font(.body)

            Text(request.tool)
                .font(MajorTomTheme.Typography.headline)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)

            Spacer()

            // Priority badge (server-provided)
            HStack(spacing: 4) {
                Circle()
                    .fill(request.priorityLevel.color)
                    .frame(width: 6, height: 6)
                Text(request.priorityLevel.label)
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(request.priorityLevel.color)
            }
            .padding(.horizontal, MajorTomTheme.Spacing.sm)
            .padding(.vertical, MajorTomTheme.Spacing.xs)
            .background(request.priorityLevel.color.opacity(0.12))
            .clipShape(Capsule())

            // Danger badge
            Text(request.dangerLevel.label)
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(request.dangerLevel.color)
                .padding(.horizontal, MajorTomTheme.Spacing.sm)
                .padding(.vertical, MajorTomTheme.Spacing.xs)
                .background(request.dangerLevel.color.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    // MARK: - Tool-Specific Details

    @ViewBuilder
    private var toolDetails: some View {
        switch request.tool {
        case "Bash":
            bashDetails
        case "Edit":
            editDetails
        case "Write":
            writeDetails
        case "Read":
            readDetails
        case "Glob", "Grep":
            searchDetails
        default:
            EmptyView()
        }
    }

    private var bashDetails: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            if let command = request.command {
                DetailSection(title: "Command") {
                    Text(command)
                        .font(MajorTomTheme.Typography.codeFont)
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                        .padding(MajorTomTheme.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MajorTomTheme.Colors.background)
                        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
                }
            }
            if let cwd = request.workingDirectory {
                DetailSection(title: "Working Directory") {
                    Text(cwd)
                        .font(MajorTomTheme.Typography.codeFontSmall)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }
            }
        }
    }

    private var editDetails: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            if let path = request.filePath {
                DetailSection(title: "File") {
                    Text(path)
                        .font(MajorTomTheme.Typography.codeFontSmall)
                        .foregroundStyle(MajorTomTheme.Colors.accent)
                }
            }
            if let diff = request.diffContent {
                DetailSection(title: "Changes") {
                    DiffView(diff: diff)
                }
            }
        }
    }

    private var writeDetails: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            if let path = request.filePath {
                DetailSection(title: "File") {
                    Text(path)
                        .font(MajorTomTheme.Typography.codeFontSmall)
                        .foregroundStyle(MajorTomTheme.Colors.accent)
                }
            }
            if let preview = request.contentPreview {
                DetailSection(title: "Content Preview") {
                    Text(preview)
                        .font(MajorTomTheme.Typography.codeFontSmall)
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                        .padding(MajorTomTheme.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MajorTomTheme.Colors.background)
                        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
                }
            }
        }
    }

    private var readDetails: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            if let path = request.filePath {
                DetailSection(title: "File") {
                    Text(path)
                        .font(MajorTomTheme.Typography.codeFontSmall)
                        .foregroundStyle(MajorTomTheme.Colors.accent)
                }
            }
        }
    }

    private var searchDetails: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            if let pattern = request.searchPattern {
                DetailSection(title: "Pattern") {
                    Text(pattern)
                        .font(MajorTomTheme.Typography.codeFont)
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                }
            }
            if let path = request.searchPath {
                DetailSection(title: "Path") {
                    Text(path)
                        .font(MajorTomTheme.Typography.codeFontSmall)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }
            }
        }
    }

    // MARK: - Expand Toggle

    private var hasExpandableContent: Bool {
        switch request.tool {
        case "Bash": return request.command != nil || request.workingDirectory != nil
        case "Edit": return request.filePath != nil || request.diffContent != nil
        case "Write": return request.filePath != nil || request.contentPreview != nil
        case "Read": return request.filePath != nil
        case "Glob", "Grep": return request.searchPattern != nil
        default: return false
        }
    }

    private var expandToggle: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
            HapticService.selection()
        } label: {
            HStack(spacing: MajorTomTheme.Spacing.xs) {
                Text(isExpanded ? "Hide Details" : "Show Details")
                    .font(MajorTomTheme.Typography.caption)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(MajorTomTheme.Colors.accent)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: MajorTomTheme.Spacing.sm) {
            ApprovalButton(title: "Allow", color: MajorTomTheme.Colors.allow, shortcutKey: "a") {
                HapticService.approve()
                onDecision(.allow)
            }

            ApprovalButton(title: "Always", color: MajorTomTheme.Colors.accent, shortcutKey: "w") {
                HapticService.approve()
                onDecision(.allowAlways)
            }

            ApprovalButton(title: "Skip", color: MajorTomTheme.Colors.skip, shortcutKey: "s") {
                HapticService.skip()
                onDecision(.skip)
            }

            ApprovalButton(title: "Deny", color: MajorTomTheme.Colors.deny, shortcutKey: "d") {
                HapticService.deny()
                onDecision(.deny)
            }
        }
    }

    // MARK: - Swipe Gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard !isAutoApproved else { return }
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard !isAutoApproved else { return }

                if value.translation.width > swipeThreshold {
                    // Swipe right = Allow — fling offscreen
                    dragOffset = 500
                    HapticService.approve()
                    onDecision(.allow)
                } else if value.translation.width < -swipeThreshold {
                    // Swipe left = Deny — fling offscreen
                    dragOffset = -500
                    HapticService.deny()
                    onDecision(.deny)
                } else {
                    // Spring back
                    dragOffset = 0
                }
            }
    }

    // MARK: - Auto-approved Badge

    @ViewBuilder
    private var autoApprovedBadge: some View {
        if isAutoApproved {
            VStack(alignment: .trailing, spacing: 2) {
                Text("Auto-approved")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(.white)
                if let reason = autoApprovalReason {
                    Text(autoApprovalReasonLabel(reason))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, MajorTomTheme.Spacing.sm)
            .padding(.vertical, MajorTomTheme.Spacing.xs)
            .background(MajorTomTheme.Colors.accent.opacity(0.8))
            .clipShape(Capsule())
            .padding(MajorTomTheme.Spacing.sm)
        }
    }

    private func autoApprovalReasonLabel(_ reason: AutoApprovalReason) -> String {
        switch reason {
        case .smartSettings: return "Smart: settings"
        case .smartSession: return "Smart: session"
        case .godYolo: return "God: YOLO"
        case .godNormal: return "God mode"
        }
    }

    // MARK: - Countdown Overlay

    @ViewBuilder
    private var countdownOverlay: some View {
        if let remaining = countdownRemaining, remaining > 0 {
            ZStack {
                RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium)
                    .fill(.black.opacity(0.5))

                VStack(spacing: MajorTomTheme.Spacing.sm) {
                    Text("\(remaining)")
                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("Auto-approving...")
                        .font(MajorTomTheme.Typography.caption)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }
            }
        }
    }
}

// MARK: - Detail Section

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
            Text(title)
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                .textCase(.uppercase)
            content()
        }
    }
}

// MARK: - Diff View

struct DiffView: View {
    let diff: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(diff.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                if !line.isEmpty {
                    Text(line)
                        .font(MajorTomTheme.Typography.codeFontSmall)
                        .foregroundStyle(lineColor(for: line))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, MajorTomTheme.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(lineBackground(for: line))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
    }

    private func lineColor(for line: String) -> Color {
        if line.hasPrefix("+ ") {
            return MajorTomTheme.Colors.allow
        } else if line.hasPrefix("- ") {
            return MajorTomTheme.Colors.deny
        }
        return MajorTomTheme.Colors.textPrimary
    }

    private func lineBackground(for line: String) -> Color {
        if line.hasPrefix("+ ") {
            return MajorTomTheme.Colors.allow.opacity(0.1)
        } else if line.hasPrefix("- ") {
            return MajorTomTheme.Colors.deny.opacity(0.1)
        }
        return MajorTomTheme.Colors.background
    }
}

// MARK: - Approval Button

struct ApprovalButton: View {
    let title: String
    let color: Color
    var shortcutKey: KeyEquivalent? = nil
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            Text(title)
                .font(MajorTomTheme.Typography.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, MajorTomTheme.Spacing.sm)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
        }

        if let key = shortcutKey {
            button.keyboardShortcut(key, modifiers: [])
        } else {
            button
        }
    }
}

// MARK: - Previews

#Preview("High Danger - Bash rm") {
    ApprovalCard(
        request: ApprovalRequest(
            from: ApprovalRequestEvent(
                type: "approval.request",
                requestId: "1",
                tool: "Bash",
                description: "rm -rf node_modules && npm install",
                details: [
                    "command": .string("rm -rf node_modules && npm install"),
                    "working_directory": .string("/Users/dev/project"),
                ]
            )
        ),
        onDecision: { _ in }
    )
    .padding()
    .background(MajorTomTheme.Colors.background)
}

#Preview("Medium Danger - Edit") {
    ApprovalCard(
        request: ApprovalRequest(
            from: ApprovalRequestEvent(
                type: "approval.request",
                requestId: "2",
                tool: "Edit",
                description: "Editing src/config.json",
                details: [
                    "file_path": .string("src/config.json"),
                    "old_string": .string("\"debug\": false"),
                    "new_string": .string("\"debug\": true"),
                ]
            )
        ),
        onDecision: { _ in }
    )
    .padding()
    .background(MajorTomTheme.Colors.background)
}

#Preview("Normal - Read") {
    ApprovalCard(
        request: ApprovalRequest(
            from: ApprovalRequestEvent(
                type: "approval.request",
                requestId: "3",
                tool: "Read",
                description: "Reading src/index.ts",
                details: [
                    "path": .string("src/index.ts")
                ]
            )
        ),
        onDecision: { _ in }
    )
    .padding()
    .background(MajorTomTheme.Colors.background)
}

#Preview("Auto-approved") {
    ApprovalCard(
        request: ApprovalRequest(
            from: ApprovalRequestEvent(
                type: "approval.request",
                requestId: "4",
                tool: "Grep",
                description: "Searching for 'TODO'",
                details: [
                    "pattern": .string("TODO"),
                    "path": .string("src/"),
                ]
            )
        ),
        onDecision: { _ in },
        isAutoApproved: true
    )
    .padding()
    .background(MajorTomTheme.Colors.background)
}

#Preview("With Countdown") {
    ApprovalCard(
        request: ApprovalRequest(
            from: ApprovalRequestEvent(
                type: "approval.request",
                requestId: "5",
                tool: "Bash",
                description: "npm test",
                details: [
                    "command": .string("npm test")
                ]
            )
        ),
        onDecision: { _ in },
        countdownRemaining: 3
    )
    .padding()
    .background(MajorTomTheme.Colors.background)
}
