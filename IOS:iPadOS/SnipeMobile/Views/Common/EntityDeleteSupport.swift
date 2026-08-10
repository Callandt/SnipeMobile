import SwiftUI

/// Confirm dialog + spinner for entity deletes.
struct EntityDeleteSupport: ViewModifier {
    @Binding var showConfirm: Bool
    @Binding var isDeleting: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String
    let confirmTitle: String
    let confirmMessage: String
    let onDelete: () async -> Void

    func body(content: Content) -> some View {
        content
            .alert(confirmTitle, isPresented: $showConfirm) {
                Button(L10n.string("cancel"), role: .cancel) {}
                Button(L10n.string("delete"), role: .destructive) {
                    Task { await onDelete() }
                }
            } message: {
                Text(confirmMessage)
            }
            .alert(L10n.string("delete_failed"), isPresented: $showError) {
                Button(L10n.string("ok"), role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .overlay {
                if isDeleting {
                    ZStack {
                        Color.black.opacity(0.15).ignoresSafeArea()
                        ProgressView(L10n.string("deleting"))
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
    }
}

extension View {
    func entityDeleteSupport(
        showConfirm: Binding<Bool>,
        isDeleting: Binding<Bool>,
        showError: Binding<Bool>,
        errorMessage: Binding<String>,
        confirmTitle: String,
        confirmMessage: String,
        onDelete: @escaping () async -> Void
    ) -> some View {
        modifier(
            EntityDeleteSupport(
                showConfirm: showConfirm,
                isDeleting: isDeleting,
                showError: showError,
                errorMessage: errorMessage,
                confirmTitle: confirmTitle,
                confirmMessage: confirmMessage,
                onDelete: onDelete
            )
        )
    }
}
