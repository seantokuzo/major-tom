import Foundation
import WatchKit

// MARK: - Approval View Model

@Observable
@MainActor
final class ApprovalViewModel {
    let connectivity: WatchConnectivityService
    var currentIndex: Int = 0

    init(connectivity: WatchConnectivityService) {
        self.connectivity = connectivity
    }

    // MARK: - Computed

    var pendingApprovals: [WatchApprovalRequest] {
        connectivity.pendingApprovals
    }

    var currentRequest: WatchApprovalRequest? {
        guard currentIndex < pendingApprovals.count else { return nil }
        return pendingApprovals[currentIndex]
    }

    var hasMultiple: Bool {
        pendingApprovals.count > 1
    }

    var remainingCount: Int {
        max(0, pendingApprovals.count - currentIndex - 1)
    }

    var currentPosition: String {
        "\(currentIndex + 1) of \(pendingApprovals.count)"
    }

    // MARK: - Actions

    func approve() {
        guard let request = currentRequest else { return }
        connectivity.sendApprovalDecision(requestId: request.id, approved: true)
        WKInterfaceDevice.current().play(.success)
        advanceToNext()
    }

    func deny() {
        guard let request = currentRequest else { return }
        connectivity.sendApprovalDecision(requestId: request.id, approved: false)
        WKInterfaceDevice.current().play(.failure)
        advanceToNext()
    }

    func advanceToNext() {
        // After optimistic removal the list already shrunk, so just clamp
        // currentIndex to stay in bounds (the next item slid into position).
        if pendingApprovals.isEmpty {
            currentIndex = 0
        } else if currentIndex >= pendingApprovals.count {
            currentIndex = 0
        }
        // Otherwise currentIndex already points at the next item.
    }
}
