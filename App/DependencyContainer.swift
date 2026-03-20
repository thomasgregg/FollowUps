import Foundation

@MainActor
final class DependencyContainer: ObservableObject {
    let persistenceService: PersistenceServicing
    let audioCaptureService: AudioCaptureServicing
    let transcriptionService: TranscriptionServicing
    let actionItemExtractionService: ActionItemExtracting
    let reminderService: ReminderServicing
    let backgroundTaskService: BackgroundTaskServicing
    let completionNotificationService: CompletionNotificationServicing
    let appViewModel: AppViewModel
    let recordingViewModel: RecordingViewModel

    init(
        persistenceService: PersistenceServicing,
        audioCaptureService: AudioCaptureServicing,
        transcriptionService: TranscriptionServicing,
        actionItemExtractionService: ActionItemExtracting,
        reminderService: ReminderServicing,
        backgroundTaskService: BackgroundTaskServicing,
        completionNotificationService: CompletionNotificationServicing
    ) {
        self.persistenceService = persistenceService
        self.audioCaptureService = audioCaptureService
        self.transcriptionService = transcriptionService
        self.actionItemExtractionService = actionItemExtractionService
        self.reminderService = reminderService
        self.backgroundTaskService = backgroundTaskService
        self.completionNotificationService = completionNotificationService
        self.appViewModel = AppViewModel(
            persistenceService: persistenceService,
            reminderService: reminderService,
            transcriptionService: transcriptionService,
            actionItemExtractionService: actionItemExtractionService
        )
        self.recordingViewModel = RecordingViewModel(
            audioCaptureService: audioCaptureService,
            transcriptionService: transcriptionService,
            actionItemExtractionService: actionItemExtractionService,
            persistenceService: persistenceService,
            backgroundTaskService: backgroundTaskService,
            completionNotificationService: completionNotificationService
        )
    }

    static func bootstrap() -> DependencyContainer {
        let persistence = PersistenceService()
        let audio = AudioCaptureService()
        let openAIClient = OpenAIClient(persistenceService: persistence)
        let transcription = TranscriptionService(client: openAIClient)
        let extractor = ActionItemExtractionService(client: openAIClient)
        let reminders = ReminderService()
        let background = BackgroundTaskService()
        let notifications = CompletionNotificationService()
        return DependencyContainer(
            persistenceService: persistence,
            audioCaptureService: audio,
            transcriptionService: transcription,
            actionItemExtractionService: extractor,
            reminderService: reminders,
            backgroundTaskService: background,
            completionNotificationService: notifications
        )
    }

    func bootstrap() async {
        backgroundTaskService.register()
        completionNotificationService.register()
        refreshPendingReviewSessionFromNotifications()
        await appViewModel.load()
        await appViewModel.resumePendingSessions()
        recordingViewModel.bind(appViewModel: appViewModel)
    }

    func handle(url: URL) async {
        switch url.host {
        case "record":
            appViewModel.selectedTab = .record
            switch url.path {
            case "/start":
                await recordingViewModel.startRecording()
            case "/stop":
                await recordingViewModel.stopRecording()
                await appViewModel.load()
            default:
                break
            }
        default:
            break
        }
    }

    func refreshPendingReviewSessionFromNotifications() {
        if let sessionID = completionNotificationService.consumePendingOpenedSessionID() {
            appViewModel.selectedTab = .record
            appViewModel.pendingReviewSessionID = sessionID
        }
    }

    func presentPendingReviewSessionIfNeeded() async {
        refreshPendingReviewSessionFromNotifications()
        guard let sessionID = appViewModel.pendingReviewSessionID else { return }
        await appViewModel.load()
        guard let session = appViewModel.sessions.first(where: { $0.id == sessionID }) else { return }
        appViewModel.selectedTab = .record
        recordingViewModel.presentReviewSession(session)
        appViewModel.pendingReviewSessionID = nil
    }
}
