import BackgroundTasks
import Foundation
import UIKit

@MainActor
final class BackgroundTaskService: BackgroundTaskServicing {
    private let processingIdentifier = "com.thomasgregg.FollowUps.postprocess"
    private var activeTokens: [UUID: UIBackgroundTaskIdentifier] = [:]

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: processingIdentifier, using: nil) { task in
            task.expirationHandler = {
                task.setTaskCompleted(success: false)
            }
            task.setTaskCompleted(success: true)
        }
    }

    func schedulePostProcessing() {
        let request = BGProcessingTaskRequest(identifier: processingIdentifier)
        request.requiresExternalPower = false
        request.requiresNetworkConnectivity = false
        try? BGTaskScheduler.shared.submit(request)
    }

    func beginProcessingWindow() -> ProcessingBackgroundToken? {
        let token = ProcessingBackgroundToken(id: UUID())
        let taskID = UIApplication.shared.beginBackgroundTask(withName: "FollowUpsProcessing") { [weak self] in
            Task { @MainActor in
                self?.endProcessingWindow(token)
            }
        }

        guard taskID != .invalid else { return nil }
        activeTokens[token.id] = taskID
        return token
    }

    func endProcessingWindow(_ token: ProcessingBackgroundToken?) {
        guard let token, let taskID = activeTokens.removeValue(forKey: token.id) else { return }
        UIApplication.shared.endBackgroundTask(taskID)
    }
}
