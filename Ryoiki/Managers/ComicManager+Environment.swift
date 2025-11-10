import SwiftUI

private struct ComicManagerKey: EnvironmentKey {
    static let defaultValue: ComicManager = ComicManager(httpClient: HTTPClient())
}

extension EnvironmentValues {
    var comicManager: ComicManager {
        get { self[ComicManagerKey.self] }
        set { self[ComicManagerKey.self] = newValue }
    }
}
