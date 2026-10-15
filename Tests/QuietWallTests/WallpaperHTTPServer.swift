import Foundation
import Network
import XCTest

/// Loopback-only fixture server: tests never contact an external media provider.
final class WallpaperHTTPServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "QuietWall.HTTPTests")
    private var connections: [NWConnection] = []
    let requestReceived = XCTestExpectation(description: "HTTP request received")

    init(body: Data, contentType: String = "application/octet-stream") throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let ready = XCTestExpectation(description: "HTTP server ready")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
            if case .failed = state { ready.fulfill() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.receive(connection, accumulated: Data(), body: body, contentType: contentType)
        }
        listener.start(queue: queue)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed, listener.port != nil else {
            listener.cancel()
            throw URLError(.cannotConnectToHost)
        }
    }

    func url(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:\(listener.port!.rawValue)\(path)")!
    }

    func stop() {
        queue.sync {
            listener.cancel()
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    private func receive(_ connection: NWConnection, accumulated: Data, body: Data, contentType: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self, error == nil else { connection.cancel(); return }
            let request = accumulated + (data ?? Data())
            guard let text = String(data: request, encoding: .utf8), text.contains("\r\n\r\n") else {
                if complete { connection.cancel() }
                else { self.receive(connection, accumulated: request, body: body, contentType: contentType) }
                return
            }
            self.requestReceived.fulfill()
            let path = text.components(separatedBy: " ").dropFirst().first ?? "/"
            if path == "/slow" { return } // Leave response pending so cancellation can be exercised.
            let status = path == "/missing" ? "404 Not Found" : (path == "/redirect" ? "302 Found" : "200 OK")
            let payload = path == "/redirect" ? Data() : body
            let location = path == "/redirect" ? "Location: /media\r\n" : ""
            let headers = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(payload.count)\r\n\(location)Connection: close\r\n\r\n"
            connection.send(content: Data(headers.utf8) + payload, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
