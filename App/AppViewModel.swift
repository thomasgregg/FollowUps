import Foundation

enum AppTab: Hashable {
    case record
    case sessions
    case settings
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published private(set) var sessions: [CallSession] = []
    @Published var settings = AppSettings()
    @Published var selectedTab: AppTab = .record
    @Published var pendingReviewSessionID: UUID?

    private let persistenceService: PersistenceServicing
    private let reminderService: ReminderServicing
    private let transcriptionService: TranscriptionServicing
    private let actionItemExtractionService: ActionItemExtracting
    private var processingSessionIDs: Set<UUID> = []

    init(
        persistenceService: PersistenceServicing,
        reminderService: ReminderServicing,
        transcriptionService: TranscriptionServicing,
        actionItemExtractionService: ActionItemExtracting
    ) {
        self.persistenceService = persistenceService
        self.reminderService = reminderService
        self.transcriptionService = transcriptionService
        self.actionItemExtractionService = actionItemExtractionService
    }

    func load() async {
        settings = persistenceService.loadSettings()
        if settings.retentionCleanupEnabled {
            try? persistenceService.purgeExpiredSessions(retentionDays: settings.retentionDays)
        }
        sessions = (try? persistenceService.fetchSessions()) ?? []
    }

    func save(settings: AppSettings) {
        self.settings = settings
        persistenceService.save(settings: settings)
        if settings.retentionCleanupEnabled {
            try? persistenceService.purgeExpiredSessions(retentionDays: settings.retentionDays)
        }
        refreshSessions()
    }

    func deleteAllSessions() {
        try? persistenceService.deleteAllSessions()
        sessions = []
    }

    func deleteSession(id: UUID) {
        try? persistenceService.deleteSession(id: id)
        sessions.removeAll { $0.id == id }
    }

    func refreshSessions() {
        sessions = (try? persistenceService.fetchSessions()) ?? []
    }

    func resumePendingSessions() async {
        refreshSessions()
        let pendingSessions = sessions.filter {
            $0.status == .processing && $0.audioFileURL != nil && !processingSessionIDs.contains($0.id)
        }

        for session in pendingSessions {
            processingSessionIDs.insert(session.id)
            await processPendingSession(session)
            processingSessionIDs.remove(session.id)
        }
    }

    func resolvedAudioURL(for session: CallSession) -> URL? {
        let candidateURLs = [session.audioFileURL, persistenceService.audioFileURL(for: session.id)]
            .compactMap { $0 }

        return candidateURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    func saveSelectedReminders(for sessionID: UUID, items: [ActionItem]) async throws -> ReminderSyncResult {
        let granted = try await reminderService.requestAccess()
        guard granted else {
            throw ReminderError.accessDenied
        }

        let syncResult = try await reminderService.sync(actionItems: items)
        guard let session = sessions.first(where: { $0.id == sessionID }) ?? (try? persistenceService.fetchSessions().first(where: { $0.id == sessionID })) else {
            throw ReminderError.saveFailed
        }

        var updatedSession = session
        updatedSession.actionItems = syncResult.items
        updatedSession.createdReminderIDs = updatedSession.actionItems.compactMap(\.linkedReminderID)
        try persistenceService.save(session: updatedSession)
        refreshSessions()
        return ReminderSyncResult(
            items: updatedSession.actionItems,
            createdCount: syncResult.createdCount,
            updatedCount: syncResult.updatedCount,
            removedCount: syncResult.removedCount,
            unchangedCount: syncResult.unchangedCount
        )
    }

    private func processPendingSession(_ session: CallSession) async {
        guard let audioURL = resolvedAudioURL(for: session) else {
            var failedSession = session
            failedSession.status = .failed
            failedSession.debugNotes.append("Could not resume processing because the recording file was missing.")
            try? persistenceService.save(session: failedSession)
            refreshSessions()
            return
        }

        do {
            let transcript = try await transcriptionService.finalizeTranscription(for: audioURL)
            let extractionResult = try await actionItemExtractionService.extractActionItems(transcript: transcript)

            var completedSession = session
            completedSession.status = .completed
            completedSession.transcript = transcript
            completedSession.actionItems = extractionResult.items
            completedSession.headline = extractionResult.headline
            try persistenceService.save(session: completedSession)
        } catch {
            var failedSession = session
            failedSession.status = .failed
            failedSession.debugNotes.append("Resume processing failed: \(error.localizedDescription)")
            try? persistenceService.save(session: failedSession)
        }

        refreshSessions()
    }
}
