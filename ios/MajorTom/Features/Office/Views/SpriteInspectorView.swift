import SwiftUI
import SpriteKit

// MARK: - Sprite Inspector (Wave 4)
//
// Three-mode inspector, keyed off the tapped sprite:
//
//   linkedSubagentId != nil → `/btw` modal with state machine
//   isDog                   → local canned-response modal
//   else                    → info panel only (idle human, Q4 decision D)
//
// The caller (OfficeView) passes the agent + a closure that sends a sprite
// message to the relay. All per-sprite state lives on the OfficeViewModel so
// the inspector can be opened/closed without losing pending → ready state.

struct SpriteInspectorView: View {
    let agent: AgentState
    let viewModel: OfficeViewModel
    let activityDescription: String?
    let onRename: (String) -> Void
    /// Called when the inspector should send a `/btw` to the relay.
    /// The closure is responsible for dispatching (or queuing) based on
    /// current relay connectivity. Returns `true` if the socket was
    /// connected at send time, `false` if the message was queued locally.
    let onSendLinkedMessage: ((QueuedSpriteMessage) -> Bool)?
    let onDismiss: () -> Void

    @State private var renameText = ""
    @State private var isRenaming = false
    @State private var draft: String = ""
    @State private var responseExpanded: Bool = false
    @State private var questionExpanded: Bool = false
    @State private var spriteScene: InspectorSpriteScene?

    private enum Mode {
        case linked
        case dog
        case idleHuman
    }

    private var mode: Mode {
        if agent.linkedSubagentId != nil {
            return .linked
        }
        if agent.characterType.isDog {
            return .dog
        }
        return .idleHuman
    }

    private var messagingState: SpriteMessagingState {
        viewModel.messagingState(for: agent.id)
    }

