import Foundation
import EventKit

/// A writable calendar the user can pick as the sync destination.
struct CalendarOption: Identifiable, Hashable {
    let id: String
    let title: String
}

/// Wraps EventKit access: full-access authorization, listing the calendars the
/// user can sync into, and creating/removing events.
final class CalendarService {
    private let store = EKEventStore()

    // MARK: - Authorization

    /// Requests full access (needed to enumerate calendars and add events).
    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    // MARK: - Calendars

    /// Calendars the user can add events to (editable, not subscribed), sorted by title.
    func writableCalendarOptions() -> [CalendarOption] {
        store.calendars(for: .event)
            .filter { $0.allowsContentModifications && !$0.isSubscribed }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { CalendarOption(id: $0.calendarIdentifier, title: $0.title) }
    }

    func calendar(withIdentifier id: String) -> EKCalendar? {
        store.calendar(withIdentifier: id)
    }

    // MARK: - Events

    /// Creates an event but does not commit (batch with `commit()`).
    /// Returns the new event's identifier.
    func addEvent(to calendar: EKCalendar, title: String, notes: String, start: Date, end: Date) throws -> String {
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.notes = notes
        event.startDate = start
        event.endDate = end
        try store.save(event, span: .thisEvent, commit: false)
        return event.eventIdentifier
    }

    /// Removes a previously created event but does not commit.
    func removeEvent(identifier: String) throws {
        guard let event = store.event(withIdentifier: identifier) else { return }
        try store.remove(event, span: .thisEvent, commit: false)
    }

    func commit() throws {
        try store.commit()
    }
}
