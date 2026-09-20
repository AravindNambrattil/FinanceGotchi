import CoreMotion
import Foundation
import HealthKit
import Observation

/// Today's activity numbers. Two sources, picked by what the build can do:
/// - **HealthKit** (steps, active energy, exercise minutes) when the project has the HealthKit entitlement and the
///   `NSHealthShareUsageDescription` plist key. That needs a paid Apple developer account.
/// - **CoreMotion's pedometer** (steps only) otherwise. It works with a free account and only needs
///   `NSMotionUsageDescription`.
@Observable
@MainActor
final class HealthKitManager {
    static let shared = HealthKitManager()

    var isAuthorized: Bool = false
    var steps: Int = 0
    var activeEnergyKcal: Double = 0
    var exerciseMinutes: Int = 0

    /// True when active energy and exercise minutes are real numbers (HealthKit); false when only steps are known.
    var hasEnergyAndExercise: Bool { canUseHealthKit }

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private let pedometer = CMPedometer()

    /// True only when HealthKit is available AND the app has the required NSHealthShareUsageDescription plist key.
    /// Without the key (or the entitlement that goes with it), calling requestAuthorization throws an NSException that
    /// bypasses Swift catch, so this must stay false for builds signed without a paid account.
    @ObservationIgnored private let canUseHealthKit: Bool = {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let key = Bundle.main.object(forInfoDictionaryKey: "NSHealthShareUsageDescription")
        return key != nil
    }()

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if let t = HKQuantityType.quantityType(forIdentifier: .stepCount) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(t) }
        if let t = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) { types.insert(t) }
        return types
    }

    private init() {}

    // MARK: - Authorization
    func requestAuthorization() async {
        if canUseHealthKit {
            do {
                try await store.requestAuthorization(toShare: [], read: readTypes)
                isAuthorized = true
                await fetchTodayMetrics()
            } catch {
                isAuthorized = false
            }
        } else {
            // Asking for today's steps is what makes iOS show the Motion & Fitness permission prompt.
            if let today = await pedometerSteps() {
                isAuthorized = true
                steps = today
            } else {
                isAuthorized = false
            }
        }
    }

    // MARK: - Fetch Today's Totals
    func fetchTodayMetrics() async {
        guard isAuthorized else { return }
        guard canUseHealthKit else {
            if let today = await pedometerSteps() { steps = today }
            return
        }
        async let stepsResult = querySum(type: .stepCount, unit: HKUnit.count())
        async let energyResult = querySum(type: .activeEnergyBurned, unit: HKUnit.kilocalorie())
        async let exerciseResult = querySum(type: .appleExerciseTime, unit: HKUnit.minute())

        let (s, e, ex) = await (stepsResult, energyResult, exerciseResult)
        steps = Int(s)
        activeEnergyKcal = e
        exerciseMinutes = Int(ex)
    }

    // MARK: - Build Payload
    var healthPayload: HealthPayload {
        HealthPayload(
            steps: steps,
            activeEnergyKcal: activeEnergyKcal,
            exerciseMinutes: exerciseMinutes
        )
    }

    // MARK: - Private Helpers
    /// Steps since midnight, or nil when the pedometer is missing (simulator) or permission was refused.
    private func pedometerSteps() async -> Int? {
        guard CMPedometer.isStepCountingAvailable() else { return nil }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: startOfDay, to: Date()) { data, error in
                continuation.resume(returning: error == nil ? data?.numberOfSteps.intValue : nil)
            }
        }
    }

    private func querySum(type identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }
}
