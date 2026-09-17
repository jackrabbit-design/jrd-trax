import Foundation
import Network

public final class LoopbackListener: CallbackListening, @unchecked Sendable {
    private let requestedPort: UInt16
    private var listener: NWListener?
    private var continuation: CheckedContinuation<[String: String], Error>?
    private let lock = NSLock()

    public init(port: UInt16) {
        self.requestedPort = port
    }

    public func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        let nwPort = requestedPort == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: requestedPort)!
        let listener = try NWListener(using: params, on: nwPort)
        self.listener = listener

        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    let port = listener.port?.rawValue ?? self?.requestedPort ?? 0
                    continuation.resume(returning: port)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: .main)
        }
    }

    public func waitForCallback() async throws -> [String: String] {
        try await withCheckedThrowingContinuation { continuation in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(throwing: CancellationError())
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let request = String(data: data, encoding: .utf8),
               let parsed = Self.parseRequest(fromRequestLine: request) {
                guard parsed.method == "GET" && parsed.path == "/callback" else {
                    self.respondNotFound(on: connection)
                    return
                }
                self.respond(on: connection)
                self.lock.lock()
                let cont = self.continuation
                self.continuation = nil
                self.lock.unlock()
                cont?.resume(returning: parsed.queryParams)
            } else if let error {
                self.lock.lock()
                let cont = self.continuation
                self.continuation = nil
                self.lock.unlock()
                cont?.resume(throwing: error)
            } else {
                self.respondNotFound(on: connection)
            }
        }
    }

    private func respond(on connection: NWConnection) {
        let body = "<html><body>You can close this window and return to Trax.</body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func respondNotFound(on connection: NWConnection) {
        let body = "<html><body>Not found.</body></html>"
        let response = "HTTP/1.1 404 Not Found\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private struct ParsedRequest {
        let method: String
        let path: String
        let queryParams: [String: String]
    }

    private static func parseRequest(fromRequestLine request: String) -> ParsedRequest? {
        guard let firstLine = request.split(separator: "\r\n").first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let target = String(parts[1])
        guard let components = URLComponents(string: "http://localhost\(target)") else { return nil }
        var result: [String: String] = [:]
        for item in components.queryItems ?? [] {
            result[item.name] = item.value ?? ""
        }
        return ParsedRequest(method: method, path: components.path, queryParams: result)
    }
}
