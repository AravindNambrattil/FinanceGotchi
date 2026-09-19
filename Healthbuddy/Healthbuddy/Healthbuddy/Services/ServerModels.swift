import Foundation

// Wire shapes of the deployed FastAPI backend (`files/main.py`, `files/db.py`). They exist only so `PetService` can
// translate the server's JSON into the app's own models; views never see them.

struct BackendBank: Decodable {
    let synced: Bool
    let checking: Double?
    let savings: Double?
    let reason: String?
}

/// `GET /pets/{id}` and the pet-shaped part of `POST /decision|interact|expense`.
struct BackendPet: Decodable {
    let id: String
    let name: String
    let mood: Int
    let needs: Int
    let energy: Int
    let savingsScore: Int
    let streak: Int
    let connected: Bool?
    let goal: SavingsGoal?
    // Only present on decision / expense responses.
    let message: String?
    let covered: Bool?
    let bank: BackendBank?
}

struct BackendEmergencyFund: Decodable {
    let current: Double
    let target: Double
}

struct BackendActivity: Decodable {
    let id: Int
    let category: String
    let amount: Double
    let description: String?
}

/// `GET /pets/{id}/finance`
struct BackendFinance: Decodable {
    let emergencyFund: BackendEmergencyFund?
    let bank: BackendBank
    let recentActivity: [BackendActivity]
}

/// `POST /pets/{id}/decision`
struct BackendDecisionBody: Encodable {
    let choice: String      // buy | save | later
    let amount: Double
    let offerId: Int?
}

/// `POST /pets/{id}/interact`
struct BackendInteractBody: Encodable {
    let action: String      // feed | play | pet
}
