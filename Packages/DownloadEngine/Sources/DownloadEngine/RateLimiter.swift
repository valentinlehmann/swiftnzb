//
//  RateLimiter.swift
//  DownloadEngine
//
//  Token-bucket limiter shared by all of a job's connections, so the configured cap throttles
//  *aggregate* throughput. Each connection awaits `take(_:)` for the bytes it just received;
//  when the bucket is empty the connection suspends, which naturally backpressures the socket.
//

import Foundation

actor RateLimiter {
    private let bytesPerSecond: Double
    private let capacity: Double            // ~1 second of burst
    private var tokens: Double
    private var last: ContinuousClock.Instant

    /// nil when unlimited (cap <= 0).
    init?(bytesPerSecond: Int) {
        guard bytesPerSecond > 0 else { return nil }
        self.bytesPerSecond = Double(bytesPerSecond)
        self.capacity = Double(bytesPerSecond)
        self.tokens = Double(bytesPerSecond)
        self.last = ContinuousClock().now
    }

    /// Consume `n` bytes of budget, sleeping if the bucket has run dry.
    func take(_ n: Int) async {
        guard n > 0 else { return }
        refill()
        tokens -= Double(n)
        if tokens < 0 {
            let deficitSeconds = -tokens / bytesPerSecond
            try? await Task.sleep(for: .seconds(deficitSeconds))
            tokens = 0
            // Reset the clock so the next refill doesn't re-credit the interval we just slept
            // through (which would halve the effective throttle).
            last = ContinuousClock().now
        }
    }

    private func refill() {
        let now = ContinuousClock().now
        let elapsed = now - last
        last = now
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
        tokens = min(capacity, tokens + seconds * bytesPerSecond)
    }
}
