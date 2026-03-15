import AVFoundation
import SwiftUI

struct SessionsListView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @State private var sessionPendingDeletion: CallSession?
    @State private var showDeleteAllConfirmation = false
    @State private var showDeleteSelectedConfirmation = false
    @State private var isSelectionMode = false
    @State private var selectedSessionIDs: Set<UUID> = []
    @State private var selectedSession: CallSession?

    private var sessionCardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
            )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedSessions) { group in
                    Section(group.title) {
                        ForEach(group.sessions) { session in
                            Group {
                                if isSelectionMode {
                                    Button {
                                        toggleSelection(for: session.id)
                                    } label: {
                                        SessionRow(
                                            session: session,
                                            showsSelection: true,
                                            isSelected: selectedSessionIDs.contains(session.id),
                                            showsChevron: false,
                                            cardBackground: AnyView(sessionCardBackground)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Button {
                                        selectedSession = session
                                    } label: {
                                        SessionRow(
                                            session: session,
                                            showsSelection: false,
                                            isSelected: false,
                                            showsChevron: true,
                                            cardBackground: AnyView(sessionCardBackground)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if !isSelectionMode {
                                    Button(role: .destructive) {
                                        sessionPendingDeletion = session
                                    } label: {
                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 34, weight: .bold))
                                            .imageScale(.large)
                                            .frame(width: 120, height: 120)
                                    }
                                    .tint(.red)
                                }
                            }
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedSession) { session in
                SessionDetailView(session: session)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .overlay {
                if appViewModel.sessions.isEmpty {
                    ContentUnavailableView("No Sessions Yet", systemImage: "mic.slash", description: Text("Start a recording from the Record tab, a widget, or an App Shortcut."))
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                if !appViewModel.sessions.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        if isSelectionMode {
                            HStack(spacing: 12) {
                                Button("Cancel") {
                                    exitSelectionMode()
                                }

                                Button("Delete Selected", role: .destructive) {
                                    showDeleteSelectedConfirmation = true
                                }
                                .disabled(selectedSessionIDs.isEmpty)
                            }
                        } else {
                            Menu("Manage") {
                                Button("Select Sessions to Delete") {
                                    isSelectionMode = true
                                }

                                Button("Delete All Sessions", role: .destructive) {
                                    showDeleteAllConfirmation = true
                                }
                            }
                        }
                    }
                }
            }
            .alert("Delete Session?", isPresented: Binding(
                get: { sessionPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        sessionPendingDeletion = nil
                    }
                }
            )) {
                Button("Delete", role: .destructive) {
                    if let sessionPendingDeletion {
                        appViewModel.deleteSession(id: sessionPendingDeletion.id)
                    }
                    sessionPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    sessionPendingDeletion = nil
                }
            } message: {
                Text("This deletes the session and its recording.")
            }
            .alert("Delete All Sessions?", isPresented: $showDeleteAllConfirmation) {
                Button("Delete All", role: .destructive) {
                    appViewModel.deleteAllSessions()
                    exitSelectionMode()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes every session and all saved recordings.")
            }
            .alert("Delete Selected Sessions?", isPresented: $showDeleteSelectedConfirmation) {
                Button("Delete Selected", role: .destructive) {
                    for sessionID in selectedSessionIDs {
                        appViewModel.deleteSession(id: sessionID)
                    }
                    exitSelectionMode()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes the selected sessions and their recordings.")
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var groupedSessions: [SessionGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: appViewModel.sessions) { session in
            calendar.startOfDay(for: session.startedAt)
        }

        return grouped
            .map { SessionGroup(date: $0.key, sessions: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.date > $1.date }
    }

    private func toggleSelection(for sessionID: UUID) {
        if selectedSessionIDs.contains(sessionID) {
            selectedSessionIDs.remove(sessionID)
        } else {
            selectedSessionIDs.insert(sessionID)
        }
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedSessionIDs.removeAll()
    }
}

enum SessionDetailPresentation {
    case browsing
    case review
}

struct SessionDetailView: View {
    let session: CallSession
    let presentation: SessionDetailPresentation
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel
    @StateObject private var audioPlayer = SessionAudioPlayer()
    @State private var editableItems: [ActionItem]
    @State private var saveMessage = ""
    @State private var saveErrorMessage = ""
    @State private var playbackErrorMessage = ""
    @State private var showDeleteConfirmation = false
    @State private var showReminderRemovalConfirmation = false

    init(session: CallSession, presentation: SessionDetailPresentation = .browsing) {
        self.session = session
        self.presentation = presentation
        _editableItems = State(initialValue: session.actionItems)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(sessionMetaText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Tasks")
                        .font(.title2)
                        .fontWeight(.semibold)

                    if editableItems.isEmpty {
                        Text("No tasks were extracted from this call.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($editableItems) { $item in
                            TaskCard(item: $item)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Divider()
                                .padding(.top, 4)

                            Button {
                                if hasDeselectedLinkedReminders {
                                    showReminderRemovalConfirmation = true
                                } else {
                                    syncReminders()
                                }
                            } label: {
                                Text(primaryReminderActionTitle)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                            .disabled(!hasPendingReminderChanges)

                            Text(primaryReminderHelperText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)
                    }
                }

                if !saveMessage.isEmpty {
                    Text(saveMessage)
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }

                if !saveErrorMessage.isEmpty {
                    Text(saveErrorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }

                if !playbackErrorMessage.isEmpty {
                    Text(playbackErrorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }

                ConversationCard(
                    audioURL: appViewModel.resolvedAudioURL(for: session),
                    isPlaying: audioPlayer.isPlaying,
                    durationText: recordingDurationText,
                    transcript: session.transcript,
                    togglePlayback: {
                        if let audioURL = appViewModel.resolvedAudioURL(for: session) {
                            do {
                                playbackErrorMessage = ""
                                try audioPlayer.togglePlayback(from: audioURL)
                            } catch {
                                playbackErrorMessage = error.localizedDescription
                            }
                        }
                    }
                )

                if !session.debugNotes.isEmpty {
                    DisclosureGroup("Processing Notes") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(session.debugNotes, id: \.self) { note in
                                Text(note)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 10)
                    }
                    .padding(20)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            audioPlayer.stop()
        }
        .toolbar {
            if presentation == .review {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Delete", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
        }
        .alert("Delete Session?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                appViewModel.deleteSession(id: session.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the session and its recording.")
        }
        .alert("Remove Unchecked Reminders?", isPresented: $showReminderRemovalConfirmation) {
            Button("Update Reminders", role: .destructive) {
                syncReminders()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unchecked tasks that were already saved to Apple Reminders will be removed.")
        }
    }

    private var sessionMetaText: String {
        let selectedCount = editableItems.filter(\.selectedForExport).count

        var parts = [recordingDurationText, "\(session.actionItems.count) tasks"]

        if selectedCount > 0 {
            parts.append(selectedCount == 1 ? "1 selected" : "\(selectedCount) selected")
        }

        return parts.joined(separator: " • ")
    }

    private var primaryReminderActionTitle: String {
        hasExistingLinkedReminders ? "Update Apple Reminders" : "Create Apple Reminders"
    }

    private var primaryReminderHelperText: String {
        hasExistingLinkedReminders
            ? "Updates Apple Reminders to match the checked tasks above."
            : "Creates Apple Reminders for the checked tasks above."
    }

    private var hasExistingLinkedReminders: Bool {
        editableItems.contains { $0.linkedReminderID != nil }
    }

    private var hasDeselectedLinkedReminders: Bool {
        editableItems.contains { !$0.selectedForExport && $0.linkedReminderID != nil }
    }

    private var hasPendingReminderChanges: Bool {
        editableItems.contains { $0.selectedForExport || $0.linkedReminderID != nil }
    }

    private var recordingDurationText: String {
        let seconds = max(session.durationSeconds, 0)
        if seconds < 60 {
            return "\(seconds) sec"
        }

        let minutes = seconds / 60
        let remainder = seconds % 60
        if remainder == 0 {
            return "\(minutes) min"
        }
        return "\(minutes)m \(remainder)s"
    }

    private func timestampText(for segment: TranscriptSegment) -> String? {
        guard segment.startTime > 0 || segment.endTime > 0 else {
            return nil
        }

        if segment.endTime > segment.startTime {
            return "\(format(seconds: segment.startTime)) - \(format(seconds: segment.endTime))"
        }

        return format(seconds: segment.startTime)
    }

    private func format(seconds: TimeInterval) -> String {
        "\(String(format: "%.1f", seconds))s"
    }

    private func syncReminders() {
        Task {
            saveMessage = ""
            saveErrorMessage = ""
            do {
                let result = try await appViewModel.saveSelectedReminders(for: session.id, items: editableItems)
                editableItems = result.items
                saveMessage = reminderMessage(for: result)
            } catch {
                saveErrorMessage = error.localizedDescription
            }
        }
    }

    private func reminderMessage(for result: ReminderSyncResult) -> String {
        if result.changedCount == 0 {
            return "Apple Reminders is already up to date."
        }

        var parts: [String] = []
        if result.createdCount > 0 {
            parts.append(result.createdCount == 1 ? "Created 1 reminder" : "Created \(result.createdCount) reminders")
        }
        if result.updatedCount > 0 {
            parts.append(result.updatedCount == 1 ? "updated 1 reminder" : "updated \(result.updatedCount) reminders")
        }
        if result.removedCount > 0 {
            parts.append(result.removedCount == 1 ? "removed 1 reminder" : "removed \(result.removedCount) reminders")
        }

        guard let first = parts.first else {
            return "Apple Reminders was updated."
        }

        let remaining = parts.dropFirst()
        let sentence = ([first.capitalized] + remaining).joined(separator: ", ")
        return sentence + "."
    }
}

private struct SessionRow: View {
    let session: CallSession
    let showsSelection: Bool
    let isSelected: Bool
    let showsChevron: Bool
    let cardBackground: AnyView

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if showsSelection {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 36, height: 36)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(metaText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if showsChevron {
                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(cardBackground)
    }

    private var title: String {
        if let headline = session.headline?.trimmingCharacters(in: .whitespacesAndNewlines),
           !headline.isEmpty,
           !Self.isLegacyFallbackHeadline(headline) {
            return headline
        }

        return "Untitled session"
    }

    private static func isLegacyFallbackHeadline(_ headline: String) -> Bool {
        let normalized = headline.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "untitled session" {
            return true
        }

        if normalized.hasSuffix("task from this call") || normalized.hasSuffix("tasks from this call") {
            let prefix = normalized
                .replacingOccurrences(of: "tasks from this call", with: "")
                .replacingOccurrences(of: "task from this call", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return !prefix.isEmpty && prefix.allSatisfy(\.isNumber)
        }

        return false
    }

    private var metaText: String {
        let reminderCount = session.createdReminderIDs.count
        return "\(durationText) • \(session.actionItems.count) tasks • \(reminderCount) reminders"
    }

    private var durationText: String {
        let seconds = max(session.durationSeconds, 0)
        if seconds < 60 {
            return "\(seconds) sec"
        }

        let minutes = seconds / 60
        let remainder = seconds % 60
        if remainder == 0 {
            return "\(minutes) min"
        }
        return "\(minutes)m \(remainder)s"
    }
}

private struct TaskCard: View {
    @Binding var item: ActionItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                item.selectedForExport.toggle()
            } label: {
                Image(systemName: item.selectedForExport ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(item.selectedForExport ? Color.accentColor : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, -6)

            VStack(alignment: .leading, spacing: 14) {
                TextField("Title", text: $item.title)
                    .font(.headline)

                if let details = item.details, !details.isEmpty {
                    Text(details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                DatePicker(
                    "Due Date",
                    selection: Binding(
                        get: { item.dueDate ?? .now },
                        set: { item.dueDate = $0 }
                    ),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.compact)

                if let sourceQuote = item.sourceQuote, !sourceQuote.isEmpty {
                    Text("From transcript: \"\(sourceQuote)\"")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(22)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 10, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            item.selectedForExport.toggle()
        }
    }
}

private struct SessionGroup: Identifiable {
    let date: Date
    let sessions: [CallSession]

    var id: Date { date }

    var title: String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        }
        return date.formatted(.dateTime.month(.wide).day())
    }
}

private struct AudioPlaybackCard: View {
    let isPlaying: Bool
    let durationText: String
    let togglePlayback: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text("Recording")
                    .font(.headline)
                Text(durationText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
        )
    }
}

private struct ConversationCard: View {
    let audioURL: URL?
    let isPlaying: Bool
    let durationText: String
    let transcript: [TranscriptSegment]
    let togglePlayback: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                if audioURL != nil {
                    Button(action: togglePlayback) {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Recording & Transcript")
                        .font(.headline)
                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(isExpanded ? "Hide" : "Show") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
            }

            if isExpanded {
                Divider()

                if audioURL == nil {
                    Text("Recording file is no longer available for playback.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(transcript) { segment in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(segment.text)

                            if let timestampText = timestampText(for: segment) {
                                Text(timestampText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
        )
    }

    private var summaryText: String {
        if audioURL != nil {
            if transcript.isEmpty {
                return "\(durationText) recording"
            }
            return "\(durationText) recording • Transcript available"
        }
        return transcript.isEmpty ? "Transcript unavailable" : "Transcript available"
    }

    private func timestampText(for segment: TranscriptSegment) -> String? {
        guard segment.startTime > 0 || segment.endTime > 0 else {
            return nil
        }

        if segment.endTime > segment.startTime {
            return "\(format(seconds: segment.startTime)) - \(format(seconds: segment.endTime))"
        }

        return format(seconds: segment.startTime)
    }

    private func format(seconds: TimeInterval) -> String {
        "\(String(format: "%.1f", seconds))s"
    }
}

@MainActor
private final class SessionAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false

    private var player: AVAudioPlayer?

    func togglePlayback(from url: URL) throws {
        if isPlaying {
            stop()
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(
                domain: "CallNotes.AudioPlayback",
                code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The recording file could not be found."]
                )
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else {
                throw NSError(
                    domain: "CallNotes.AudioPlayback",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "FollowUps could not start playback."]
                )
            }
            self.player = player
            isPlaying = true
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            stop()
        }
    }
}
