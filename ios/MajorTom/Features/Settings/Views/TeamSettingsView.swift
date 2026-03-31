import SwiftUI

struct TeamSettingsView: View {
    private let relay: RelayService
    private let auth: AuthService
    @State private var selectedRole: UserRole = .operator
    @State private var generatedCode: String?
    @State private var codeExpiry: String?
    @State private var isLoading = false

    init(relay: RelayService, auth: AuthService) {
        self.relay = relay
        self.auth = auth
    }

    var body: some View {
        List {
            teamMembersSection
            if relay.currentUserRole == .admin {
                inviteSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(MajorTomTheme.Colors.background)
        .navigationTitle("Team")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoading = true
            defer { isLoading = false }
            do {
                let counterBefore = relay.responseCounter
                try await relay.requestUserList()
                for _ in 0..<40 {
                    if Task.isCancelled { break }
                    if relay.responseCounter != counterBefore { break }
                    try await Task.sleep(for: .milliseconds(50))
                }
            } catch {
                // Silent fail — user list just won't load
            }
        }
        .onAppear {
            relay.onInviteGenerated = { code, expiresAt in
                generatedCode = code
                codeExpiry = expiresAt
            }
        }
        .onDisappear {
            relay.onInviteGenerated = nil
        }
    }

    // MARK: - Team Members

    private var teamMembersSection: some View {
        Section {
            if relay.teamUsers.isEmpty && isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(MajorTomTheme.Colors.accent)
                    Spacer()
                }
                .listRowBackground(MajorTomTheme.Colors.surface)
            } else if relay.teamUsers.isEmpty {
                Text("No team members found")
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .listRowBackground(MajorTomTheme.Colors.surface)
            } else {
                ForEach(relay.teamUsers) { user in
                    TeamUserRow(user: user, relay: relay, isAdmin: relay.currentUserRole == .admin)
                        .listRowBackground(MajorTomTheme.Colors.surface)
                }
            }
        } header: {
            HStack {
                Text("Team Members")
                Spacer()
                if !relay.teamUsers.isEmpty {
                    let onlineCount = relay.teamUsers.filter(\.isOnline).count
                    Text("\(onlineCount) online")
                        .font(.caption)
                        .foregroundStyle(MajorTomTheme.Colors.allow)
                }
            }
        }
    }

    // MARK: - Invite

    private var inviteSection: some View {
        Section {
            Picker("Role", selection: $selectedRole) {
                ForEach(UserRole.allCases, id: \.self) { role in
                    Text(role.displayName).tag(role)
                }
            }
            .listRowBackground(MajorTomTheme.Colors.surface)

            Button {
                Task {
                    try? await relay.generateInvite(role: selectedRole)
                }
                HapticService.buttonTap()
            } label: {
                Label("Generate Invite Code", systemImage: "person.badge.plus")
            }
            .listRowBackground(MajorTomTheme.Colors.surface)

            if let code = generatedCode {
                VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.sm) {
                    HStack {
                        Text(code)
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(MajorTomTheme.Colors.accent)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = code
                            HapticService.notification(.success)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(MajorTomTheme.Colors.accent)
                        }
                    }
                    if let expiry = codeExpiry {
                        Text("Expires: \(expiry)")
                            .font(.caption)
                            .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    }
                }
                .listRowBackground(MajorTomTheme.Colors.surface)
            }
        } header: {
            Text("Invite")
        }
    }
}

// MARK: - Team User Row

struct TeamUserRow: View {
    let user: TeamUser
    let relay: RelayService
    let isAdmin: Bool

    var body: some View {
        HStack(spacing: MajorTomTheme.Spacing.md) {
            Circle()
                .fill(user.isOnline ? Color.green : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.name ?? user.email)
                    .font(MajorTomTheme.Typography.body)
                    .foregroundStyle(MajorTomTheme.Colors.textPrimary)
                if user.name != nil {
                    Text(user.email)
                        .font(MajorTomTheme.Typography.caption)
                        .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                }
            }

            Spacer()

            if isAdmin {
                NavigationLink {
                    DirectoryPermissionsView(userId: user.id, relay: relay)
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                        .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                        .font(.caption)
                }
            }

            Text(user.role.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(roleColor(user.role).opacity(0.2))
                .foregroundStyle(roleColor(user.role))
                .clipShape(Capsule())
        }
    }

    private func roleColor(_ role: UserRole) -> Color {
        switch role {
        case .admin: return MajorTomTheme.Colors.accent
        case .operator: return MajorTomTheme.Colors.allow
        case .viewer: return MajorTomTheme.Colors.textSecondary
        }
    }
}

#Preview {
    NavigationStack {
        TeamSettingsView(relay: RelayService(), auth: AuthService())
    }
    .preferredColorScheme(.dark)
}
