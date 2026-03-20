import AVFoundation
import Foundation
import UserNotifications

enum AudioCaptureError: Error, LocalizedError {
    case microphonePermissionDenied
    case sessionConfigurationFailed
    case unableToCreateFile
    case alreadyRecording
    case notRecording
    case interruption

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Microphone access is required to record with FollowUps."
        case .sessionConfigurationFailed:
            "FollowUps could not configure the audio session."
        case .unableToCreateFile:
            "FollowUps could not create an audio file."
        case .alreadyRecording:
            "A recording is already in progress."
        case .notRecording:
            "There is no recording to stop."
        case .interruption:
            "Recording was interrupted by the system."
        }
    }
}

enum TranscriptionError: Error, LocalizedError {
    case processingUnavailable
    case finalizationFailed
    case missingAPIKey
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .processingUnavailable:
            "OpenAI processing is not available right now."
        case .finalizationFailed:
            "FollowUps could not finalize the transcript."
        case .missingAPIKey:
            "Add your OpenAI API key in Settings before you start recording."
        case .invalidResponse:
            "FollowUps received an unreadable transcription response."
        }
    }
}

enum ReminderError: Error, LocalizedError {
    case accessDenied
    case noWritableCalendar
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Enable Reminders access for FollowUps to save tasks."
        case .noWritableCalendar:
            "No writable Reminders list is available on this device."
        case .saveFailed:
            "FollowUps couldn't save the selected tasks to Reminders."
        }
    }
}

struct ReminderSyncResult: Equatable {
    var items: [ActionItem]
    var createdCount: Int
    var updatedCount: Int
    var removedCount: Int
    var unchangedCount: Int

    var changedCount: Int {
        createdCount + updatedCount + removedCount
    }
}

struct ProcessingBackgroundToken: Hashable {
    let id: UUID
}

enum ActionItemExtractionError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your OpenAI API key in Settings before extracting tasks."
        case .invalidResponse:
            "FollowUps received unreadable tasks from OpenAI."
        case .emptyTranscript:
            "There was not enough transcript text to extract tasks."
        }
    }
}

struct ExtractedTasksResult: Equatable {
    let headline: String?
    let items: [ActionItem]
}

protocol AudioCaptureServicing: AnyObject {
    var currentLevel: Double { get }
    var currentAudioFileURL: URL? { get }
    var recordingState: RecordingState { get }
    var debugStatusLines: [String] { get }
    func requestMicrophonePermission() async -> PermissionState
    func startRecording(sessionID: UUID, onBuffer: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime?) -> Void) async throws
    func stopRecording() async throws -> URL
    func cancelRecording() async
}

protocol TranscriptionServicing: AnyObject {
    var partialText: String { get }
    func isConfigured() async -> Bool
    func startLiveTranscription(sessionID: UUID) async throws
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer, when: AVAudioTime?) async
    func stopLiveTranscription() async
    func finalizeTranscription(for audioURL: URL) async throws -> [TranscriptSegment]
}

protocol ActionItemExtracting {
    func extractActionItems(transcript: [TranscriptSegment]) async throws -> ExtractedTasksResult
}

protocol ReminderServicing {
    func requestAccess() async throws -> Bool
    func sync(actionItems: [ActionItem]) async throws -> ReminderSyncResult
}

@MainActor
protocol BackgroundTaskServicing {
    func register()
    func schedulePostProcessing()
    func beginProcessingWindow() -> ProcessingBackgroundToken?
    func endProcessingWindow(_ token: ProcessingBackgroundToken?)
}

protocol CompletionNotificationServicing: AnyObject {
    func register()
    func requestAuthorizationIfNeeded() async
    func scheduleProcessingCompleteNotification(for session: CallSession) async
    func clearProcessingCompleteNotification(for sessionID: UUID)
    func consumePendingOpenedSessionID() -> UUID?
}

protocol PersistenceServicing {
    func fetchSessions() throws -> [CallSession]
    func save(session: CallSession) throws
    func purgeExpiredSessions(retentionDays: Int) throws
    func deleteSession(id: UUID) throws
    func deleteAllSessions() throws
    func loadSettings() -> AppSettings
    func save(settings: AppSettings)
    func audioFileURL(for sessionID: UUID) -> URL
}
