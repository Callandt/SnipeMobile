import SwiftUI

struct EphemeralNotice: Equatable {
    let message: String
    let isError: Bool

    init(_ message: String, isError: Bool = false) {
        self.message = message
        self.isError = isError
    }
}

private struct EphemeralNoticeBanner: View {
    let notice: EphemeralNotice

    var body: some View {
        Text(notice.message)
            .font(.caption)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                (notice.isError ? Color.red : Color.green).opacity(0.88),
                in: Capsule()
            )
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

private struct EphemeralNoticeModifier: ViewModifier {
    @Binding var notice: EphemeralNotice?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if let notice {
                    EphemeralNoticeBanner(notice: notice)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: notice)
    }
}

extension View {
    func ephemeralNotice(_ notice: Binding<EphemeralNotice?>) -> some View {
        modifier(EphemeralNoticeModifier(notice: notice))
    }
}

@MainActor
func presentEphemeralNotice(_ notice: Binding<EphemeralNotice?>, _ message: String, isError: Bool = false) {
    let item = EphemeralNotice(message, isError: isError)
    withAnimation(.easeInOut(duration: 0.2)) {
        notice.wrappedValue = item
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if notice.wrappedValue == item {
                notice.wrappedValue = nil
            }
        }
    }
}
