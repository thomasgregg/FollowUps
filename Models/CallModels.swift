import Foundation

struct CallSession: Identifiable, Codable, Hashable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var status: SessionStatus
    var headline: String?
    var audioFileURL: URL?
    var durationSeconds: Int
    var consentConfirmed: Bool
    var transcript: [TranscriptSegment]
    var summary: SessionSummary?
    var actionItems: [ActionItem]
    var createdReminderIDs: [String]
    var debugNotes: [String]
}

enum SessionStatus: String, Codable, CaseIterable {
    case idle
    case recording
    case processing
    case completed
    case failed
}

struct TranscriptSegment: Identifiable, Codable, Hashable {
    var id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
    var isFinal: Bool
}

struct TranscriptChunk: Identifiable, Codable, Hashable {
    var id: UUID
    var text: String
    var timestamp: Date
    var isFinal: Bool
}

struct SessionSummary: Codable, Hashable {
    var headline: String
    var bullets: [String]
    var decisions: [String]
    var openQuestions: [String]
}

struct ActionItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var details: String?
    var owner: String?
    var dueDate: Date?
    var sourceQuote: String?
    var confidence: Double
    var selectedForExport: Bool
    var linkedReminderID: String?
}

enum RecordingState: Equatable {
    case idle
    case requestingPermission
    case ready
    case recording
    case stopping
    case failed(String)
}

enum PermissionState: Equatable {
    case unknown
    case granted
    case denied
}

extension CallSession {
    static let mock = CallSession(
        id: UUID(),
        startedAt: .now.addingTimeInterval(-1800),
        endedAt: .now.addingTimeInterval(-1500),
        status: .completed,
        headline: "Proposal follow-up",
        audioFileURL: nil,
        durationSeconds: 300,
        consentConfirmed: true,
        transcript: [
            TranscriptSegment(id: UUID(), startTime: 0, endTime: 10, text: "We agreed to send the revised proposal by Friday.", isFinal: true)
        ],
        summary: SessionSummary(
            headline: "Proposal follow-up and ownership alignment",
            bullets: ["Reviewed the revised proposal scope.", "Assigned follow-up owners."],
            decisions: ["Pricing stays unchanged for this round."],
            openQuestions: ["Will legal need another review?"]
        ),
        actionItems: [
            ActionItem(id: UUID(), title: "Send revised proposal", details: "Include updated terms section.", owner: "Me", dueDate: .now.addingTimeInterval(86_400 * 2), sourceQuote: "I'll send the revised proposal by Friday.", confidence: 0.91, selectedForExport: true, linkedReminderID: nil)
        ],
        createdReminderIDs: [],
        debugNotes: []
    )
}
