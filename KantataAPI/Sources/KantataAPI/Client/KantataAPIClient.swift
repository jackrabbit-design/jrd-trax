import Foundation

public struct KantataAPIClient: Sendable {
    private let transport: any HTTPTransport
    private let baseURL: URL
    private let tokenProvider: @Sendable () -> String?

    public init(
        transport: any HTTPTransport,
        baseURL: URL = URL(string: "https://api.mavenlink.com/api/v1/")!,
        tokenProvider: @escaping @Sendable () -> String?
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
    }

    public func fetchTaskStatuses() async throws -> [TaskStatusDTO] {
        try await get("task_statuses")
    }

    public func fetchStatusSets() async throws -> [StatusSetDTO] {
        try await get("task_status_sets")
    }

    public func fetchAssignments() async throws -> [AssignmentDTO] {
        try await get("assignments")
    }

    public func fetchDailyScheduledHours(from: String, to: String) async throws -> [DailyScheduledHourDTO] {
        try await get("story_allocation_days", queryItems: [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
        ])
    }

    public func fetchStories() async throws -> [StoryDTO] {
        try await get("stories")
    }

    public func fetchCurrentUser() async throws -> UserDTO {
        try await get("me")
    }

    public func createTimeEntry(_ requestBody: TimeEntryCreateRequest) async throws -> TimeEntryDTO {
        try await post("time_entries", body: requestBody)
    }

    public func createStoryStateChange(_ requestBody: StoryStateChangeCreateRequest) async throws -> StoryStateChangeDTO {
        try await post("story_state_changes", body: requestBody)
    }

    private func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        applyAuth(&request)
        return try await send(request)
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&request)
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await transport.send(request)
        try Self.validate(response)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw KantataAPIError.decodingFailed(error)
        }
    }

    private func applyAuth(_ request: inout URLRequest) {
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 { throw KantataAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            throw KantataAPIError.httpError(http.statusCode)
        }
    }
}
