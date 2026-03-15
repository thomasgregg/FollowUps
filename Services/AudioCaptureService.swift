import AVFoundation
import Foundation

final class AudioCaptureService: NSObject, AudioCaptureServicing {
    private let session = AVAudioSession.sharedInstance()
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?
    private var levelTimer: Timer?
    private var debugLines: [String] = []
    private(set) var currentLevel: Double = 0
    private(set) var recordingState: RecordingState = .idle

    var currentAudioFileURL: URL? { outputURL }
    var debugStatusLines: [String] { debugLines }

    func requestMicrophonePermission() async -> PermissionState {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    self.refreshDebugStatus(extra: "Mic permission: \(granted ? "granted" : "denied")")
                    continuation.resume(returning: granted ? .granted : .denied)
                }
            } else {
                session.requestRecordPermission { granted in
                    self.refreshDebugStatus(extra: "Mic permission: \(granted ? "granted" : "denied")")
                    continuation.resume(returning: granted ? .granted : .denied)
                }
            }
        }
    }

    func startRecording(
        sessionID: UUID,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime?) -> Void
    ) async throws {
        guard case .recording = recordingState else {
            recordingState = .requestingPermission
            let permission = await requestMicrophonePermission()
            guard permission == .granted else {
                recordingState = .failed(AudioCaptureError.microphonePermissionDenied.localizedDescription)
                throw AudioCaptureError.microphonePermissionDenied
            }

            let persistence = PersistenceService()
            let fileURL = persistence.audioFileURL(for: sessionID)

            do {
                try configureRecordingSession()

                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: session.sampleRate > 0 ? session.sampleRate : 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                    AVEncoderBitRateKey: 128_000
                ]

                let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
                recorder.isMeteringEnabled = true
                recorder.prepareToRecord()

                guard recorder.record() else {
                    throw AudioCaptureError.sessionConfigurationFailed
                }

                self.recorder = recorder
                self.outputURL = fileURL
                refreshDebugStatus(extra: "Recorder started")
                startMetering()
                _ = onBuffer
            } catch {
                refreshDebugStatus(extra: "Start failed: \(error.localizedDescription)")
                recordingState = .failed(error.localizedDescription)
                throw error
            }

            recordingState = .recording
            return
        }

        throw AudioCaptureError.alreadyRecording
    }

    func stopRecording() async throws -> URL {
        guard case .recording = recordingState else {
            throw AudioCaptureError.notRecording
        }

        recordingState = .stopping
        levelTimer?.invalidate()
        recorder?.stop()
        try session.setActive(false, options: .notifyOthersOnDeactivation)
        recordingState = .ready
        refreshDebugStatus(extra: "Recorder stopped")

        guard let outputURL else {
            throw AudioCaptureError.unableToCreateFile
        }

        recorder = nil
        self.outputURL = nil
        currentLevel = 0
        return outputURL
    }

    func cancelRecording() async {
        levelTimer?.invalidate()
        recorder?.stop()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        recorder = nil
        outputURL = nil
        currentLevel = 0
        recordingState = .idle
        refreshDebugStatus(extra: "Recording cancelled")
    }

    private func startMetering() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self, let recorder else { return }
            recorder.updateMeters()
            let peakPower = recorder.peakPower(forChannel: 0)
            let floor: Float = -55
            let clamped = max(peakPower, floor)
            let normalized = (clamped - floor) / abs(floor)
            self.currentLevel = Double(max(0, min(1, normalized)))
            self.refreshDebugStatus(extra: String(format: "Peak: %.1f dB | Level: %.3f", peakPower, self.currentLevel))
        }
    }

    private func configureRecordingSession() throws {
        let configurations: [(AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)] = [
            (.playAndRecord, .spokenAudio, [.defaultToSpeaker, .allowBluetoothHFP]),
            (.playAndRecord, .default, [.defaultToSpeaker]),
            (.record, .default, [])
        ]

        var lastError: Error?

        for (category, mode, options) in configurations {
            do {
                try session.setCategory(category, mode: mode, options: options)

                // These preferences improve quality but are not required for recording to work.
                try? session.setPreferredSampleRate(44_100)
                try? session.setPreferredInputNumberOfChannels(1)

                try session.setActive(true)
                refreshDebugStatus(extra: "Audio session ready: \(category.rawValue) / \(mode.rawValue)")
                return
            } catch {
                lastError = error
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                refreshDebugStatus(extra: "Audio session fallback failed: \(category.rawValue) / \(mode.rawValue) - \(error.localizedDescription)")
            }
        }

        let message = lastError?.localizedDescription ?? AudioCaptureError.sessionConfigurationFailed.localizedDescription
        throw NSError(
            domain: "CallNotes.AudioCapture",
            code: 1001,
            userInfo: [NSLocalizedDescriptionKey: "CallNotes could not configure the audio session. \(message)"]
        )
    }

    private func refreshDebugStatus(extra: String? = nil) {
        let routeInputs = session.currentRoute.inputs.map { "\($0.portType.rawValue)(\($0.portName))" }.joined(separator: ", ")
        let routeOutputs = session.currentRoute.outputs.map { "\($0.portType.rawValue)(\($0.portName))" }.joined(separator: ", ")
        let availableInputs = (session.availableInputs ?? []).map { "\($0.portType.rawValue)(\($0.portName))" }.joined(separator: ", ")
        let preferredInput = session.preferredInput.map { "\($0.portType.rawValue)(\($0.portName))" } ?? "none"
        let recorderState = recorder == nil ? "nil" : "exists"
        let isRecording = recorder?.isRecording == true ? "true" : "false"
        let url = outputURL?.lastPathComponent ?? "none"
        let fileSize = outputURL.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } ?? 0

        var lines = [
            "Recorder object: \(recorderState) | isRecording: \(isRecording)",
            String(format: "Sample rate: %.0f | Input channels: %d", session.sampleRate, session.inputNumberOfChannels),
            "Current input: \(routeInputs.isEmpty ? "none" : routeInputs)",
            "Current output: \(routeOutputs.isEmpty ? "none" : routeOutputs)",
            "Preferred input: \(preferredInput)",
            "Available inputs: \(availableInputs.isEmpty ? "none" : availableInputs)",
            "File: \(url)",
            "File size: \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))"
        ]

        if let extra {
            lines.append(extra)
        }

        debugLines = lines
    }
}
