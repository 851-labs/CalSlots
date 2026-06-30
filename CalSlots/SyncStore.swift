import Foundation

/// The persisted state that lets sync resume across launches (including
/// background relaunches triggered by HealthKit).
struct SyncState: Codable {
    /// Archived `HKQueryAnchor` marking the last workout we processed.
    var anchorData: Data?
    /// Identifier of the dedicated "Workouts" calendar we created.
    var calendarIdentifier: String?
    /// Maps a workout UUID string to the calendar event identifier we created for it.
    var workoutEventIDs: [String: String] = [:]
    /// When the last successful sync pass completed.
    var lastSyncDate: Date?
}

/// Loads and saves `SyncState` as JSON in Application Support.
final class SyncStore {
    private let url: URL
    private(set) var state: SyncState

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("CalSlotsSyncState.json")

        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(SyncState.self, from: data) {
            state = decoded
        } else {
            state = SyncState()
        }
    }

    /// Mutate the in-memory state. Call `save()` to persist.
    func update(_ mutate: (inout SyncState) -> Void) {
        mutate(&state)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
