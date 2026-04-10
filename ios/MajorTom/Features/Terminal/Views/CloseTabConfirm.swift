import SwiftUI

/// View modifier that presents a confirmation dialog when closing a terminal tab.
///
/// Shown when the user taps the close button on a tab that may have an active
/// process. Uses `.alert` for a clean modal experience on iOS.
struct CloseTabConfirmModifier: ViewModifier {
    /// Whether the confirmation dialog is showing.
    @Binding var isPresented: Bool

    /// The title of the tab being closed, for display in the dialog.
    let tabTitle: String

    /// Called when the user confirms the close action.
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Close Tab?", isPresented: $isPresented) {
                Button("Cancel", role: .cancel) { }
                Button("Close", role: .destructive) {
                    onConfirm()
                }
            } message: {
                Text("This tab may have a running process. Close \"\(tabTitle)\" anyway?")
            }
    }
}

extension View {
    /// Attach a close-tab confirmation dialog to this view.
    func closeTabConfirmation(
        isPresented: Binding<Bool>,
        tabTitle: String,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(CloseTabConfirmModifier(
            isPresented: isPresented,
            tabTitle: tabTitle,
            onConfirm: onConfirm
        ))
    }
}
