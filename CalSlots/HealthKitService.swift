import Foundation
import HealthKit

/// Wraps HealthKit access: authorization, incremental workout queries, and
/// background delivery.
final class HealthKitService {
    private let store = HKHealthStore()
    private let workoutType = HKObjectType.workoutType()
    private var observerQuery: HKObserverQuery?

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Result of an incremental query: new workouts, UUIDs of deleted workouts,
    /// and the anchor to persist for next time.
    struct Changes {
        var added: [HKWorkout]
        var deletedUUIDs: [UUID]
        var newAnchor: HKQueryAnchor
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: [workoutType])
    }

    // MARK: - Incremental fetch

    /// Fetches workouts added or deleted since `anchorData`. A nil anchor
    /// returns the entire workout history.
    func fetchChanges(since anchorData: Data?) async throws -> Changes {
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.workout()],
            anchor: Self.anchor(from: anchorData),
            limit: HKObjectQueryNoLimit
        )
        let result = try await descriptor.result(for: store)
        return Changes(
            added: result.addedSamples,
            deletedUUIDs: result.deletedObjects.map(\.uuid),
            newAnchor: result.newAnchor
        )
    }

    // MARK: - Background delivery

    /// Enables background delivery and installs a long-lived observer query.
    /// `onChange` runs whenever HealthKit reports new or deleted workouts.
    func startObserving(_ onChange: @escaping @Sendable () async -> Void) async throws {
        try await enableBackgroundDelivery()

        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { _, completionHandler, _ in
            Task {
                await onChange()
                // Must always be called so HealthKit knows we handled the update.
                completionHandler()
            }
        }
        store.execute(query)
        observerQuery = query
    }

    private func enableBackgroundDelivery() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Mapping

    /// Extracts a HealthKit-free `WorkoutInfo` from an `HKWorkout`.
    func info(for workout: HKWorkout) -> WorkoutInfo {
        WorkoutInfo(
            activityName: Self.name(for: workout.workoutActivityType),
            symbol: Self.symbol(for: workout.workoutActivityType),
            start: workout.startDate,
            end: workout.endDate,
            duration: workout.duration,
            distanceMeters: distanceMeters(for: workout),
            energyKilocalories: energyKilocalories(for: workout)
        )
    }

    private func energyKilocalories(for workout: HKWorkout) -> Double? {
        let type = HKQuantityType(.activeEnergyBurned)
        return workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: .kilocalorie())
    }

    private func distanceMeters(for workout: HKWorkout) -> Double? {
        // Distance is recorded under an activity-specific quantity type; try the
        // common ones and use the first that has data.
        let identifiers: [HKQuantityTypeIdentifier] = [
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
            .distanceWheelchair,
            .distanceDownhillSnowSports
        ]
        for identifier in identifiers {
            if let meters = workout.statistics(for: HKQuantityType(identifier))?
                .sumQuantity()?
                .doubleValue(for: .meter()) {
                return meters
            }
        }
        return nil
    }

    // MARK: - Anchor archiving

    private static func anchor(from data: Data?) -> HKQueryAnchor? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    static func archive(_ anchor: HKQueryAnchor) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }

    // MARK: - Activity display

    private static func name(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "Running"
        case .walking: "Walking"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .hiking: "Hiking"
        case .yoga: "Yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: "Strength Training"
        case .highIntensityIntervalTraining: "HIIT"
        case .rowing: "Rowing"
        case .elliptical: "Elliptical"
        case .pilates: "Pilates"
        case .dance, .cardioDance: "Dance"
        case .coreTraining: "Core Training"
        case .stairClimbing, .stairs: "Stair Climbing"
        case .jumpRope: "Jump Rope"
        case .kickboxing: "Kickboxing"
        case .boxing: "Boxing"
        case .soccer: "Soccer"
        case .basketball: "Basketball"
        case .tennis: "Tennis"
        case .golf: "Golf"
        default: "Workout"
        }
    }

    private static func symbol(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "🏃"
        case .walking, .hiking: "🚶"
        case .cycling: "🚴"
        case .swimming: "🏊"
        case .yoga, .pilates: "🧘"
        case .functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining: "🏋️"
        case .rowing: "🚣"
        case .jumpRope: "🤸"
        case .boxing, .kickboxing: "🥊"
        case .soccer: "⚽️"
        case .basketball: "🏀"
        case .tennis: "🎾"
        case .golf: "⛳️"
        case .dance, .cardioDance: "💃"
        default: "🏅"
        }
    }
}
