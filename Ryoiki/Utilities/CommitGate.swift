import Foundation

actor CommitGate {
    static let shared = CommitGate()

    private var paused: Bool = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func pause() {
        paused = true
    }

    func resume() {
        paused = false
        let toResume = waiters
        waiters.removeAll()
        for c in toResume { c.resume() }
    }

    func waitIfPaused() async {
        if !paused { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
        }
    }
}
