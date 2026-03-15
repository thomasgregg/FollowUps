import Foundation
import UIKit
import UserNotifications

final class CompletionNotificationService: CompletionNotificationServicing {
    private let center = UNUserNotificationCenter.current()
    private let openedSessionDefaultsKey = "completion_notification_opened_session_id"

    func register() {}

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
        "processing-complete-\(sessionID.uuidString)"
    }
}
