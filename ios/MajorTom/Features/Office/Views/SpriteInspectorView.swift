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

    /// Transient "agent completed" banner shown for ~2.5s when a linked agent
    /// despawns while the user had the inspector open (scenario 9 downgrade).
    @State private var agentCompletedToast: String?

    private enum Mode {
        case linked
        case dog
        case idleHuman
    }

    /// Live lookup of the current agent from the view model. If the agent has
    /// been despawned (agent.complete fired while the inspector was open), we
    /// fall back to the cached `agent` so the view can still render the sheet
    /// while showing the "agent completed" toast.
    private var currentAgent: AgentState {
        viewModel.agents.first(where: { $0.id == agent.id }) ?? agent
    }

    /// Scenario 9: mode is computed from the LIVE agent state. A sprite that
    /// was idle when tapped but became linked before send is now `.linked`.
    /// Conversely, a sprite that was linked at tap but has since completed is
    /// now `.idleHuman` (or `.dog`).
    private var mode: Mode {
        let live = currentAgent
        if live.linkedSubagentId != nil {
            return .linked
        }
        if live.characterType.isDog {
            return .dog
        }
        return .idleHuman
    }

    private var messagingState: SpriteMessagingState {
        viewModel.messagingState(for: currentAgent.id)
    }

    private var hasQueuedLocally: Bool {
        guard let subagentId = currentAgent.linkedSubagentId else { return false }
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

            if let toast = agentCompletedToast {
                agentCompletedBanner(toast)
            }

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
        // Scenario 9 downgrade — was linked at tap, now idle.
        .onChange(of: currentAgent.linkedSubagentId) { oldValue, newValue in
            // We only care about the linked → unlinked transition on the same sprite.
            if oldValue != nil, newValue == nil, !draft.isEmpty {
                showAgentCompletedToast()
            }
        }
    }

    /// Inline banner surfaced when the linked sprite despawned mid-type.
    private func agentCompletedBanner(_ text: String) -> some View {
        HStack(spacing: MajorTomTheme.Spacing.sm) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(MajorTomTheme.Colors.warning)
                .font(.system(size: 12))
            Text(text)
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
            Spacer()
        }
        .padding(MajorTomTheme.Spacing.sm)
        .background(MajorTomTheme.Colors.warning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
        .transition(.opacity)
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
        let live = currentAgent
        switch mode {
        case .linked:
            label = live.status.rawValue.uppercased()
            color = statusColor(for: live.status)
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
        let live = currentAgent
        return VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            HStack(spacing: MajorTomTheme.Spacing.sm) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(MajorTomTheme.Colors.accent)
                Text((live.canonicalRole ?? live.role).capitalized)
                    .font(MajorTomTheme.Typography.headline)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
            }

            if let task = live.currentTask {
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
        let live = currentAgent
        return VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
            detailRow(label: "Agent ID", value: String(live.id.prefix(12)) + "...")
            detailRow(
                label: "Desk",
                value: live.deskIndex.map { "Desk \($0 + 1)" }
                    ?? (live.overflowPosition != nil ? "Overflow" : "None")
            )
            detailRow(label: "Uptime", value: live.uptime)
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

    /// True when the relay disconnected and the sprite was flagged via
    /// `OfficeViewModel.markAllAgentsDisconnected`. Used to swap the /btw
    /// input for an informational "relay offline" panel.
    private var isDisconnected: Bool {
        viewModel.disconnectedSpriteIds.contains(currentAgent.id)
    }

    @ViewBuilder
    private var content: some View {
        if isDisconnected && mode == .linked {
            disconnectedLinkedContent
        } else {
            switch mode {
            case .linked:
                linkedModeContent
            case .dog:
                dogModeContent
            case .idleHuman:
                idleHumanContent
            }
        }
    }

    /// S4 info panel shown while the relay is disconnected and the sprite is
    /// gray-out. /btw is unavailable until reconnect.
    private var disconnectedLinkedContent: some View {
        VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 10))
                    .foregroundStyle(MajorTomTheme.Colors.warning)
                Text("Disconnected from relay")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                Spacer()
            }
            Text("We'll reconnect automatically. /btw will be available again once we're back online.")
                .font(MajorTomTheme.Typography.caption)
                .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                .padding(MajorTomTheme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MajorTomTheme.Colors.background)
                .clipShape(RoundedRectangle(cornerRadius: MajorTomTheme.Radius.small))
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
        // Scenario 9 — re-check linkage at send time using the live agent.
        // If the sprite is STILL linked, proceed with the /btw send. If it
        // flipped to idle mid-type (subagent finished), surface a brief toast
        // and clear the draft so the user understands the downgrade.
        let live = currentAgent
        guard let handle = live.spriteHandle,
              let subagentId = live.linkedSubagentId,
              let send = onSendLinkedMessage,
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            if live.linkedSubagentId == nil {
                showAgentCompletedToast()
            }
            return
        }

        let text = draft
        draft = ""
        HapticService.impact(.light)

        // Always transition to .pending; the caller decides send vs queue.
        guard let queued = viewModel.beginPendingMessage(
            spriteId: live.id,
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
        let live = currentAgent
        viewModel.sendDogCannedMessage(spriteId: live.id, text: text, character: live.characterType)
    }

    /// Surface a short "agent completed" banner, clear the draft, and auto-hide
    /// after 2.5s. Triggered when the inspector's linked sprite despawned mid-type.
    private func showAgentCompletedToast() {
        draft = ""
        HapticService.impact(.soft)
        agentCompletedToast = "Agent completed — /btw isn't available anymore."
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            agentCompletedToast = nil
        }
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
