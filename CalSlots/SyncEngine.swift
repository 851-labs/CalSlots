import Foundation
import Observation
import HealthKit
import EventKit

/// Coordinates a sync pass: pull workout changes from HealthKit and mirror them
/// into the calendar the user picked. Observable so the UI can reflect progress.
///
/// A shared instance is used so the `AppDelegate` (background relaunch) and the
/// SwiftUI views drive the same engine.
@MainActor
@Observable
final class SyncEngine {
    static let shared = SyncEngine()

    enum Status: Equatable {
        case idle
        case syncing
        case error(String)
    }

    private let health = HealthKitService()
    private let calendar = CalendarService()
    private let store = SyncStore()

    private(set) var status: Status = .idle
    private(set) var calendarAuthorized = false
    private(set) var isObserving = false
    private(set) var availableCalendars: [CalendarOption] = []

    var healthAvailable: Bool { HealthKitService.isAvailable }
    var lastSyncDate: Date? { store.state.lastSyncDate }
    var syncedCount: Int { store.state.workoutEventIDs.count }
    var selectedCalendarID: String? { store.state.calendarIdentifier }
    var needsCalendarSelection: Bool { calendarAuthorized && selectedCalendarID == nil }

    private init() {}

    /// Called once at launch (foreground or background). Requests permissions and,
    /// if a destination calendar is already chosen, syncs and starts observing.
    func bootstrap() async {
        guard healthAvailable else {
            status = .error("Health data isn't available on this device.")
            return
        }
        do {
            try await health.requestAuthorization()
            calendarAuthorized = try await calendar.requestAccess()
            guard calendarAuthorized else {
                status = .error("Calendar access was denied. Enable it in Settings.")
                return
            }

            availableCalendars = calendar.writableCalendarOptions()

            // Drop a stale selection (e.g. the calendar was deleted).
            if let id = selectedCalendarID, !availableCalendars.contains(where: { $0.id == id }) {
                store.update { $0.calendarIdentifier = nil }
                store.save()
            }

            if selectedCalendarID != nil {
                await sync()
                await startObservingIfNeeded()
            }
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    /// Chooses the destination calendar. Switching resets the anchor so the full
    /// history populates the newly chosen calendar.
    func selectCalendar(id: String) {
        guard !id.isEmpty, id != selectedCalendarID else { return }
        store.update {
            $0.calendarIdentifier = id
            $0.anchorData = nil
            $0.workoutEventIDs = [:]
        }
        store.save()
        Task {
            await sync()
            await startObservingIfNeeded()
        }
    }

    private func startObservingIfNeeded() async {
        guard !isObserving else { return }
        do {
            try await health.startObserving { [weak self] in
                await self?.sync()
            }
            isObserving = true
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    /// Runs a single idempotent sync pass into the selected calendar.
    func sync() async {
        guard status != .syncing else { return }
        guard let calendarID = selectedCalendarID,
              let target = calendar.calendar(withIdentifier: calendarID) else {
            status = .idle
            return
        }
        status = .syncing
        do {
            let changes = try await health.fetchChanges(since: store.state.anchorData)

            for workout in changes.added {
                let info = health.info(for: workout)
                let identifier = try calendar.addEvent(
                    to: target,
                    title: WorkoutEventBuilder.title(for: info),
                    notes: WorkoutEventBuilder.notes(for: info),
                    start: info.start,
                    end: info.end
                )
                store.update { $0.workoutEventIDs[workout.uuid.uuidString] = identifier }
            }

            for uuid in changes.deletedUUIDs {
                let key = uuid.uuidString
                if let identifier = store.state.workoutEventIDs[key] {
                    try calendar.removeEvent(identifier: identifier)
                    store.update { $0.workoutEventIDs[key] = nil }
                }
            }

            try calendar.commit()

            store.update {
                $0.anchorData = HealthKitService.archive(changes.newAnchor)
                $0.lastSyncDate = Date()
            }
            store.save()
            status = .idle
        } catch {
            status = .error(error.localizedDescription)
        }
    }
}
