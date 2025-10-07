import SwiftUI

// Common form input styling used across the app.
struct FormInputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(6)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }
}

extension View {
    func formInputStyle() -> some View { self.modifier(FormInputStyle()) }
}
