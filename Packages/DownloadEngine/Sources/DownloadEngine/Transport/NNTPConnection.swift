//
//  NNTPConnection.swift
//  DownloadEngine
//
//  One authenticated NNTP connection over Network.framework (TLS or plain). An actor: each
//  connection is owned by exactly one pool worker, which issues BODY fetches serially.
//
//  Timeouts are handled by the caller (the pool worker) racing `fetchBody` against a sleep and
//  calling `close()` to abort — while `fetchBody` is suspended awaiting a socket read, the actor
//  is free to service `close()`, which cancels the socket and unblocks the read with an error.
//

import Foundation
import Network

actor NNTPConnection {
    private let config: ServerConfig
    private static let queue = DispatchQueue(label: "de.valentinlehmann.swiftnzb.nntp", attributes: .concurrent)

    private var connection: NWConnection?
    private var framer = LineFramer()
    private var lineQueue: [Data] = []
    private(set) var isClosed = false
    /// Shared across the job's connections so the cap throttles aggregate throughput.
    private let rateLimiter: RateLimiter?

    init(config: ServerConfig, rateLimiter: RateLimiter? = nil) {
        self.config = config
        self.rateLimiter = rateLimiter
    }

    // MARK: - Lifecycle

    /// Establish the TCP/TLS connection, read the greeting, and authenticate.
    func open() async throws {
        guard let port = NWEndpoint.Port(rawValue: UInt16(exactly: config.port) ?? 0) else {
            throw NNTPError.connectionFailed("invalid port \(config.port)")
        }

        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 20
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 30
        let params: NWParameters = config.useSSL
            ? NWParameters(tls: NWProtocolTLS.Options(), tcp: tcp)
            : NWParameters(tls: nil, tcp: tcp)

        let connection = NWConnection(host: NWEndpoint.Host(config.host), port: port, using: params)
        self.connection = connection

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce(cont)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(.success(()))
                case .failed(let error): once.resume(.failure(NNTPError.connectionFailed(String(describing: error))))
                case .cancelled: once.resume(.failure(NNTPError.cancelled))
                default: break
                }
            }
            connection.start(queue: Self.queue)
        }
        // Once connected, demote the handler so later state changes don't try to resume again.
        connection.stateUpdateHandler = { _ in }

        let greeting = try await readStatus()
        guard greeting.code == 200 || greeting.code == 201 else {
            throw NNTPError.badGreeting(greeting.code)
        }

        if let username = config.username, !username.isEmpty {
            try await authenticate(user: username, password: config.password)
        }
    }

    /// Cancel the socket. Safe to call while a `fetchBody` read is in flight — it unblocks it.
    func close() {
        isClosed = true
        connection?.cancel()
        connection = nil
    }

    // MARK: - Commands

    /// Fetch and decode-ready body lines for an article. Returns the dot-unstuffed content lines.
    /// Throws `.articleUnavailable` for 4xx/5xx (e.g. 430 taken-down).
    func fetchBody(messageID: String) async throws -> [Data] {
        try await send("BODY <\(messageID)>")
        let status = try await readStatus()
        switch status.code {
        case 222:
            return try await readBodyLines()
        case let code where code >= 400:
            throw NNTPError.articleUnavailable(code: code)
        default:
            throw NNTPError.protocolError("unexpected BODY response \(status.code)")
        }
    }

    // MARK: - Auth

    private func authenticate(user: String, password: String?) async throws {
        try await send("AUTHINFO USER \(user)")
        let r1 = try await readStatus()
        if r1.code == 281 { return }                 // accepted, no password needed
        guard r1.code == 381 else { throw NNTPError.authenticationFailed(r1.code) }
        guard let password else { throw NNTPError.authenticationFailed(r1.code) }
        try await send("AUTHINFO PASS \(password)")
        let r2 = try await readStatus()
        guard r2.code == 281 else { throw NNTPError.authenticationFailed(r2.code) }
    }

    // MARK: - Wire I/O

    private func send(_ command: String) async throws {
        guard let connection else { throw NNTPError.notConnected }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: NNTP.command(command), completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: NNTPError.connectionFailed(String(describing: error)))
                } else {
                    cont.resume(returning: ())
                }
            })
        }
    }

    private func readStatus() async throws -> NNTPStatus {
        let line = try await nextLine()
        guard let status = NNTPStatus(line: line) else {
            throw NNTPError.protocolError("malformed status line")
        }
        return status
    }

    private func readBodyLines() async throws -> [Data] {
        var lines: [Data] = []
        while true {
            let raw = try await nextLine()
            switch NNTP.processBodyLine(raw) {
            case .terminator: return lines
            case .content(let content): lines.append(content)
            }
        }
    }

    private func nextLine() async throws -> Data {
        while lineQueue.isEmpty {
            let chunk = try await receiveChunk()
            lineQueue.append(contentsOf: framer.append(chunk))
        }
        return lineQueue.removeFirst()
    }

    private func receiveChunk() async throws -> Data {
        let data = try await rawReceive()
        // Throttle aggregate throughput against the shared bucket (no-op when unlimited).
        await rateLimiter?.take(data.count)
        return data
    }

    private func rawReceive() async throws -> Data {
        guard let connection else { throw NNTPError.notConnected }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, isComplete, error in
                if let error {
                    cont.resume(throwing: NNTPError.connectionFailed(String(describing: error)))
                } else if let data, !data.isEmpty {
                    cont.resume(returning: data)
                } else if isComplete {
                    cont.resume(throwing: NNTPError.connectionClosed)
                } else {
                    cont.resume(throwing: NNTPError.connectionClosed)
                }
            }
        }
    }
}

/// Guards a continuation so it resumes exactly once, even though `stateUpdateHandler` may fire
/// multiple times off the actor's executor.
private final class ResumeOnce: @unchecked Sendable {
    private var cont: CheckedContinuation<Void, Error>?
    private let lock = NSLock()

    init(_ cont: CheckedContinuation<Void, Error>) { self.cont = cont }

    func resume(_ result: Result<Void, Error>) {
        lock.lock()
        let c = cont
        cont = nil
        lock.unlock()
        guard let c else { return }
        switch result {
        case .success: c.resume()
        case .failure(let error): c.resume(throwing: error)
        }
    }
}
