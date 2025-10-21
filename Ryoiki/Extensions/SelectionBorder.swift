import SwiftUI

struct SelectionBorder: ViewModifier {
    let isSelected: Bool
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.tint, lineWidth: isSelected ? 2 : 0)
            )
    }
}

extension View {
    func selectionBorder(_ isSelected: Bool) -> some View {
        modifier(SelectionBorder(isSelected: isSelected))
    }
}
