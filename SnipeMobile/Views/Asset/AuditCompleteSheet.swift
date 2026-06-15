import SwiftUI

// Shared audit/maintenance completion sheet.
struct CompletionActionSheet: View {
    let title: String
    let message: String
    var dateLabel: String? = nil
    var date: Binding<Date>? = nil
    // When set, adds a toggle to opt out of sending the date.
    var includeDate: Binding<Bool>? = nil
    var includeDateLabel: String? = nil
    @Binding var note: String
    let confirmTitle: String
    var isSaving: Bool
    var onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var showsDateSection: Bool { date != nil && dateLabel != nil }
    private var isDateExpanded: Bool {
        guard showsDateSection else { return false }
        guard let includeDate else { return true }
        return includeDate.wrappedValue
    }
    private var sheetHeight: CGFloat {
        if !showsDateSection { return 316 }
        return isDateExpanded ? 396 : 336
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 28)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    if let date, let dateLabel {
                        if let includeDate {
                            Toggle(includeDateLabel ?? dateLabel, isOn: includeDate)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                            Divider()
                                .padding(.leading, 16)
                        }

                        if isDateExpanded {
                            HStack {
                                Text(dateLabel)
                                    .fontWeight(.semibold)
                                Spacer(minLength: 12)
                                DatePicker("", selection: date, displayedComponents: .date)
                                    .labelsHidden()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            Divider()
                                .padding(.leading, 16)
                        }
                    }

                    TextField(L10n.string("note_optional"), text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Spacer(minLength: 0)

                Button(action: onSave) {
                    Label(confirmTitle, systemImage: "checkmark.seal")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .disabled(isSaving)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("cancel")) { dismiss() }
                        .disabled(isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView()
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
    }
}