    private var hasQueuedLocally: Bool {
        guard let subagentId = agent.linkedSubagentId else { return false }
        return viewModel.queuedSpriteMessages.contains(where: { $0.subagentId == subagentId })
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.md) {
            spriteHeader

            Divider().background(MajorTomTheme.Colors.textTertiary)

            roleAndTask

            if let activityDescription {
                activitySection(activityDescription)
            }

            detailRows

            Spacer(minLength: MajorTomTheme.Spacing.sm)

            content

            actions
        }
        .padding(MajorTomTheme.Spacing.lg)
        .background(MajorTomTheme.Colors.surface)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Mark any unread response as read (clears green glow on sprite)
            // but keep the .ready state so the user can hit Cool Beans.
            viewModel.markResponseRead(for: agent.id)
        }
        .task {
            // Build the SpriteKit scene exactly once per inspector
            // presentation. Doing this inside `body` via an immediately-
            // invoked closure risks SwiftUI re-rendering and allocating
            // multiple scenes before the async state update lands.
            if spriteScene == nil {
                spriteScene = InspectorSpriteScene(characterType: agent.characterType)
            }
        }
        .onChange(of: agent.id) { _, _ in
            // Sprite switched under us (scenario #2) — discard draft.
            draft = ""
            responseExpanded = false
            questionExpanded = false
        }
    }

    // MARK: - Header

    private var spriteHeader: some View {
        HStack(spacing: MajorTomTheme.Spacing.md) {
            Group {
                if let spriteScene {
                    SpriteView(scene: spriteScene)
                } else {
                    // Placeholder until `.task` builds the scene (one frame at most).
                    Color.clear
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: MajorTomTheme.Radius.medium)
                    .stroke(CharacterCatalog.config(for: agent.characterType).spriteColor.opacity(0.5), lineWidth: 1.5)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(agent.name)
                    .font(MajorTomTheme.Typography.headline)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)

                Text(CharacterCatalog.config(for: agent.characterType).displayName)
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)

                statusBadge
            }

            Spacer()
        }
    }

    private var statusBadge: some View {
        let label: String
        let color: Color
        switch mode {
        case .linked:
            label = agent.status.rawValue.uppercased()
            color = statusColor(for: agent.status)
        case .dog:
            label = "DOG"
            color = MajorTomTheme.Colors.accent
        case .idleHuman:
            label = "CREW"
            color = MajorTomTheme.Colors.textSecondary
        }
        return Text(label)
            .font(.system(.caption2, design: .monospaced, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func statusColor(for status: AgentStatus) -> Color {
        switch status {
        case .spawning: return .gray
        case .walking: return .blue
        case .working: return MajorTomTheme.Colors.allow
        case .idle: return MajorTomTheme.Colors.accent
        case .celebrating: return .yellow
        case .leaving: return MajorTomTheme.Colors.deny
        }
    }

    // MARK: - Role + Task

    private var roleAndTask: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            HStack(spacing: MajorTomTheme.Spacing.sm) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                Text((agent.canonicalRole ?? agent.role).capitalized)
                    .font(MajorTomTheme.Typography.headline)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
            }

            if let task = agent.currentTask {
                HStack(alignment: .top, spacing: MajorTomTheme.Spacing.sm) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(MajorTomTheme.Colors.allow)
                    Text(task)
                        .font(MajorTomTheme.Typography.body)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(MajorTomTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MajorTomTheme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
    }

    private func activitySection(_ activity: String) -> some View {
        HStack(spacing: MajorTomTheme.Spacing.sm) {
            Image(systemName: "figure.walk")
                .font(.system(size: 12))
                .foregroundStyle(MajorTomTheme.Colors.accent)
            Text(activity)
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.accent)
        }
        .padding(.horizontal, MajorTomTheme.Spacing.sm)
        .padding(.vertical, MajorTomTheme.Spacing.xs)
        .background(MajorTomTheme.Colors.accentSubtle)
        .clipShape(Capsule())
    }

    private var detailRows: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            detailRow(label: "Agent ID", value: String(agent.id.prefix(12)) + "...")
            detailRow(label: "Desk", value: agent.deskIndex.map { "Desk \($0 + 1)" } ?? "None")
            detailRow(label: "Uptime", value: agent.uptime)
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
        }
    }

    // MARK: - Mode content

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .linked:
            linkedModeContent
        case .dog:
            dogModeContent
        case .idleHuman:
            idleHumanContent
        }
    }

    // MARK: - Linked mode (/btw state machine)

    @ViewBuilder
    private var linkedModeContent: some View {
        switch messagingState {
        case .idle:
            linkedInput(enabled: true, prompt: "/btw — send an observation...")
        case .pending(_, let question):
            pendingQuestionView(question)
            linkedInput(enabled: false, prompt: "Waiting for response...")
        case .ready(_, let question, let response, _):
            pendingQuestionView(question)
            responseView(response)
        }
    }

    @ViewBuilder
    private func linkedInput(enabled: Bool, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
            HStack(spacing: 6) {
                Text("/btw")
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                if hasQueuedLocally, enabled {
                    Text("queued — will send on reconnect")
                        .font(MajorTomTheme.Typography.caption)
                        .foregroundStyle(MajorTomTheme.Colors.warning)
                }
                Spacer()
            }

            HStack(spacing: MajorTomTheme.Spacing.sm) {
                TextField(prompt, text: $draft, axis: .vertical)
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                    .disabled(!enabled)
                    .padding(MajorTomTheme.Spacing.sm)
                    .background(MajorTomTheme.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
                    .lineLimit(1...4)

                Button(action: sendLinkedDraft) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(
                            sendDisabled
                            ? MajorTomTheme.Colors.textTertiary
                            : MajorTomTheme.Colors.accent
                        )
                }
                .disabled(sendDisabled)
            }
        }
    }

    private var sendDisabled: Bool {
        !messagingState.question.isNilOrEmpty || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func pendingQuestionView(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 10))
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                Text("You asked")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                Spacer()
                if question.count > 140 {
                    Button(questionExpanded ? "Less" : "More") {
                        questionExpanded.toggle()
                    }
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                }
            }
            Text(question)
                .font(MajorTomTheme.Typography.codeFontSmall)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .lineLimit(questionExpanded ? nil : 3)
        }
        .padding(MajorTomTheme.Spacing.sm)
        .background(MajorTomTheme.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
    }

    private func responseView(_ response: String) -> some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(MajorTomTheme.Colors.allow)
                Text("Response")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                Spacer()
                if response.count > 200 {
                    Button(responseExpanded ? "Less" : "More") {
                        responseExpanded.toggle()
                    }
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                }
            }
            Text(response)
                .font(MajorTomTheme.Typography.body)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                .lineLimit(responseExpanded ? nil : 6)
        }
        .padding(MajorTomTheme.Spacing.sm)
        .background(MajorTomTheme.Colors.allow.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small)
                .stroke(MajorTomTheme.Colors.allow.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
    }

    // MARK: - Dog mode

    @ViewBuilder
    private var dogModeContent: some View {
        switch messagingState {
        case .idle:
            dogInput(enabled: true)
        case .pending(_, let question):
            pendingQuestionView(question)
            dogInput(enabled: false)
        case .ready(_, let question, let response, _):
            pendingQuestionView(question)
            responseView(response)
        }
    }

    @ViewBuilder
    private func dogInput(enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                Text("Say hi to \(agent.name)")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                Spacer()
            }
            HStack(spacing: MajorTomTheme.Spacing.sm) {
                TextField(enabled ? "Pet, praise, or ask a silly question..." : "Thinking...", text: $draft, axis: .vertical)
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                    .disabled(!enabled)
                    .padding(MajorTomTheme.Spacing.sm)
                    .background(MajorTomTheme.Colors.background)
                    .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
                    .lineLimit(1...3)

                Button(action: sendDogDraft) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(
                            sendDisabled
                            ? MajorTomTheme.Colors.textTertiary
                            : MajorTomTheme.Colors.accent
                        )
                }
                .disabled(sendDisabled)
            }
        }
    }

    // MARK: - Idle human

    private var idleHumanContent: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                Text("Off duty")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                Spacer()
            }
            Text("This crew member isn't assigned to a subagent right now. They'll wander the station and take breaks.")
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .padding(MajorTomTheme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MajorTomTheme.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
        }
    }

    // MARK: - Actions row

    private var actions: some View {
        HStack(spacing: MajorTomTheme.Spacing.md) {
            if mode == .linked || mode == .idleHuman {
                Button {
                    renameText = agent.name
                    isRenaming = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                        .font(MajorTomTheme.Typography.caption)
                }
                .buttonStyle(.bordered)
                .tint(MajorTomTheme.Colors.accent)
                .alert("Rename Crew", isPresented: $isRenaming) {
                    TextField("Name", text: $renameText)
                    Button("Cancel", role: .cancel) {}
                    Button("Rename") {
                        if !renameText.isEmpty { onRename(renameText) }
                    }
                } message: {
                    Text("Enter a new display name.")
                }
            }

            Spacer()

            if case .ready = messagingState {
                Button {
                    HapticService.impact(.soft)
                    viewModel.dismissResponse(for: agent.id)
                    draft = ""
                } label: {
                    Label("Cool Beans", systemImage: "checkmark.circle.fill")
                        .font(MajorTomTheme.Typography.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(MajorTomTheme.Colors.allow)
            } else {
                Button {
                    onDismiss()
                } label: {
                    Label("Close", systemImage: "xmark.circle")
                        .font(MajorTomTheme.Typography.caption)
                }
                .buttonStyle(.bordered)
                .tint(MajorTomTheme.Colors.textTertiary)
            }
        }
    }

    // MARK: - Send actions

    private func sendLinkedDraft() {
        guard let handle = agent.spriteHandle,
              let subagentId = agent.linkedSubagentId,
              let send = onSendLinkedMessage,
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        let text = draft
        draft = ""
        HapticService.impact(.light)

        // Always transition to .pending; the caller decides send vs queue.
        guard let queued = viewModel.beginPendingMessage(
            spriteId: agent.id,
            spriteHandle: handle,
            subagentId: subagentId,
            text: text,
            isConnected: true  // stub — view layer just wants the descriptor
        ) else { return }

        let wasSent = send(queued)
        if !wasSent {
            // Caller signalled offline — persist to queue so reconnect flushes.
            if !viewModel.queuedSpriteMessages.contains(where: { $0.id == queued.id }) {
                viewModel.queuedSpriteMessages.append(queued)
            }
        }
    }

    private func sendDogDraft() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let text = draft
        draft = ""
        HapticService.impact(.light)
        viewModel.sendDogCannedMessage(spriteId: agent.id, text: text, character: agent.characterType)
    }
}

// MARK: - Optional helpers

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        switch self {
        case .none: return true
        case .some(let s): return s.isEmpty
        }
    }
}

#Preview {
    SpriteInspectorView(
        agent: AgentState(
            id: "preview-1",
            name: "Alice",
            role: "frontend",
            characterType: .frontendDev,
            status: .working,
            currentTask: "Building the login page",
            deskIndex: 0,
            linkedSubagentId: "sub-1",
            spriteHandle: "handle-1",
            canonicalRole: "frontend"
        ),
        viewModel: OfficeViewModel(),
        activityDescription: nil,
        onRename: { _ in },
        onSendLinkedMessage: { _ in true },
        onDismiss: {}
    )
}
