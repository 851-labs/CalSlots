import Foundation

/// A HealthKit-free description of a workout, used to build a calendar event.
///
/// Keeping this struct free of HealthKit types makes the mapping logic in
/// `WorkoutEventBuilder` easy to unit test without constructing `HKWorkout`s.
struct WorkoutInfo: Equatable {
    var activityName: String
    var symbol: String
    var start: Date
    var end: Date
    var duration: TimeInterval
    var distanceMeters: Double?
    var energyKilocalories: Double?
}

/// Pure mapping from a `WorkoutInfo` to the fields of a calendar event.
/// No side effects — every function here is deterministic given its input.
enum WorkoutEventBuilder {

    /// The event title, e.g. "🏃 Running".
    static func title(for info: WorkoutInfo) -> String {
        "\(info.symbol) \(info.activityName)"
    }

    /// A multi-line notes string summarizing the workout.
    static func notes(for info: WorkoutInfo) -> String {
        var lines: [String] = []
        lines.append("Duration: \(formattedDuration(info.duration))")

        if let distance = info.distanceMeters, distance > 0 {
            let measurement = Measurement(value: distance, unit: UnitLength.meters)
            lines.append("Distance: \(measurement.formatted(.measurement(width: .abbreviated, usage: .road)))")
        }

        if let energy = info.energyKilocalories, energy > 0 {
            let measurement = Measurement(value: energy, unit: UnitEnergy.kilocalories)
            lines.append("Active energy: \(measurement.formatted(.measurement(width: .abbreviated, usage: .workout)))")
        }

        lines.append("Synced from Health by CalSlots")
        return lines.joined(separator: "\n")
    }

    /// Formats a duration as a compact "1h 5m" / "42m" string.
    static func formattedDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
