import AppIntents
import Foundation

struct StartFollowUpsIntent: AppIntent {
    static let title: LocalizedStringResource = "Start FollowUps"
    static let description = IntentDescription("Open FollowUps and start a recording session.")

    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(URL(string: "followups://record/start")!))
    }
}

struct StopFollowUpsIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop FollowUps"
    static let description = IntentDescription("Open FollowUps and stop the active recording session.")

    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(URL(string: "followups://record/stop")!))
    }
}

struct FollowUpsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartFollowUpsIntent(),
            phrases: [
                "Start FollowUps in \(.applicationName)",
                "Start recording in \(.applicationName)"
            ],
            shortTitle: "Start Recording",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: StopFollowUpsIntent(),
            phrases: [
                "Stop FollowUps in \(.applicationName)"
            ],
            shortTitle: "Stop Recording",
            systemImageName: "stop.fill"
        )
    }
}
