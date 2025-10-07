import SwiftUI

// MARK: - BorderlessGroupBoxStyle
/// GroupBoxStyle without default borders, used for cleaner sections.
struct BorderlessGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            configuration.label
                .font(.headline)
            configuration.content
        }
    }
}
