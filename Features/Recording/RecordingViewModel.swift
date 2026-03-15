import Foundation
import UIKit

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var permissionState: PermissionState = .unknown
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var liveLevel: Double = 0
    @Published private(set) var levelHistory: [Double] = Array(repeating: 0, count: 24)
    @Published private(set) var liveTranscriptSnippet = "FollowUps will transcribe the recording and extract tasks after you stop."
    @Published private(set) var processingMessage = "Preparing recording..."
    @Published private(set) var processingStepIndex = 0
    @Published var reviewSession: CallSession?
    @Published var isShowingError = false
    @Published var errorMessage = ""

    private let audioCaptureService: AudioCaptureServicing
    private let transcriptionService: TranscriptionServicing
    private let actionItemExtractionService: ActionItemExtracting
    private let persistenceService: PersistenceServicing
    private let backgroundTaskService: BackgroundTaskServicing
    private let completionNotificationService: CompletionNotificationServicing
    private weak var appViewModel: AppViewModel?
    private var timer: Timer?
    private var currentSession: CallSession?
    private var processingTask: Task<Void, Never>?
    private var backgroundProcessingToken: ProcessingBackgroundToken?

    init(
        audioCaptureService: AudioCaptureServicing,
        transcriptionService: TranscriptionServicing,
        actionItemExtractionService: ActionItemExtracting,
        persistenceService: PersistenceServicing,
        backgroundTaskService: BackgroundTaskServicing,
        completionNotificationService: CompletionNotificationServicing
    ) {
        self.audioCaptureService = audioCaptureService
        self.transcriptionService = transcriptionService
        self.actionItemExtractionService = actionItemExtractionService
        self.persistenceService = persistenceService
        self.backgroundTaskService = backgroundTaskService
        self.completionNotificationService = completionNotificationService
    }

    func bind(appViewModel: AppViewModel) {
        self.appViewModel = appViewModel
    }

    func startRecording() async {
        let session = CallSession(
            id: UUID(),
            startedAt: .now,
            endedAt: nil,
            status: .recording,
            headline: nil,
            audioFileURL: nil,
            durationSeconds: 0,
            consentConfirmed: true,
            transcript: [],
            summary: nil,
            actionItems: [],
            createdReminderIDs: [],
            debugNotes: []
        )
        currentSession = session

        do {
            permissionState = await audioCaptureService.requestMicrophonePermission()
            guard permissionState == .granted else {
                throw AudioCaptureError.microphonePermissionDenied
            }

            try await transcriptionService.startLiveTranscription(sessionID: session.id)
            try await audioCaptureService.startRecording(sessionID: session.id) { [weak self] buffer, time in
                Task {
                    await self?.transcriptionService.appendAudioBuffer(buffer, when: time)
                    await MainActor.run {
                        self?.liveLevel = self?.audioCaptureService.currentLevel ?? 0
                        self?.liveTranscriptSnippet = self?.transcriptionService.partialText ?? ""
                    }
                }
            }
            state = .recording
            startTimer()
        } catch {
            currentSession = nil
            present(error: error)
        }
    }

    func stopRecording() async {
        guard let session = currentSession else { return }
        processingTask?.cancel()
        state = .stopping
        timer?.invalidate()
        backgroundProcessingToken = backgroundTaskService.beginProcessingWindow()
        Task {
            await completionNotificationService.requestAuthorizationIfNeeded()
        }

        processingTask = Task { [weak self] in
            await self?.runStopPipeline(session: session)
        }
    }

    func cancelRecording() async {
        timer?.invalidate()
        await transcriptionService.stopLiveTranscription()
        await audioCaptureService.cancelRecording()
        currentSession = nil
        state = .idle
        resetRecordingUI()
    }

    func abortProcessing() {
        processingTask?.cancel()
        processingTask = nil
        if let sessionID = currentSession?.id {
            try? persistenceService.deleteSession(id: sessionID)
        }
        currentSession = nil
        state = .idle
        backgroundTaskService.endProcessingWindow(backgroundProcessingToken)
        backgroundProcessingToken = nil
        resetRecordingUI()
    }

    private func runStopPipeline(session: CallSession) async {
        var session = session

        do {
            setProcessingStep(0, message: "Saving the recording")
            let audioURL: URL
            do {
                audioURL = try await audioCaptureService.stopRecording()
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                throw Self.stageError("Could not finish the recording", underlying: error)
            }

            try Task.checkCancellation()
            await transcriptionService.stopLiveTranscription()

            session.endedAt = .now
            session.status = .processing
            session.audioFileURL = audioURL
            session.durationSeconds = Int(elapsedTime)
            session.transcript = []
            session.actionItems = []
            session.debugNotes = []

            do {
                try persistenceService.save(session: session)
            } catch {
                throw Self.stageError("Could not queue the recording for processing", underlying: error)
            }
            currentSession = session

            setProcessingStep(1, message: "Transcribing with OpenAI")
            let transcript: [TranscriptSegment]
            do {
                transcript = try await transcriptionService.finalizeTranscription(for: audioURL)
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                throw Self.stageError("Transcription failed", underlying: error)
            }

            try Task.checkCancellation()
            setProcessingStep(2, message: "Extracting tasks")
            let extractionResult: ExtractedTasksResult
            do {
                extractionResult = try await actionItemExtractionService.extractActionItems(transcript: transcript)
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                throw Self.stageError("Task extraction failed", underlying: error)
            }

            session.endedAt = .now
            session.status = .completed
            session.headline = extractionResult.headline
            session.audioFileURL = audioURL
            session.durationSeconds = Int(elapsedTime)
            session.transcript = transcript
            session.summary = nil
            session.actionItems = extractionResult.items
            session.debugNotes = []

            try Task.checkCancellation()
            do {
                setProcessingStep(3, message: "Saving your session")
                try persistenceService.save(session: session)
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                throw Self.stageError("Could not save the finished session", underlying: error)
            }

            if UIApplication.shared.applicationState == .active {
                reviewSession = session
            } else {
                await completionNotificationService.scheduleProcessingCompleteNotification(for: session)
            }
            currentSession = nil
            state = .ready
            backgroundTaskService.endProcessingWindow(backgroundProcessingToken)
            backgroundProcessingToken = nil
            resetRecordingUI()
            backgroundTaskService.schedulePostProcessing()
            await appViewModel?.load()
            processingTask = nil
        } catch is CancellationError {
            processingTask = nil
            backgroundTaskService.endProcessingWindow(backgroundProcessingToken)
            backgroundProcessingToken = nil
        } catch {
            processingTask = nil
            if var failedSession = currentSession {
                failedSession.status = .failed
                failedSession.debugNotes.append(error.localizedDescription)
                try? persistenceService.save(session: failedSession)
                await appViewModel?.load()
            }
            backgroundTaskService.endProcessingWindow(backgroundProcessingToken)
            backgroundProcessingToken = nil
            present(error: error)
        }
    }

    func presentReviewSession(_ session: CallSession) {
        reviewSession = session
        state = .ready
    }

    private func startTimer() {
        elapsedTime = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsedTime += 0.25
            self.liveLevel = self.audioCaptureService.currentLevel
            self.pushLevelSample(self.liveLevel)
            self.liveTranscriptSnippet = self.transcriptionService.partialText.isEmpty
                ? "Recording now. OpenAI will transcribe and extract tasks after you stop."
                : self.transcriptionService.partialText
        }
    }

    private func pushLevelSample(_ level: Double) {
        let boosted = min(pow(max(level, 0), 0.42) * 1.6, 1)
        let filtered = boosted < 0.018 ? 0 : boosted
        let smoothed = ((levelHistory.last ?? 0) * 0.35) + (filtered * 0.65)
        levelHistory.append(smoothed)
        if levelHistory.count > 24 {
            levelHistory.removeFirst(levelHistory.count - 24)
        }
    }

    private func resetRecordingUI() {
        elapsedTime = 0
        liveLevel = 0
        levelHistory = Array(repeating: 0, count: 24)
        liveTranscriptSnippet = "FollowUps will transcribe the recording and extract tasks after you stop."
        processingMessage = "Preparing recording..."
        processingStepIndex = 0
    }

    var processingSteps: [String] {
        [
            "Saving the recording",
            "Transcribing with OpenAI",
            "Extracting tasks",
            "Saving your session"
        ]
    }

    private func present(error: Error) {
        processingTask = nil
        backgroundTaskService.endProcessingWindow(backgroundProcessingToken)
        backgroundProcessingToken = nil
        state = .failed(error.localizedDescription)
        errorMessage = error.localizedDescription
        isShowingError = true
    }

    private func setProcessingStep(_ index: Int, message: String) {
        processingStepIndex = index
        processingMessage = message
    }

    private static func stageError(_ stage: String, underlying: Error) -> NSError {
        NSError(
            domain: "CallNotes.RecordingPipeline",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "\(stage). \(underlying.localizedDescription)"
            ]
        )
    }
}
