import Foundation
import Observation

@Observable
@MainActor
final class HealthViewModel {
    var isSyncing: Bool = false
    var syncMessage: String?
    var lastSyncDate: Date?

    @ObservationIgnored private let healthKit: HealthKitManager
    @ObservationIgnored private let service: PetServiceProtocol
    @ObservationIgnored private let settings: AppSettings

    var isAuthorized: Bool { healthKit.isAuthorized }
    var steps: Int { healthKit.steps }
    var activeEnergyKcal: Double { healthKit.activeEnergyKcal }
    var exerciseMinutes: Int { healthKit.exerciseMinutes }
    /// False when only steps are known (free-account build using the pedometer instead of HealthKit).
    var hasEnergyAndExercise: Bool { healthKit.hasEnergyAndExercise }

    init(
        healthKit: HealthKitManager = .shared,
        service: PetServiceProtocol? = nil,
        settings: AppSettings = .shared
    ) {
        self.healthKit = healthKit
        self.settings = settings
        self.service = service ?? PetService.makeService(settings: settings)
    }

    // MARK: - Authorize HealthKit
    func requestAuthorization() async {
        await healthKit.requestAuthorization()
    }

    // MARK: - Sync to Backend
    func syncActivity(petId: String) async {
        guard healthKit.isAuthorized else {
            await requestAuthorization()
            return
        }
        isSyncing = true
        syncMessage = nil
        await healthKit.fetchTodayMetrics()
        do {
            let response = try await service.sendHealth(petId: petId, payload: healthKit.healthPayload)
            syncMessage = response.message
            lastSyncDate = Date()
        } catch {
            syncMessage = error.localizedDescription
        }
        isSyncing = false
    }
}
