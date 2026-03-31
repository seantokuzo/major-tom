import SwiftUI

struct AuditLogView: View {
    private let relay: RelayService
    @State private var isLoading = false
    @State private var actionFilter: String = ""
    @State private var timeRange: TimeRange = .day

    enum TimeRange: String, CaseIterable {
        case hour = "Last Hour"
        case day = "Last 24h"
        case week = "Last 7 Days"
        case all = "All Time"

        var startTime: String? {
            let now = Date()
            switch self {
            case .hour:
                return ISO8601DateFormatter().string(from: now.addingTimeInterval(-3600))
            case .day:
                return ISO8601DateFormatter().string(from: now.addingTimeInterval(-86400))
            case .week:
                return ISO8601DateFormatter().string(from: now.addingTimeInterval(-604800))
            case .all:
                return nil
            }
        }
    }

    init(relay: RelayService) {
        self.relay = relay
    }

    private var uniqueActions: [String] {
        Array(Set(relay.auditEntries.map(\.action))).sorted()
    }

    private var filteredEntries: [AuditEntryData] {
        if actionFilter.isEmpty {
            return relay.auditEntries
        }
        return relay.auditEntries.filter { $0.action == actionFilter }
    }

    var body: some View {
        List {
            filterSection

            if filteredEntries.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No Audit Entries",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Actions will be recorded here")
                )
                .listRowBackground(Color.clear)
            } else if filteredEntries.isEmpty && isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(MajorTomTheme.Colors.accent)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredEntries) { entry in
                    AuditEntryRow(entry: entry)
                        .listRowBackground(MajorTomTheme.Colors.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(MajorTomTheme.Colors.background)
        .navigationTitle("Audit Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await fetchEntries() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            await fetchEntries()
        }
        .onChange(of: timeRange) {
            Task { await fetchEntries() }
        }
    }

    private var filterSection: some View {
        Section {
            Picker("Time Range", selection: $timeRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .listRowBackground(MajorTomTheme.Colors.surface)

            Picker("Action", selection: $actionFilter) {
                Text("All Actions").tag("")
                ForEach(uniqueActions, id: \.self) { action in
                    Text(action).tag(action)
                }
            }
            .listRowBackground(MajorTomTheme.Colors.surface)
        } header: {
            Text("Filters")
        }
    }

    private func fetchEntries() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let counterBefore = relay.responseCounter
            try await relay.queryAudit(
                startTime: timeRange.startTime,
                action: actionFilter.isEmpty ? nil : actionFilter,
                limit: 200
            )
            for _ in 0..<40 {
                if Task.isCancelled { break }
                if relay.responseCounter != counterBefore { break }
                try await Task.sleep(for: .milliseconds(50))
            }
        } catch {
            // Silently handle — entries may still arrive
        }
    }
}

// MARK: - Audit Entry Row

struct AuditEntryRow: View {
    let entry: AuditEntryData

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.action)
                    .font(MajorTomTheme.Typography.codeFont)
                    .fontWeight(.bold)
                    .foregroundStyle(actionColor)

                Spacer()

                Text(relativeTime)
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }

            HStack(spacing: 8) {
                Text(entry.email)
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .lineLimit(1)

                Text(entry.role.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(MajorTomTheme.Colors.surface)
                    .clipShape(Capsule())
            }

            if let sessionId = entry.sessionId {
                Text(String(sessionId.prefix(8)))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(MajorTomTheme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            if let details = entry.details, !details.isEmpty {
                Text(details)
                    .font(MajorTomTheme.Typography.codeFontSmall)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var actionColor: Color {
        if entry.action.contains("approve") || entry.action.contains("allow") {
            return MajorTomTheme.Colors.allow
        }
        if entry.action.contains("deny") || entry.action.contains("revoke") {
            return MajorTomTheme.Colors.deny
        }
        if entry.action.contains("prompt") {
            return MajorTomTheme.Colors.accent
        }
        if entry.action.contains("login") || entry.action.contains("auth") {
            return .purple
        }
        if entry.action.contains("session") {
            return .blue
        }
        return MajorTomTheme.Colors.textSecondary
    }

    private var relativeTime: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: entry.timestamp) else { return entry.timestamp }
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        return "\(Int(diff / 86400))d ago"
    }
}

#Preview {
    NavigationStack {
        AuditLogView(relay: RelayService())
    }
}
