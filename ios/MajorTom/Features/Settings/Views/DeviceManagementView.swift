import SwiftUI

struct DeviceManagementView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        List {
            if viewModel.isLoadingDevices {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(MajorTomTheme.Colors.surface)
            } else if viewModel.devices.isEmpty {
                Text("No paired devices")
                    .foregroundStyle(MajorTomTheme.Colors.textSecondary)
                    .listRowBackground(MajorTomTheme.Colors.surface)
            } else {
                ForEach(viewModel.devices) { device in
                    deviceRow(device)
                        .listRowBackground(MajorTomTheme.Colors.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(MajorTomTheme.Colors.background)
        .navigationTitle("Paired Devices")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.requestDeviceList()
        }
    }

    private func deviceRow(_ device: DeviceInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: MajorTomTheme.Spacing.xs) {
                HStack(spacing: MajorTomTheme.Spacing.sm) {
                    Image(systemName: device.id == viewModel.deviceId ? "iphone" : "desktopcomputer")
                        .foregroundStyle(MajorTomTheme.Colors.accent)
                    Text(device.name)
                        .font(MajorTomTheme.Typography.body)
                        .foregroundStyle(MajorTomTheme.Colors.textPrimary)

                    if device.id == viewModel.deviceId {
                        Text("This device")
                            .font(MajorTomTheme.Typography.caption)
                            .foregroundStyle(MajorTomTheme.Colors.accent)
                            .padding(.horizontal, MajorTomTheme.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(MajorTomTheme.Colors.accentSubtle)
                            .clipShape(Capsule())
                    }
                }

                Text("Last seen: \(formatDate(device.lastSeenAt))")
                    .font(MajorTomTheme.Typography.caption)
                    .foregroundStyle(MajorTomTheme.Colors.textTertiary)
            }

            Spacer()

            if device.id != viewModel.deviceId {
                Button {
                    Task { await viewModel.revokeDevice(id: device.id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MajorTomTheme.Colors.deny)
                }
            }
        }
    }

    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return isoString }

        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}
