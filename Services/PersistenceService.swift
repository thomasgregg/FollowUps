import Foundation

final class PersistenceService: PersistenceServicing {
    private let fm = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var baseURL: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CallNotes", isDirectory: true)
    }

    private var sessionsURL: URL { baseURL.appendingPathComponent("sessions.json") }
    private var settingsURL: URL { baseURL.appendingPathComponent("settings.json") }
    private var audioURL: URL { baseURL.appendingPathComponent("Audio", isDirectory: true) }

    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        ensureDirectories()
    }

    func fetchSessions() throws -> [CallSession] {
        guard fm.fileExists(atPath: sessionsURL.path) else { return [] }
        let data = try Data(contentsOf: sessionsURL)
        do {
            return try decoder.decode([CallSession].self, from: data)
                .sorted { $0.startedAt > $1.startedAt }
        } catch {
            try? fm.removeItem(at: sessionsURL)
            return []
        }
    }

    func save(session: CallSession) throws {
        var sessions = try fetchSessions().filter { $0.id != session.id }
        sessions.append(session)
        let data = try encoder.encode(sessions.sorted { $0.startedAt > $1.startedAt })
        try data.write(to: sessionsURL, options: .atomic)
    }

    func purgeExpiredSessions(retentionDays: Int) throws {
        let sessions = try fetchSessions()
        guard !sessions.isEmpty else { return }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now) ?? .distantPast
        let expired = sessions.filter { ($0.endedAt ?? $0.startedAt) < cutoffDate }
        guard !expired.isEmpty else { return }

        let expiredIDs = Set(expired.map(\.id))
        let remaining = sessions.filter { !expiredIDs.contains($0.id) }
        let data = try encoder.encode(remaining.sorted { $0.startedAt > $1.startedAt })
        try data.write(to: sessionsURL, options: .atomic)

        for session in expired {
            let candidateURL = session.audioFileURL ?? audioFileURL(for: session.id)
            if fm.fileExists(atPath: candidateURL.path) {
                try? fm.removeItem(at: candidateURL)
            }
        }
    }

    func deleteSession(id: UUID) throws {
        let sessions = try fetchSessions()
        guard let sessionToDelete = sessions.first(where: { $0.id == id }) else { return }

        let remaining = sessions.filter { $0.id != id }
        let data = try encoder.encode(remaining.sorted { $0.startedAt > $1.startedAt })
        try data.write(to: sessionsURL, options: .atomic)

        let candidateURL = sessionToDelete.audioFileURL ?? audioFileURL(for: id)
        if fm.fileExists(atPath: candidateURL.path) {
            try? fm.removeItem(at: candidateURL)
        }
    }

    func deleteAllSessions() throws {
        if fm.fileExists(atPath: sessionsURL.path) {
            try fm.removeItem(at: sessionsURL)
        }
        if fm.fileExists(atPath: audioURL.path) {
            try fm.removeItem(at: audioURL)
        }
        ensureDirectories()
    }

    func loadSettings() -> AppSettings {
        guard
            fm.fileExists(atPath: settingsURL.path),
            let data = try? Data(contentsOf: settingsURL),
            let settings = try? decoder.decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }
        return settings
    }

    func save(settings: AppSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }

    func audioFileURL(for sessionID: UUID) -> URL {
        audioURL.appendingPathComponent("\(sessionID.uuidString).m4a")
    }

    private func ensureDirectories() {
        try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: audioURL, withIntermediateDirectories: true)
    }
}
