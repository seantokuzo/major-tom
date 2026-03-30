import Foundation

@Observable
@MainActor
final class SettingsViewModel {
    var showDeviceManagement = false
    var showUnpairConfirmation = false
    var devices: [DeviceInfo] = []
    var isLoadingDevices = false

    private let auth: AuthService
    private let relay: RelayService

    init(auth: AuthService, relay: RelayService) {
        self.auth = auth
        self.relay = relay
        // Wire up device list updates from relay
        relay.onDeviceListUpdate = { [weak self] devices in
            Task { @MainActor [weak self] in
                self?.updateDevices(devices)
            }
        }
    }

    var serverURL: String { auth.serverURL }
    var isPaired: Bool { auth.isPaired }
    var deviceName: String { auth.deviceName }
    var deviceId: String? { auth.deviceId }
    var connectionState: ConnectionState { relay.connectionState }

    var sessionCount: Int {
        relay.currentSession != nil ? 1 : 0
    }

    var currentSessionId: String? {
        relay.currentSession?.id
    }

    func unpair() {
        auth.unpair()
        relay.disconnect()
        HapticService.notification(.warning)
    }

    func requestDeviceList() async {
        isLoadingDevices = true
        defer { isLoadingDevices = false }

        do {
            let counterBefore = relay.responseCounter
            try await relay.requestDeviceList()
            // Poll until the relay response arrives (responseCounter changes).
            // Respects task cancellation so the loop stops when the view disappears.
            for _ in 0..<40 {
                if Task.isCancelled { break }
                if relay.responseCounter != counterBefore { break }
                try await Task.sleep(for: .milliseconds(50))
            }
        } catch {
            // Silently fail — device list will just not update (includes CancellationError)
        }
    }

    func revokeDevice(id: String) async {
        do {
            try await relay.revokeDevice(id: id)
            devices.removeAll { $0.id == id }
            HapticService.notification(.success)
            // Refresh the device list from server to ensure fresh data
            await requestDeviceList()
        } catch {
            HapticService.notification(.error)
        }
    }

    func updateDevices(_ newDevices: [DeviceInfo]) {
        devices = newDevices
        isLoadingDevices = false
    }
}
