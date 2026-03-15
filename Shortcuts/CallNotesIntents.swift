import AppIntents
import Foundation

struct StartCallNotesIntent: AppIntent {
    static let title: LocalizedStringResource = "Start FollowUps"
    static let description = IntentDescription("Open FollowUps and start a recording session.")

    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(URL(string: "callnotes://record/start")!))
    }
}

struct StopCallNotesIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop FollowUps"
    static let description = IntentDescription("Open FollowUps and stop the active recording session.")

    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(URL(string: "callnotes://record/stop")!))
    }
}

struct CallNotesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartCallNotesIntent(),
            phrases: [
                "Start FollowUps in \(.applicationName)",
                "Start recording in \(.applicationName)"
            ]
        )
        AppShortcut(
            intent: StopCallNotesIntent(),
            phrases: [
                "Stop FollowUps in \(.applicationName)"
            ]
        )
    }
}
