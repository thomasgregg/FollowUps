import Foundation

protocol OpenAIClienting {
    func hasConfiguredAPIKey() -> Bool
    func transcribeAudio(at audioURL: URL) async throws -> OpenAITranscriptionResult
    func extractActionItems(from transcript: String) async throws -> ExtractedTasksResult
}

struct OpenAITranscriptionResult: Equatable {
    let text: String
    let language: String?
}

enum OpenAIClientError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add your OpenAI API key in Settings before using AI processing."
        case .invalidResponse:
            "FollowUps received an invalid response from OpenAI."
        case let .apiError(message):
            message
        }
    }
}

final class OpenAIClient: OpenAIClienting {
    private let session: URLSession
    private let persistenceService: PersistenceServicing
    private let bundle: Bundle
    private let baseURL: URL
    private let transcriptionModel: String
    private let extractionModel: String

    init(
        persistenceService: PersistenceServicing,
        session: URLSession = .shared,
        bundle: Bundle = .main,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        transcriptionModel: String = "gpt-4o-transcribe",
        extractionModel: String = "gpt-5"
    ) {
        self.persistenceService = persistenceService
        self.session = session
        self.bundle = bundle
        self.baseURL = baseURL
        self.transcriptionModel = transcriptionModel
        self.extractionModel = extractionModel
    }

    func hasConfiguredAPIKey() -> Bool {
        !(configuredAPIKey()?.isEmpty ?? true)
    }

