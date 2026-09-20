import Foundation
import HealthKit
import Observation

@Observable
@MainActor
final class HealthKitManager {
    static let shared = HealthKitManager()

    var isAuthorized: Bool = false
    var steps: Int = 0
    var activeEnergyKcal: Double = 0
    var exerciseMinutes: Int = 0

    @ObservationIgnored private let store = HKHealthStore()

    /// True only when HealthKit is available AND the app has the required
    /// NSHealthShareUsageDescription plist key. Without the key, calling
    /// requestAuthorization throws an NSException that bypasses Swift catch.
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
        guard canUseHealthKit else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
            await fetchTodayMetrics()
        } catch {
            isAuthorized = false
        }
    }

    // MARK: - Fetch Today's Totals
    func fetchTodayMetrics() async {
        guard canUseHealthKit, isAuthorized else { return }
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
