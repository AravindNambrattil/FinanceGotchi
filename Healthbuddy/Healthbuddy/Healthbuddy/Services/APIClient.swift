import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case networkUnreachable
    case decodingFailed(Error)
    case serverError(Int)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL."
        case .networkUnreachable: return "Can't reach Mochi right now. Check your Wi-Fi connection."
        case .decodingFailed: return "Unexpected response from server."
        case .serverError(let code): return "Server error (\(code))."
        case .unknown(let e): return e.localizedDescription
        }
    }
}

actor APIClient {
    static let shared = APIClient()
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        session = URLSession(configuration: config)
    }

    // MARK: - GET
    func get<T: Decodable>(_ path: String, baseURL: URL) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        let (data, response) = try await fetch(url: url)
        try validate(response: response)
        return try decode(data)
    }

    // MARK: - POST
    func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        baseURL: URL
    ) async throws -> Response {
        try await send("POST", path, body: body, baseURL: baseURL)
    }

    // MARK: - PUT
    func put<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        baseURL: URL
    ) async throws -> Response {
        try await send("PUT", path, body: body, baseURL: baseURL)
    }

    // MARK: - DELETE
    /// `query` is passed separately because `appendingPathComponent` would percent-encode a `?` in `path`.
    func delete<Response: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        baseURL: URL
    ) async throws -> Response {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (data, response) = try await fetch(urlRequest: request)
        try validate(response: response)
        return try decode(data)
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ method: String,
        _ path: String,
        body: Body,
        baseURL: URL
    ) async throws -> Response {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONCoding.makeEncoder().encode(body)

        let (data, response) = try await fetch(urlRequest: request)
        try validate(response: response)
        return try decode(data)
    }

    // MARK: - Helpers
    private func fetch(url: URL) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(from: url)
        } catch {
            throw mapNetworkError(error)
        }
    }

    private func fetch(urlRequest: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: urlRequest)
        } catch {
            throw mapNetworkError(error)
        }
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.serverError(http.statusCode)
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONCoding.makeDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    private func mapNetworkError(_ error: Error) -> APIError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain &&
            [NSURLErrorNotConnectedToInternet,
             NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost,
             NSURLErrorTimedOut,
             NSURLErrorNetworkConnectionLost].contains(nsError.code) {
            return .networkUnreachable
        }
        return .unknown(error)
    }
}
