import Foundation

struct AppSettings: Codable, Equatable {
    var retentionCleanupEnabled = false
    var retentionDays = 30
    var openAIAPIKey = ""
    var extractionStyle: ExtractionStyle = .balanced
    var customExtractionInstructions = ""
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
