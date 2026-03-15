import AVFoundation
import Foundation

final class TranscriptionService: NSObject, TranscriptionServicing {
    private let client: OpenAIClienting
    private(set) var partialText = ""

    init(client: OpenAIClienting) {
        self.client = client
    }

    func isConfigured() async -> Bool {
        client.hasConfiguredAPIKey()
    }

    func startLiveTranscription(sessionID: UUID) async throws {
        guard client.hasConfiguredAPIKey() else {
            throw TranscriptionError.missingAPIKey
        }
        partialText = "Recording in progress. OpenAI will transcribe it and extract tasks after you stop."
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer, when: AVAudioTime?) async {}

    func stopLiveTranscription() async {
        partialText = ""
    }

    func finalizeTranscription(for audioURL: URL) async throws -> [TranscriptSegment] {
        do {
            let result = try await client.transcribeAudio(at: audioURL)
            return [
                TranscriptSegment(
                    id: UUID(),
                    startTime: 0,
                    endTime: 0,
                    text: result.text,
                    isFinal: true
                )
            ]
        } catch let error as OpenAIClientError {
            switch error {
            case .missingAPIKey:
                throw TranscriptionError.missingAPIKey
            case let .apiError(message):
                throw NSError(domain: "CallNotes.OpenAI", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            default:
                throw TranscriptionError.finalizationFailed
            }
        } catch {
            throw NSError(
                domain: "CallNotes.Transcription",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
            )
        }
    }
}
