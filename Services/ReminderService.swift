import EventKit
import Foundation

final class ReminderService: ReminderServicing {
    private let store = EKEventStore()

    func requestAccess() async throws -> Bool {
        let granted = try await store.requestFullAccessToReminders()
        if !granted {
            throw ReminderError.accessDenied
        }
        return granted
    }

    func sync(actionItems: [ActionItem]) async throws -> ReminderSyncResult {
        guard !actionItems.isEmpty else {
            return ReminderSyncResult(items: [], createdCount: 0, updatedCount: 0, removedCount: 0, unchangedCount: 0)
        }

        var syncedItems: [ActionItem] = []
        var createdCount = 0
        var updatedCount = 0
        var removedCount = 0
        var unchangedCount = 0
        guard let calendar = writableReminderCalendar() else {
            throw ReminderError.noWritableCalendar
        }

        for item in actionItems {
            var updatedItem = item
            let existing = existingReminder(for: item.linkedReminderID)

            if item.selectedForExport {
                let reminder = existing ?? EKReminder(eventStore: store)
                let notes = notes(for: item)

                if existing == nil {
                    reminder.calendar = calendar
                    reminder.title = item.title
                    reminder.notes = notes
                    if let dueDate = item.dueDate {
                        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
                    } else {
                        reminder.dueDateComponents = nil
                    }

                    do {
                        try store.save(reminder, commit: false)
                        updatedItem.linkedReminderID = reminder.calendarItemIdentifier
                        createdCount += 1
                    } catch {
                        throw ReminderError.saveFailed
                    }
                } else if reminderMatches(reminder, item: item) {
                    unchangedCount += 1
                    updatedItem.linkedReminderID = reminder.calendarItemIdentifier
                } else {
                    reminder.title = item.title
                    reminder.notes = notes
                    if reminder.calendar == nil || !reminder.calendar.allowsContentModifications {
                        reminder.calendar = calendar
                    }
                    if let dueDate = item.dueDate {
                        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
                    } else {
                        reminder.dueDateComponents = nil
                    }

                    do {
                        try store.save(reminder, commit: false)
                        updatedItem.linkedReminderID = reminder.calendarItemIdentifier
                        updatedCount += 1
                    } catch {
                        throw ReminderError.saveFailed
                    }
                }
            } else {
                if let existing {
                    do {
                        try store.remove(existing, commit: false)
                        updatedItem.linkedReminderID = nil
                        removedCount += 1
                    } catch {
                        throw ReminderError.saveFailed
                    }
                } else {
                    if updatedItem.linkedReminderID != nil {
                        updatedItem.linkedReminderID = nil
                        removedCount += 1
                    } else {
                        unchangedCount += 1
                    }
                }
            }

            syncedItems.append(updatedItem)
        }

        try store.commit()
        return ReminderSyncResult(
            items: syncedItems,
            createdCount: createdCount,
            updatedCount: updatedCount,
            removedCount: removedCount,
            unchangedCount: unchangedCount
        )
    }

    private func writableReminderCalendar() -> EKCalendar? {
        if let defaultCalendar = store.defaultCalendarForNewReminders(),
           defaultCalendar.allowsContentModifications {
            return defaultCalendar
        }

        return store.calendars(for: .reminder).first(where: \.allowsContentModifications)
    }

    private func existingReminder(for identifier: String?) -> EKReminder? {
        guard let identifier, !identifier.isEmpty else { return nil }
        return store.calendarItem(withIdentifier: identifier) as? EKReminder
    }

    private func reminderMatches(_ reminder: EKReminder, item: ActionItem) -> Bool {
        let reminderDate = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        let itemDate = item.dueDate.map { Calendar.current.startOfDay(for: $0) }
        let normalizedReminderDate = reminderDate.map { Calendar.current.startOfDay(for: $0) }

        return reminder.title == item.title &&
            reminder.notes == notes(for: item) &&
            normalizedReminderDate == itemDate
    }

    private func notes(for item: ActionItem) -> String? {
        let parts: [String] = [item.details, item.sourceQuote.map { "Source: \($0)" }]
            .compactMap { (value: String?) -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }
}
