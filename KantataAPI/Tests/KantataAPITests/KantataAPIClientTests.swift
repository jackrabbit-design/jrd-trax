import Testing
import Foundation
@testable import KantataAPI

final class StubHTTPTransport: HTTPTransport, @unchecked Sendable {
    var responseData: Data = Data()
    var statusCode: Int = 200
    private(set) var lastRequest: URLRequest?

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (responseData, response)
    }
}

@Suite("Kantata API client")
struct KantataAPIClientTests {
    @Test("fetchTaskStatuses decodes a list and sets the Authorization header")
    func fetchTaskStatuses() async throws {
        let transport = StubHTTPTransport()
        transport.responseData = #"[{"id": "s1", "name": "In Progress"}]"#.data(using: .utf8)!
        let client = KantataAPIClient(transport: transport, tokenProvider: { "tok-123" })

        let statuses = try await client.fetchTaskStatuses()
        #expect(statuses == [TaskStatusDTO(id: "s1", name: "In Progress")])
        #expect(transport.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer tok-123")
    }

    @Test("fetchCurrentUser decodes a single object")
    func fetchCurrentUser() async throws {
        let transport = StubHTTPTransport()
        transport.responseData = #"{"id": "u1", "full_name": "Chris K", "email": "ck@jumpingjackrabbit.com"}"#.data(using: .utf8)!
        let client = KantataAPIClient(transport: transport, tokenProvider: { "tok" })

        let user = try await client.fetchCurrentUser()
        #expect(user.fullName == "Chris K")
    }

    @Test("createTimeEntry posts the request body and decodes the response")
    func createTimeEntry() async throws {
        let transport = StubHTTPTransport()
        transport.responseData = #"{"id": "te1", "story_id": "st1", "date": "2026-09-16", "hours": 1.5}"#.data(using: .utf8)!
        let client = KantataAPIClient(transport: transport, tokenProvider: { "tok" })

        let result = try await client.createTimeEntry(TimeEntryCreateRequest(storyId: "st1", date: "2026-09-16", hours: 1.5))
        #expect(result.hours == 1.5)
        #expect(transport.lastRequest?.httpMethod == "POST")
    }

    @Test("401 response throws unauthorized")
    func unauthorized() async throws {
        let transport = StubHTTPTransport()
        transport.statusCode = 401
        let client = KantataAPIClient(transport: transport, tokenProvider: { "tok" })

        await #expect(throws: KantataAPIError.unauthorized) {
            try await client.fetchTaskStatuses()
        }
    }

    @Test("malformed JSON throws a decoding error, not a crash")
    func malformedResponse() async throws {
        let transport = StubHTTPTransport()
        transport.responseData = #"{"not": "a list"}"#.data(using: .utf8)!
        let client = KantataAPIClient(transport: transport, tokenProvider: { "tok" })

        do {
            _ = try await client.fetchTaskStatuses()
            Issue.record("expected a decoding error")
        } catch let error as KantataAPIError {
            guard case .decodingFailed = error else {
                Issue.record("expected .decodingFailed, got \(error)")
                return
            }
        }
    }

    @Test("non-2xx, non-401 response throws httpError with the status code")
    func genericHTTPError() async throws {
        let transport = StubHTTPTransport()
        transport.statusCode = 500
        let client = KantataAPIClient(transport: transport, tokenProvider: { "tok" })

        await #expect(throws: KantataAPIError.httpError(500)) {
            try await client.fetchTaskStatuses()
        }
    }

    @Test("fetchDailyScheduledHours sends a from/to date range query")
    func fetchDailyScheduledHoursDateRange() async throws {
        let transport = StubHTTPTransport()
        transport.responseData = "[]".data(using: .utf8)!
        let client = KantataAPIClient(transport: transport, tokenProvider: { "tok" })

        _ = try await client.fetchDailyScheduledHours(from: "2026-09-01", to: "2026-09-30")

        let query = transport.lastRequest?.url?.query ?? ""
        #expect(query.contains("from=2026-09-01"))
        #expect(query.contains("to=2026-09-30"))
    }

    @Test("createStoryStateChange posts the request body and decodes the response")
    func createStoryStateChange() async throws {
        let transport = StubHTTPTransport()
        transport.responseData = #"{"id": "c1", "story_id": "st1", "status_id": "s2"}"#.data(using: .utf8)!
        let client = KantataAPIClient(transport: transport, tokenProvider: { "tok" })

        let result = try await client.createStoryStateChange(StoryStateChangeCreateRequest(storyId: "st1", statusId: "s2"))
        #expect(result.statusId == "s2")
        #expect(transport.lastRequest?.httpMethod == "POST")
    }
}