    func transcribeAudio(at audioURL: URL) async throws -> OpenAITranscriptionResult {
        let apiKey = try requireAPIKey()
        let boundary = UUID().uuidString
        let multipartFileURL = try multipartBodyFile(
            boundary: boundary,
            fileURL: audioURL,
            fields: [
                "model": transcriptionModel,
                "response_format": "json"
            ]
        )
        defer { try? FileManager.default.removeItem(at: multipartFileURL) }

        var request = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 * 20

        let (data, response) = try await session.upload(for: request, fromFile: multipartFileURL)
        try validate(response: response, data: data)
        let decoded: AudioTranscriptionResponse
        do {
            decoded = try JSONDecoder().decode(AudioTranscriptionResponse.self, from: data)
        } catch {
            throw OpenAIClientError.apiError(
                "OpenAI transcription returned unreadable JSON. Preview: \(Self.preview(data: data))"
            )
        }
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw OpenAIClientError.apiError(
                "OpenAI transcription returned empty text. Preview: \(Self.preview(data: data))"
            )
        }
        return OpenAITranscriptionResult(text: text, language: decoded.language)
    }

    func extractActionItems(from transcript: String) async throws -> ExtractedTasksResult {
        let cleanedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTranscript.isEmpty else { throw ActionItemExtractionError.emptyTranscript }
        let settings = persistenceService.loadSettings()
        let styleInstructions = Self.styleInstructions(for: settings.extractionStyle)
        let customInstructions = settings.customExtractionInstructions
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let apiKey = try requireAPIKey()
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60 * 5
        request.httpBody = try JSONEncoder().encode(
            ChatCompletionsRequest(
                model: extractionModel,
                messages: [
                    .init(role: "system", content: Self.systemPrompt),
                    .init(role: "user", content: """
                    Extract the follow-up tasks from this transcript. Keep tasks in the same language as the speaker.

                    Rules:
                    - Include tasks that are explicit commitments, direct requests, assignments, or clear next steps agreed in the conversation.
                    - Treat imperative spoken commands like "buch mir ...", "schick ...", "reserviere ...", or "bitte ..." as tasks even when the sentence is short or grammatically messy.
                    - Treat first-person obligation phrases like "ich muss ..." or "wir müssen ..." as tasks when they clearly describe something to be done.
                    - Do not include generic discussion topics or pure background information as tasks.
                    - Infer an owner when the transcript strongly suggests one. If unclear, use null.
                    - Infer a due date when the transcript gives a plausible deadline hint. If unclear, use null.
                    - Keep titles short, concrete, and action-oriented.
                    - Include an exact sourceQuote copied from the transcript that best supports the task.
                    - Prefer capturing useful next steps over returning too few tasks.
                    - Apply this extraction style guidance: \(styleInstructions)
                    \(customInstructions.isEmpty ? "" : "- Also follow these user preferences: \(customInstructions)")

                    Examples:
                    Transcript: "Wir sollten vielleicht irgendwann mal über die Website sprechen."
                    Output: { "items": [] }

                    Transcript: "Anna, bitte schick das Angebot bis Freitag."
                    Output:
                    {
                      "headline": "Angebot bis Freitag",
                      "items": [
                        {
                          "title": "Angebot schicken",
                          "details": null,
                          "owner": "Anna",
                          "dueDateISO8601": null,
                          "sourceQuote": "Anna, bitte schick das Angebot bis Freitag.",
                          "confidence": 0.98
                        }
                      ]
                    }

                    Transcript: "Übermorgen soll die Assistentin einen Kuchen bestellen."
                    Output:
                    {
                      "headline": "Kuchen fuer uebermorgen",
                      "items": [
                        {
                          "title": "Kuchen bestellen",
                          "details": null,
                          "owner": "Assistentin",
                          "dueDateISO8601": null,
                          "sourceQuote": "Übermorgen soll die Assistentin einen Kuchen bestellen.",
                          "confidence": 0.88
                        }
                      ]
                    }

                    Transcript: "Buch mir Billy Idol Konzerttickets fuer den 12.03."
                    Output:
                    {
                      "headline": "Billy Idol Tickets",
                      "items": [
                        {
                          "title": "Billy Idol Konzerttickets buchen",
                          "details": null,
                          "owner": null,
                          "dueDateISO8601": null,
                          "sourceQuote": "Buch mir Billy Idol Konzerttickets fuer den 12.03.",
                          "confidence": 0.9
                        }
                      ]
                    }

                    Also create a short session headline from the same transcript.

                    Headline rules:
                    - headline is required
                    - use the same language as the transcript
                    - use at most 6 words
                    - capture the overall purpose or outcome of the call
                    - do not use quotation marks
                    - do not return a full sentence

                    Return valid JSON with this shape:
                    {
                      "headline": "string",
                      "items": [
                        {
                          "title": "string",
                          "details": "string or null",
                          "owner": "string or null",
                          "dueDateISO8601": "string or null",
                          "sourceQuote": "string",
                          "confidence": 0.0
                        }
                      ]
                    }

                    Transcript:
                    \(cleanedTranscript)
                    """)
                ],
                responseFormat: .jsonObject
            )
        )

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        let assistantMessage = try parseAssistantMessagePayload(from: data)

        if let refusal = assistantMessage.refusal, !refusal.isEmpty {
            throw OpenAIClientError.apiError(refusal)
        }

        guard let content = assistantMessage.content, !content.isEmpty else {
            throw OpenAIClientError.apiError(
                "OpenAI task extraction returned empty content. Preview: \(Self.preview(data: data))"
            )
        }

        let extracted = try decodeActionItems(from: content)
        let items = extracted.items.map {
            ActionItem(
                id: UUID(),
                title: $0.title,
                details: $0.details,
                owner: $0.owner,
                dueDate: Self.parseISO8601Date($0.dueDateISO8601),
                sourceQuote: $0.sourceQuote,
                confidence: min(max($0.confidence, 0), 1),
                selectedForExport: true,
                linkedReminderID: nil
            )
        }
        let headline = extracted.headline?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let headline, !headline.isEmpty else {
            throw OpenAIClientError.apiError(
                "OpenAI task extraction returned no usable headline. Preview: \(Self.preview(text: content))"
            )
        }

        return ExtractedTasksResult(
            headline: headline,
            items: items
        )
    }

    private func decodeActionItems(from content: String) throws -> ActionItemsEnvelope {
        let cleanedContent = Self.cleanJSONContent(content)
        let candidates = Self.jsonDecodeCandidates(from: cleanedContent)

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }

            if let envelope = try? JSONDecoder().decode(ActionItemsEnvelope.self, from: data) {
                return envelope
            }

            if let array = try? JSONDecoder().decode([ActionItemsEnvelope.Item].self, from: data) {
                return ActionItemsEnvelope(headline: nil, items: array)
            }

            if
                let object = try? JSONSerialization.jsonObject(with: data),
                let envelope = Self.actionItemsEnvelope(from: object)
            {
                return envelope
            }
        }

        throw OpenAIClientError.apiError(
            "OpenAI task extraction returned unusable content. Preview: \(Self.preview(text: cleanedContent))"
        )
    }

    private func parseAssistantMessagePayload(from data: Data) throws -> AssistantMessagePayload {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let choice = choices.first
        else {
            throw OpenAIClientError.apiError(
                "OpenAI task extraction returned unreadable JSON. Preview: \(Self.preview(data: data))"
            )
        }

        let message = choice["message"] as? [String: Any]
        let refusal = Self.extractText(from: message?["refusal"])
        let content =
            Self.extractText(from: message?["content"])
            ?? Self.extractToolArguments(from: message?["tool_calls"])
            ?? Self.extractText(from: choice["text"])

        return AssistantMessagePayload(
            content: content?.trimmingCharacters(in: .whitespacesAndNewlines),
            refusal: refusal?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func requireAPIKey() throws -> String {
        guard let apiKey = configuredAPIKey(), !apiKey.isEmpty else {
            throw OpenAIClientError.missingAPIKey
        }
        return apiKey
    }

    private func configuredAPIKey() -> String? {
        let settingsKey = persistenceService.loadSettings().openAIAPIKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !settingsKey.isEmpty {
            return settingsKey
        }

        let plistKey = (bundle.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return plistKey
    }

    private func multipartBodyFile(
        boundary: String,
        fileURL: URL,
        fields: [String: String]
    ) throws -> URL {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("multipart")
        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)

        let outputHandle = try FileHandle(forWritingTo: temporaryURL)
        defer { try? outputHandle.close() }

        for (name, value) in fields {
            try outputHandle.write(contentsOf: Data("--\(boundary)\r\n".utf8))
            try outputHandle.write(contentsOf: Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            try outputHandle.write(contentsOf: Data("\(value)\r\n".utf8))
        }

        try outputHandle.write(contentsOf: Data("--\(boundary)\r\n".utf8))
        try outputHandle.write(contentsOf: Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".utf8))
        try outputHandle.write(contentsOf: Data("Content-Type: audio/mp4\r\n\r\n".utf8))

        let inputHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? inputHandle.close() }

        while autoreleasepool(invoking: {
            let chunk = inputHandle.readData(ofLength: 64 * 1024)
            if chunk.isEmpty { return false }
            try? outputHandle.write(contentsOf: chunk)
            return true
        }) {}

        try outputHandle.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
        return temporaryURL
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.apiError("OpenAI returned a non-HTTP response.")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if
                let apiError = try? JSONDecoder().decode(OpenAIAPIErrorResponse.self, from: data),
                let message = apiError.error.message
            {
                throw OpenAIClientError.apiError(message)
            }
            throw OpenAIClientError.apiError(
                "OpenAI request failed with status \(httpResponse.statusCode). Preview: \(Self.preview(data: data))"
            )
        }
    }

    private static func parseISO8601Date(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter.fullInternet.date(from: value)
            ?? ISO8601DateFormatter.dateOnly.date(from: value)
    }

    private static func cleanJSONContent(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }

        let lines = trimmed.components(separatedBy: .newlines)
        let strippedLines = Array(lines.dropFirst())
        let bodyLines: [String]
        if let last = strippedLines.last,
           last.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).hasPrefix("```") {
            bodyLines = Array(strippedLines.dropLast())
        } else {
            bodyLines = strippedLines
        }
        let stripped = bodyLines.joined(separator: "\n")
        return stripped.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    private static func jsonDecodeCandidates(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var candidates: [String] = [trimmed]

        if
            let objectStart = trimmed.firstIndex(of: "{"),
            let objectEnd = trimmed.lastIndex(of: "}")
        {
            let objectCandidate = String(trimmed[objectStart...objectEnd])
            if !objectCandidate.isEmpty, objectCandidate != trimmed {
                candidates.append(objectCandidate)
            }
        }

        if
            let arrayStart = trimmed.firstIndex(of: "["),
            let arrayEnd = trimmed.lastIndex(of: "]")
        {
            let arrayCandidate = String(trimmed[arrayStart...arrayEnd])
            if !arrayCandidate.isEmpty, !candidates.contains(arrayCandidate) {
                candidates.append(arrayCandidate)
            }
        }

        return candidates
    }

    private static func actionItemsEnvelope(from object: Any) -> ActionItemsEnvelope? {
        if let itemArray = object as? [[String: Any]] {
            let items = itemArray.compactMap(actionItem(from:))
            return ActionItemsEnvelope(headline: nil, items: items)
        }

        guard let dict = object as? [String: Any] else { return nil }

        let itemsRaw =
            (dict["items"] as? [[String: Any]])
            ?? (dict["tasks"] as? [[String: Any]])
            ?? (dict["actionItems"] as? [[String: Any]])
            ?? (dict["action_items"] as? [[String: Any]])
            ?? []

        let headline =
            nonEmptyString(dict["headline"])
            ?? nonEmptyString(dict["sessionHeadline"])
            ?? nonEmptyString(dict["session_headline"])
            ?? nonEmptyString(dict["title"])

        let items = itemsRaw.compactMap(actionItem(from:))
        return ActionItemsEnvelope(headline: headline, items: items)
    }

    private static func actionItem(from dict: [String: Any]) -> ActionItemsEnvelope.Item? {
        guard
            let title =
                nonEmptyString(dict["title"])
                ?? nonEmptyString(dict["task"])
                ?? nonEmptyString(dict["name"])
                ?? nonEmptyString(dict["action"])
        else {
            return nil
        }

        let details = nonEmptyString(dict["details"]) ?? nonEmptyString(dict["detail"])
        let owner = nonEmptyString(dict["owner"]) ?? nonEmptyString(dict["assignee"])
        let dueDate =
            nonEmptyString(dict["dueDateISO8601"])
            ?? nonEmptyString(dict["dueDate"])
            ?? nonEmptyString(dict["due_date"])
        let sourceQuote =
            nonEmptyString(dict["sourceQuote"])
            ?? nonEmptyString(dict["source_quote"])
            ?? nonEmptyString(dict["quote"])
            ?? nonEmptyString(dict["evidence"])

        let confidence =
            parseDouble(dict["confidence"])
            ?? parseDouble(dict["score"])
            ?? 0.75

        return ActionItemsEnvelope.Item(
            title: title,
            details: details,
            owner: owner,
            dueDateISO8601: dueDate,
            sourceQuote: sourceQuote,
            confidence: confidence
        )
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func parseDouble(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            let normalized = string
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            return Double(normalized)
        }
        return nil
    }

    private static func extractText(from raw: Any?) -> String? {
        guard let raw else { return nil }

        if let string = raw as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let dict = raw as? [String: Any] {
            return extractText(from: dict["text"])
                ?? extractText(from: dict["value"])
                ?? extractText(from: dict["content"])
                ?? extractText(from: dict["refusal"])
        }

        if let array = raw as? [Any] {
            let pieces = array.compactMap { item -> String? in
                if let itemDict = item as? [String: Any] {
                    return extractText(from: itemDict["text"])
                        ?? extractText(from: itemDict["value"])
                        ?? extractText(from: itemDict["content"])
                        ?? extractText(from: itemDict["refusal"])
                }
                return extractText(from: item)
            }

            let joined = pieces.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : joined
        }

        return nil
    }

    private static func extractToolArguments(from raw: Any?) -> String? {
        guard let calls = raw as? [[String: Any]] else { return nil }
        for call in calls {
            if
                let function = call["function"] as? [String: Any],
                let arguments = function["arguments"] as? String
            {
                let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private static func preview(data: Data) -> String {
        preview(text: String(data: data, encoding: .utf8) ?? "<non-UTF8 response>")
    }

    private static func preview(text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(280))
    }

    private static let systemPrompt = """
    You extract actionable follow-up tasks from call transcripts in any language.

    Follow these rules:
    - Return tasks that someone committed to do, was asked to do, was assigned to do, or that the conversation clearly established as a next step.
    - Imperative requests and short spoken commands count as tasks.
    - Spoken, imperfect, or lightly ungrammatical phrasing can still express a real task and should not be rejected for that reason alone.
    - Do not convert broad themes, summaries, or pure background context into tasks.
    - Preserve the original language from the transcript.
    - Deduplicate overlapping tasks.
    - Keep titles short and concrete, starting with a verb when possible.
    - Put extra context into details only when it helps clarify the task.
    - Infer owner when the transcript strongly suggests the responsible person. Otherwise return null.
    - Infer dueDateISO8601 when the transcript gives a plausible deadline or date. Otherwise return null.
    - Include sourceQuote as an exact quote from the transcript that best supports the task.
    - It is better to include a useful likely task with medium confidence than to miss an obvious follow-up.
    """

    private static func styleInstructions(for style: ExtractionStyle) -> String {
        switch style {
        case .balanced:
            "Use balanced judgment. Capture useful tasks without inventing weak ones."
        case .moreTasks:
            "Lean toward inclusion. Capture clear implied next steps when the speaker intent sounds practical and actionable."
        case .onlyCertain:
            "Lean toward caution. Only return tasks when the transcript sounds especially explicit or strongly implied."
        }
    }
}

private struct AudioTranscriptionResponse: Decodable {
    let text: String
    let language: String?
}

private struct AssistantMessagePayload {
    let content: String?
    let refusal: String?
}

private struct OpenAIAPIErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError
}

private struct ChatCompletionsRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String

        static let jsonObject = ResponseFormat(type: "json_object")
    }

    let model: String
    let messages: [Message]
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
    }
}

private struct ChatCompletionsResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
            let refusal: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct ActionItemsEnvelope: Decodable {
    struct Item: Decodable {
        private enum CodingKeys: String, CodingKey {
            case title
            case details
            case owner
            case dueDateISO8601
            case sourceQuote
            case confidence
        }

        let title: String
        let details: String?
        let owner: String?
        let dueDateISO8601: String?
        let sourceQuote: String?
        let confidence: Double

        init(
            title: String,
            details: String?,
            owner: String?,
            dueDateISO8601: String?,
            sourceQuote: String?,
            confidence: Double
        ) {
            self.title = title
            self.details = details
            self.owner = owner
            self.dueDateISO8601 = dueDateISO8601
            self.sourceQuote = sourceQuote
            self.confidence = confidence
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            details = try container.decodeIfPresent(String.self, forKey: .details)
            owner = try container.decodeIfPresent(String.self, forKey: .owner)
            dueDateISO8601 = try container.decodeIfPresent(String.self, forKey: .dueDateISO8601)
            sourceQuote = try container.decodeIfPresent(String.self, forKey: .sourceQuote)
            confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.75
        }
    }

    let headline: String?
    let items: [Item]
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

private extension ISO8601DateFormatter {
    static let fullInternet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let dateOnly: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
