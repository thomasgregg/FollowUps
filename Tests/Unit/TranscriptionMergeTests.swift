import Foundation
import XCTest
@testable import FollowUps

final class TranscriptionMergeTests: XCTestCase {
    func testFinalizeTranscriptionReturnsSingleFinalSegment() async throws {
        let client = OpenAITranscriptionClientMock(result: .init(text: "Wir schicken das Dokument morgen.", language: "de"))
        let service = TranscriptionService(client: client)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try Data("audio".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let segments = try await service.finalizeTranscription(for: tempURL)

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.text, "Wir schicken das Dokument morgen.")
        XCTAssertTrue(segments.first?.isFinal == true)
    }

    func testStartLiveTranscriptionRequiresAPIKey() async {
        let client = OpenAITranscriptionClientMock(result: .init(text: "", language: nil), hasAPIKey: false)
        let service = TranscriptionService(client: client)

        await XCTAssertThrowsErrorAsync(try await service.startLiveTranscription(sessionID: UUID()))
    }
}

private final class OpenAITranscriptionClientMock: OpenAIClienting {
    let result: OpenAITranscriptionResult
    let hasAPIKeyValue: Bool

    init(result: OpenAITranscriptionResult, hasAPIKey: Bool = true) {
        self.result = result
        self.hasAPIKeyValue = hasAPIKey
    }

    func hasConfiguredAPIKey() -> Bool {
        hasAPIKeyValue
    }

    func transcribeAudio(at audioURL: URL) async throws -> OpenAITranscriptionResult {
        result
    }

    func extractActionItems(from transcript: String) async throws -> ExtractedTasksResult {
        ExtractedTasksResult(headline: nil, items: [])
    }
}
