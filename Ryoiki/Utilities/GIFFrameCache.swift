import Foundation

final class GIFFrameCache {
    static let shared = GIFFrameCache()

    private var storage: [URL: [GIFFrame]] = [:]
    private let queue = DispatchQueue(label: "gif.frame.cache", attributes: .concurrent)

    private init() {}

    func frames(for url: URL) -> [GIFFrame]? {
        var result: [GIFFrame]?
        queue.sync { result = storage[url] }
        return result
    }

    func setFrames(_ frames: [GIFFrame], for url: URL) {
        queue.async(flags: .barrier) { [frames] in
            self.storage[url] = frames
        }
    }

    func removeFrames(for url: URL) {
        queue.async(flags: .barrier) {
            self.storage.removeValue(forKey: url)
        }
    }

    func removeAll() {
        queue.async(flags: .barrier) {
            self.storage.removeAll()
        }
    }
}
