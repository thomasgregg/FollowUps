import Foundation
import UIKit
import UserNotifications

final class CompletionNotificationService: CompletionNotificationServicing {
    private let center = UNUserNotificationCenter.current()
    private let openedSessionDefaultsKey = "completion_notification_opened_session_id"
    private let processingNotificationPrefix = "processing-complete-"

    func register() {
        Task {
            await clearStaleNotifications()
        }
    }

    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func scheduleProcessingCompleteNotification(for session: CallSession) async {
        let applicationState = await MainActor.run { UIApplication.shared.applicationState }
        guard applicationState != .active else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        UserDefaults.standard.set(session.id.uuidString, forKey: openedSessionDefaultsKey)

        let content = UNMutableNotificationContent()
        content.title = "Tasks are ready"
        content.body = session.headline ?? "Review this call and update Apple Reminders."
        content.sound = .default
        content.userInfo = ["sessionID": session.id.uuidString]

        let request = UNNotificationRequest(
            identifier: notificationIdentifier(for: session.id),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await center.add(request)
    }

    func clearProcessingCompleteNotification(for sessionID: UUID) {
        let identifier = notificationIdentifier(for: sessionID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func consumePendingOpenedSessionID() -> UUID? {
        guard
            let rawValue = UserDefaults.standard.string(forKey: openedSessionDefaultsKey),
            let sessionID = UUID(uuidString: rawValue)
        else { return nil }

        UserDefaults.standard.removeObject(forKey: openedSessionDefaultsKey)
        return sessionID
    }

    private func notificationIdentifier(for sessionID: UUID) -> String {
        "\(processingNotificationPrefix)\(sessionID.uuidString)"
    }

    private func clearStaleNotifications() async {
        let pendingRequests = await pendingNotificationRequests()
        let pendingLegacyIDs = pendingRequests
            .filter { shouldRemoveNotificationRequest($0) }
            .map(\.identifier)
        if !pendingLegacyIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: pendingLegacyIDs)
        }

        let deliveredNotifications = await deliveredNotifications()
        let deliveredLegacyIDs = deliveredNotifications
            .filter { shouldRemoveNotificationRequest($0.request) }
            .map { $0.request.identifier }
        if !deliveredLegacyIDs.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: deliveredLegacyIDs)
        }
    }

    private func shouldRemoveNotificationRequest(_ request: UNNotificationRequest) -> Bool {
        // Keep only current-session processing notifications.
        guard !request.identifier.hasPrefix(processingNotificationPrefix) else { return false }

        let identifier = request.identifier.lowercased()
        if identifier.contains("callnotes") || identifier.contains("call-notes") {
            return true
        }
        if identifier.contains("call") && identifier.contains("reminder") {
            return true
        }

        let content = "\(request.content.title) \(request.content.body)".lowercased()
        if content.contains("start call notes") || content.contains("about to jump on a call") {
            return true
        }
        if content.contains("callnotes") {
            return true
        }

        // Remove any other non-current notifications left behind by older builds.
        return true
    }

    private func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    private func deliveredNotifications() async -> [UNNotification] {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications)
            }
        }
    }
}
