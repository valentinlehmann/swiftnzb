//
//  ServerProbe.swift
//  DownloadEngine
//
//  A lightweight "can we connect + authenticate?" check for the server-setup UI.
//

import Foundation

public enum ServerProbe {
    /// Open, authenticate, and immediately close a connection. Returns nil on success or a
    /// human-readable reason on failure.
    public static func test(_ config: ServerConfig) async -> String? {
        let connection = NNTPConnection(config: config)
        do {
            try await connection.open()
            await connection.close()
            return nil
        } catch let error as NNTPError {
            await connection.close()
            switch error {
            case .authenticationFailed: return "Authentication failed — check your username and password."
            case .badGreeting: return "The server responded unexpectedly."
            case .connectionFailed(let detail): return "Could not connect: \(detail)"
            case .timeout: return "The connection timed out."
            default: return "Connection failed (\(error))."
            }
        } catch {
            await connection.close()
            return error.localizedDescription
        }
    }
}
