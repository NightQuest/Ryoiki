import SwiftUI

// MARK: - DigestRow
/// Reusable row that shows a monospaced digest value with a copy-to-clipboard button.
/// It mirrors the original layout and behaviors (font, selection, truncation, disabled state,
/// bounce symbol effect, and sensory feedback) to maintain visuals and functionality.
struct DigestRow: View {
    let title: String
    let value: String
    let copyHelp: String
    @Binding var copyTrigger: Int
    let copyAction: (String) -> Void

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(value.isEmpty ? "Calculating…" : value)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
            .padding(.leading)
        }
    }
}
