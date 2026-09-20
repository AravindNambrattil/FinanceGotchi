import Foundation
import Observation

enum LoadState {
    case idle, loading, success, failure(String)
}

@Observable
@MainActor
final class PetViewModel {
    var petState: PetState?
    var companionPet: PetState?
    var loadState: LoadState = .loading
    var reactionMessage: String?
    /// Nil until the first check, or when the server can't be reached.
    var deviceStatus: DeviceStatus?

    @ObservationIgnored private let service: PetServiceProtocol
    @ObservationIgnored private let settings: AppSettings

    init(service: PetServiceProtocol? = nil, settings: AppSettings = .shared) {
        self.settings = settings
        self.service = service ?? PetService.makeService(settings: settings)
    }

    var petId: String { settings.activePetId }
    var companionPetId: String { petId == "mochi" ? "byte" : "mochi" }

    // MARK: - Fetch Main Pet
    func loadPetState() async {
        loadState = .loading
        do {
            petState = try await service.fetchPetState(petId: petId)
            loadState = .success
        } catch {
            loadState = .failure(error.localizedDescription)
        }
    }

    // MARK: - Fetch Companion Pet (background, non-blocking)
    func loadCompanionPet() async {
        do {
            companionPet = try await service.fetchPetState(petId: companionPetId)
        } catch {
            companionPet = nil
        }
    }

    // MARK: - Pet-to-pet interaction (generic hang out)
    func interactWithCompanion() async {
        guard companionPet != nil else { return }
        let interaction = PetInteraction(targetPetId: companionPetId, interactionType: "hang_out")
        do {
            let response = try await service.sendInteraction(petId: petId, interaction: interaction)
            reactionMessage = response.message
            if let updated = response.petState { petState = updated }
        } catch {
            reactionMessage = error.localizedDescription
        }
    }

    func refreshDevice() async {
        deviceStatus = try? await service.fetchDeviceStatus(petId: petId)
    }

    /// Adopt a pet state returned by an action, without the loading flash of a full reload.
    func apply(_ state: PetState) {
        petState = state
        loadState = .success
    }

    func dismissReaction() {
        reactionMessage = nil
    }

    // MARK: - Retry
    func retry() async {
        async let pet: () = loadPetState()
        async let companion: () = loadCompanionPet()
        _ = await (pet, companion)
    }
}

// MARK: - Preview helper
extension PetViewModel {
    static func previewLoaded() -> PetViewModel {
        let vm = PetViewModel(service: MockPetService())
        vm.petState = .mockMochi
        vm.companionPet = .mockByte
        vm.loadState = .success
        return vm
    }
}
