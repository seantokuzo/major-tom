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
        do {
            try await relay.requestDeviceList()
        } catch {
            // Error handled by relay service
        }
    }

    func revokeDevice(id: String) async {
        do {
            try await relay.revokeDevice(id: id)
            devices.removeAll { $0.id == id }
            HapticService.notification(.success)
        } catch {
            HapticService.notification(.error)
        }
    }

    func updateDevices(_ newDevices: [DeviceInfo]) {
        devices = newDevices
        isLoadingDevices = false
    }
}
