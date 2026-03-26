import Foundation

struct AppSettings: Codable, Equatable {
    var retentionCleanupEnabled = false
    var retentionDays = 30
    var cloudProcessingConsentGiven = false
    var openAIAPIKey = ""
    var extractionStyle: ExtractionStyle = .balanced
    var customExtractionInstructions = ""

    private enum CodingKeys: String, CodingKey {
        case retentionCleanupEnabled
        case retentionDays
        case cloudProcessingConsentGiven
        case openAIAPIKey
        case extractionStyle
        case customExtractionInstructions
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        retentionCleanupEnabled = try container.decodeIfPresent(Bool.self, forKey: .retentionCleanupEnabled) ?? false
        retentionDays = try container.decodeIfPresent(Int.self, forKey: .retentionDays) ?? 30
        cloudProcessingConsentGiven = try container.decodeIfPresent(Bool.self, forKey: .cloudProcessingConsentGiven) ?? false
        openAIAPIKey = try container.decodeIfPresent(String.self, forKey: .openAIAPIKey) ?? ""
        extractionStyle = try container.decodeIfPresent(ExtractionStyle.self, forKey: .extractionStyle) ?? .balanced
        customExtractionInstructions = try container.decodeIfPresent(String.self, forKey: .customExtractionInstructions) ?? ""
    }
}

enum ExtractionStyle: String, Codable, CaseIterable, Identifiable {
    case balanced
    case moreTasks
    case onlyCertain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced:
            "Balanced"
        case .moreTasks:
            "More tasks"
        case .onlyCertain:
            "Only certain tasks"
        }
    }

    var helperText: String {
        switch self {
        case .balanced:
            "A middle ground between missing tasks and over-guessing."
        case .moreTasks:
            "Capture more next steps, even when phrasing is a bit indirect."
        case .onlyCertain:
            "Only keep tasks that sound especially clear and reliable."
        }
    }
}
