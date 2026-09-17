import Testing
import Foundation
@testable import KantataAPI

@Suite("Loopback listener")
struct LoopbackListenerTests {
    @Test("captures query parameters from a real local GET request")
    func capturesCallbackParams() async throws {
        let listener = LoopbackListener(port: 0)
        let port = try await listener.start()

        async let paramsTask = listener.waitForCallback()

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/callback?code=abc123&state=xyz")!)
        request.httpMethod = "GET"
        _ = try await URLSession.shared.data(for: request)

        let params = try await paramsTask
        #expect(params["code"] == "abc123")
        #expect(params["state"] == "xyz")

        listener.stop()
    }

    @Test("request to wrong path does not resolve the callback")
    func wrongPathDoesNotResolveCallback() async throws {
        let listener = LoopbackListener(port: 0)
        let port = try await listener.start()

        async let paramsTask = listener.waitForCallback()

        // A forged/unrelated request to a different path should be rejected (404)
        // and must not resolve the pending waitForCallback().
        var wrongPathRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/not-callback?code=forged&state=forged")!)
        wrongPathRequest.httpMethod = "GET"
        let (_, wrongPathResponse) = try await URLSession.shared.data(for: wrongPathRequest)
        #expect((wrongPathResponse as? HTTPURLResponse)?.statusCode == 404)

        // The real callback then arrives on a separate connection and should resolve it.
        var realRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/callback?code=abc123&state=xyz")!)
        realRequest.httpMethod = "GET"
        _ = try await URLSession.shared.data(for: realRequest)

        let params = try await paramsTask
        #expect(params["code"] == "abc123")
        #expect(params["state"] == "xyz")

        listener.stop()
    }

    @Test("stop() while waiting throws a cancellation error")
    func stopCancelsWait() async throws {
        let listener = LoopbackListener(port: 0)
        _ = try await listener.start()

        async let waitTask = listener.waitForCallback()
        try await Task.sleep(nanoseconds: 100_000_000)
        listener.stop()

        do {
            _ = try await waitTask
            Issue.record("Expected waitForCallback() to throw after stop()")
        } catch {
            // Expected: stop() cancels the in-flight waitForCallback().
        }
    }
}
