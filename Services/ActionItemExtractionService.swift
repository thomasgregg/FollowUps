import Foundation

final class ActionItemExtractionService: ActionItemExtracting {
    private let client: OpenAIClienting

    init(client: OpenAIClienting) {
        self.client = client
    }

    func extractActionItems(transcript: [TranscriptSegment]) async throws -> ExtractedTasksResult {
        let combinedTranscript = transcript
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !combinedTranscript.isEmpty else {
            throw ActionItemExtractionError.emptyTranscript
        }

        do {
            return try await client.extractActionItems(from: combinedTranscript)
        } catch let error as OpenAIClientError {
            switch error {
            case .missingAPIKey:
                throw ActionItemExtractionError.missingAPIKey
            case let .apiError(message):
                throw NSError(domain: "CallNotes.OpenAI", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
            default:
                throw ActionItemExtractionError.invalidResponse
            }
        } catch {
            throw ActionItemExtractionError.invalidResponse
        }
    }
}
