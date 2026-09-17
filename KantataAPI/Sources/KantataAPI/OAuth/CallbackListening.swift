public protocol CallbackListening: Sendable {
    /// Starts listening on the configured port (or an OS-assigned
    /// ephemeral port if the configured port is 0) and returns the
    /// actual bound port.
    func start() async throws -> UInt16
    /// Suspends until a request arrives, returning its query parameters.
    func waitForCallback() async throws -> [String: String]
    /// Stops listening. If a call to `waitForCallback()` is in flight,
    /// it throws a cancellation error.
    func stop()
}
