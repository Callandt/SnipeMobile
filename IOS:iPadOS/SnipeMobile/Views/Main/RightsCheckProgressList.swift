import SwiftUI

/// Rights checklist (onboarding + API settings).
struct RightsCheckProgressList: View {
    let progress: AppModeCheckProgress

    var body: some View {
        VStack(spacing: 0) {
            row(
                title: L10n.string("rights_check_connection"),
                state: progress.connection
            )
            Divider().padding(.leading, 40)
            row(
                title: L10n.string("rights_check_rights"),
                state: progress.rights,
                detail: rightsDetail
            )
        }
    }

    private var rightsDetail: String? {
        guard case .success = progress.rights, let mode = progress.detectedMode else { return nil }
        return mode.localizedTitle
    }

    @ViewBuilder
    private func row(
        title: String,
        state: AppModeCheckProgress.StepState,
        detail: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            statusIcon(state)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func statusIcon(_ state: AppModeCheckProgress.StepState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .running:
            ProgressView()
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
