import SwiftUI

// MARK: - StatisticsRow
/// Reusable row that shows a monospaced digest value with a copy-to-clipboard button.
/// It mirrors the original layout and behaviors (font, selection, truncation, disabled state,
/// bounce symbol effect, and sensory feedback) to maintain visuals and functionality.
struct StatisticsRow: View {
    let title: String
    let value: String
    let copyHelp: String
    @Binding var copyTrigger: Int
    let copyAction: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Left: title takes only needed space
            Text(title)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            // Right: value + copy button take remaining width, right-aligned
            HStack(spacing: 8) {
                Text(value.isEmpty ? "Calculating…" : value)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button {
                    guard !(value.isEmpty || value == "—") else { return }
                    copyAction(value)
                    copyTrigger += 1
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.secondary)
                        .symbolEffect(.bounce, value: copyTrigger)
                }
                .buttonStyle(.borderless)
                .help(copyHelp)
                .disabled(value.isEmpty || value == "—")
                .sensoryFeedback(.success, trigger: copyTrigger)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}
