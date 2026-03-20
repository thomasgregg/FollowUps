import XCTest
@testable import FollowUps

final class ActionItemExtractionServiceTests: XCTestCase {
    func testExtractActionItemsUsesOpenAIClientResult() async throws {
        let expected = [
            ActionItem(
                id: UUID(),
                title: "Angebot schicken",
                details: "Die aktualisierte Version bis Freitag senden.",
                owner: "Ich",
                dueDate: nil,
                sourceQuote: "Ich schicke das Angebot bis Freitag.",
                confidence: 0.92,
                selectedForExport: true,
                linkedReminderID: nil
            )
        ]
        let client = OpenAIClientMock(extractedItems: expected)
        let service = ActionItemExtractionService(client: client)

        let result = try await service.extractActionItems(transcript: [
            TranscriptSegment(id: UUID(), startTime: 0, endTime: 0, text: "Ich schicke das Angebot bis Freitag.", isFinal: true)
        ])

        XCTAssertEqual(result.items, expected)
        XCTAssertEqual(result.headline, "Angebot bis Freitag")
        XCTAssertEqual(client.lastTranscript, "Ich schicke das Angebot bis Freitag.")
    }

    func testExtractActionItemsThrowsOnEmptyTranscript() async {
        let client = OpenAIClientMock(extractedItems: [])
        let service = ActionItemExtractionService(client: client)

        await XCTAssertThrowsErrorAsync(try await service.extractActionItems(transcript: []))
    }
}

private final class OpenAIClientMock: OpenAIClienting {
    private let extractedItems: [ActionItem]
    private let headline: String?
    private(set) var lastTranscript: String?

    init(extractedItems: [ActionItem], headline: String? = "Angebot bis Freitag") {
        self.extractedItems = extractedItems
        self.headline = headline
    }

    func hasConfiguredAPIKey() -> Bool {
        true
    }

    func transcribeAudio(at audioURL: URL) async throws -> OpenAITranscriptionResult {
        OpenAITranscriptionResult(text: "", language: nil)
    }

    func extractActionItems(from transcript: String) async throws -> ExtractedTasksResult {
        lastTranscript = transcript
        return ExtractedTasksResult(headline: headline, items: extractedItems)
    }
}
