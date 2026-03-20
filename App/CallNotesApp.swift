import SwiftUI

@main
struct FollowUpsApp: App {
    @StateObject private var container = DependencyContainer.bootstrap()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(container.appViewModel)
                .environmentObject(container.recordingViewModel)
                .task {
                    await container.bootstrap()
                }
                .onOpenURL { url in
                    Task {
                        await container.handle(url: url)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task { @MainActor in
                        container.refreshPendingReviewSessionFromNotifications()
                        await container.appViewModel.resumePendingSessions()
                    }
                }
        }
    }
}
