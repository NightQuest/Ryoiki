import SwiftUI

private struct ComicManagerKey: EnvironmentKey {
    static let defaultValue: ComicManager = ComicManager()
}

extension EnvironmentValues {
    var comicManager: ComicManager {
        get { self[ComicManagerKey.self] }
        set { self[ComicManagerKey.self] = newValue }
    }
}
