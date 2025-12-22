import Foundation

/// Observer for quota status changes (e.g., for system notifications).
/// Views observe providers directly via @Observable - this is for external notifications.
public protocol StatusChangeObserver: Sendable {
    /// Called when a quota status changes (e.g., from healthy to warning)
    func onStatusChanged(providerId: String, oldStatus: QuotaStatus, newStatus: QuotaStatus) async
}
