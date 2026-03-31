import SwiftUI

struct RateLimitSettingsView: View {
    private let relay: RelayService
    @State private var isLoading = false
    @State private var editedRoles: [String: EditableRoleLimit] = [:]
    @State private var isDirty = false

    // Override form
    @State private var overrideUserId = ""
    @State private var overridePrompts = ""
    @State private var overrideApprovals = ""

    struct EditableRoleLimit {
        var promptsPerMinute: Int
        var approvalsPerMinute: Int
    }

    init(relay: RelayService) {
        self.relay = relay
    }

    var body: some View {
        List {
            roleLimitsSection
            userOverridesSection
            addOverrideSection
        }
        .scrollContentBackground(.hidden)
        .background(MajorTomTheme.Colors.background)
        .navigationTitle("Rate Limits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await fetchConfig() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            await fetchConfig()
        }
        .onChange(of: relay.rateLimitRoles) {
            syncEditState()
        }
    }

    // MARK: - Role Limits

    private var roleLimitsSection: some View {
        Section {
            if editedRoles.isEmpty && isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(MajorTomTheme.Colors.accent)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if editedRoles.isEmpty {
                Text("No role limits configured")
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    .listRowBackground(MajorTomTheme.Colors.surface)
            } else {
                ForEach(Array(editedRoles.keys).sorted(), id: \.self) { role in
                    if let limits = editedRoles[role] {
                        RoleLimitRow(
                            role: role,
                            promptsPerMinute: Binding(
                                get: { limits.promptsPerMinute },
                                set: { newValue in
                                    editedRoles[role]?.promptsPerMinute = newValue
                                    isDirty = true
                                }
                            ),
                            approvalsPerMinute: Binding(
                                get: { limits.approvalsPerMinute },
                                set: { newValue in
                                    editedRoles[role]?.approvalsPerMinute = newValue
                                    isDirty = true
                                }
                            )
                        )
                        .listRowBackground(MajorTomTheme.Colors.surface)
                    }
                }

                Button {
                    saveRoleLimits()
                } label: {
                    HStack {
                        Spacer()
                        Text(isDirty ? "Save Changes" : "Saved")
                            .font(MajorTomTheme.Typography.codeFont)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(!isDirty)
                .listRowBackground(isDirty ? MajorTomTheme.Colors.accent.opacity(0.2) : MajorTomTheme.Colors.surface)
            }
        } header: {
            Text("Per-Role Limits")
        }
    }

    // MARK: - User Overrides

    private var userOverridesSection: some View {
        Section {
            if relay.rateLimitUserOverrides.isEmpty {
                Text("No user overrides")
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    .listRowBackground(MajorTomTheme.Colors.surface)
            } else {
                ForEach(Array(relay.rateLimitUserOverrides.keys).sorted(), id: \.self) { userId in
                    if let override = relay.rateLimitUserOverrides[userId] {
                        UserOverrideRow(userId: userId, override: override) {
                            removeOverride(userId: userId)
                        }
                        .listRowBackground(MajorTomTheme.Colors.surface)
                    }
                }
            }
        } header: {
            Text("User Overrides")
        }
    }

    // MARK: - Add Override

    private var addOverrideSection: some View {
        Section {
            if relay.teamUsers.isEmpty {
                TextField("User ID", text: $overrideUserId)
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .listRowBackground(MajorTomTheme.Colors.surface)
            } else {
                Picker("User", selection: $overrideUserId) {
                    Text("Select user").tag("")
                    ForEach(relay.teamUsers.filter({ $0.role != .admin })) { user in
                        Text("\(user.email) (\(user.role.displayName))").tag(user.id)
                    }
                }
                .listRowBackground(MajorTomTheme.Colors.surface)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prompts/min")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    TextField("--", text: $overridePrompts)
                        .font(MajorTomTheme.Typography.codeFont)
                        .keyboardType(.numberPad)
                }

                Divider()

                VStack(alignment: .leading, spacing: 2) {
                    Text("Approvals/min")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    TextField("--", text: $overrideApprovals)
                        .font(MajorTomTheme.Typography.codeFont)
                        .keyboardType(.numberPad)
                }
            }
            .listRowBackground(MajorTomTheme.Colors.surface)

            Button {
                addOverride()
            } label: {
                HStack {
                    Spacer()
                    Text("Add Override")
                        .font(MajorTomTheme.Typography.codeFont)
                        .fontWeight(.semibold)
                        .foregroundStyle(MajorTomTheme.Colors.accent)
                    Spacer()
                }
            }
            .disabled(overrideUserId.isEmpty)
            .listRowBackground(MajorTomTheme.Colors.surface)
        } header: {
            Text("Add Override")
        }
    }

    // MARK: - Actions

    private func fetchConfig() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let counterBefore = relay.responseCounter
            try await relay.getRateLimitConfig()
            for _ in 0..<40 {
                if Task.isCancelled { break }
                if relay.responseCounter != counterBefore { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            syncEditState()
        } catch {
            // Silently handle
        }
    }

    private func syncEditState() {
        editedRoles = relay.rateLimitRoles.mapValues {
            EditableRoleLimit(promptsPerMinute: $0.promptsPerMinute, approvalsPerMinute: $0.approvalsPerMinute)
        }
        isDirty = false
    }

    private func saveRoleLimits() {
        for (role, limits) in editedRoles {
            Task {
                try? await relay.setRoleRateLimit(
                    role: role,
                    promptsPerMinute: limits.promptsPerMinute,
                    approvalsPerMinute: limits.approvalsPerMinute
                )
            }
        }
        isDirty = false
        HapticService.notification(.success)
    }

    private func addOverride() {
        guard !overrideUserId.isEmpty else { return }
        Task {
            try? await relay.setUserRateLimitOverride(
                userId: overrideUserId,
                promptsPerMinute: Int(overridePrompts),
                approvalsPerMinute: Int(overrideApprovals)
            )
            overrideUserId = ""
            overridePrompts = ""
            overrideApprovals = ""
            try? await Task.sleep(for: .milliseconds(300))
            await fetchConfig()
        }
        HapticService.notification(.success)
    }

    private func removeOverride(userId: String) {
        Task {
            try? await relay.clearUserRateLimitOverride(userId: userId)
            try? await Task.sleep(for: .milliseconds(300))
            await fetchConfig()
        }
        HapticService.notification(.success)
    }
}

// MARK: - Role Limit Row

struct RoleLimitRow: View {
    let role: String
    @Binding var promptsPerMinute: Int
    @Binding var approvalsPerMinute: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(role.capitalized)
                .font(MajorTomTheme.Typography.codeFont)
                .fontWeight(.bold)
                .foregroundStyle(MajorTomTheme.Colors.textPrimary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prompts/min")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    Stepper(value: $promptsPerMinute, in: 0...1000) {
                        Text("\(promptsPerMinute)")
                            .font(MajorTomTheme.Typography.codeFont)
                            .foregroundStyle(MajorTomTheme.Colors.accent)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 2) {
                    Text("Approvals/min")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    Stepper(value: $approvalsPerMinute, in: 0...1000) {
                        Text("\(approvalsPerMinute)")
                            .font(MajorTomTheme.Typography.codeFont)
                            .foregroundStyle(MajorTomTheme.Colors.accent)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - User Override Row

struct UserOverrideRow: View {
    let userId: String
    let override: RateLimitUserOverrideData
    let onRemove: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(userId.prefix(16)) + (userId.count > 16 ? "..." : ""))
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)

                HStack(spacing: 8) {
                    if let p = override.promptsPerMinute {
                        Text("\(p)p/min")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(MajorTomTheme.Colors.accent)
                    }
                    if let a = override.approvalsPerMinute {
                        Text("\(a)a/min")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(MajorTomTheme.Colors.accent)
                    }
                }
            }

            Spacer()

            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
        }
    }
}

#Preview {
    NavigationStack {
        RateLimitSettingsView(relay: RelayService())
    }
}
