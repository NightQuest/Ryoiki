import Foundation

actor RateLimiter {
    let minInterval: Duration
    private var lastRequestTimes: [String: ContinuousClock.Instant] = [:]
    private let clock = ContinuousClock()

    init(minInterval: Duration) {
        self.minInterval = minInterval
    }

    static let shared = RateLimiter(minInterval: .milliseconds(250))

    func acquire(for url: URL) async {
        guard let host = url.host else { return }

        let now = clock.now
        if let lastRequest = lastRequestTimes[host] {
            let elapsed = now - lastRequest
            if elapsed < minInterval {
                let sleepDuration = minInterval - elapsed
                try? await clock.sleep(for: sleepDuration)
            }
        }
        lastRequestTimes[host] = clock.now
    }
}
