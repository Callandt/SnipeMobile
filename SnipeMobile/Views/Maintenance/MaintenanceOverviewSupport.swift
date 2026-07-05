import SwiftUI

// in progress / completed filter for the overview
enum MaintenanceStatusFilter: String, CaseIterable, Identifiable {
    case all
    case inProgress
    case completed

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .all: return L10n.string("filter_all")
        case .inProgress: return L10n.string("in_progress")
        case .completed: return L10n.string("status_completed")
        }
    }

    func matches(_ record: AssetMaintenance) -> Bool {
        switch self {
        case .all: return true
        case .inProgress: return !record.isCompleted
        case .completed: return record.isCompleted
        }
    }

    static func available(in records: [AssetMaintenance]) -> [MaintenanceStatusFilter] {
        var filters: [MaintenanceStatusFilter] = [.all]
        if records.contains(where: { !$0.isCompleted }) { filters.append(.inProgress) }
        if records.contains(where: { $0.isCompleted }) { filters.append(.completed) }
        return filters
    }

    static func hasChoices(in records: [AssetMaintenance]) -> Bool {
        available(in: records).count > 1
    }
}

// overview row, also used in bulk-select mode
struct MaintenanceOverviewRow: View {
    let record: AssetMaintenance
    var linkedAsset: Asset? = nil
    var isSelecting: Bool
    var isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 10) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                MaintenanceCardView(record: record, linkedAsset: linkedAsset, showAssetHeader: true)
            }
        }
        .buttonStyle(.plain)
        .opacity(isSelecting && record.isCompleted ? 0.45 : 1)
        .allowsHitTesting(!isSelecting || !record.isCompleted)
    }
}

// bottom bar shown while bulk-completing
struct MaintenanceBulkSelectionBar: View {
    let selectedCount: Int
    let isBusy: Bool
    let onComplete: () -> Void

    var body: some View {
        Button(action: onComplete) {
            Label(L10n.string("mark_complete_selected", selectedCount), systemImage: "checkmark.seal")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.large)
        .disabled(isBusy || selectedCount == 0)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

enum MaintenanceBulkCompleter {
    static func inProgress(from records: [AssetMaintenance]) -> [AssetMaintenance] {
        records.filter { !$0.isCompleted }
    }

    @MainActor
    static func complete(
        ids: Set<Int>,
        note: String?,
        apiClient: SnipeITAPIClient
    ) async -> (failedCount: Int, lastError: String?) {
        var failed = 0
        var lastError: String? = nil
        for id in ids {
            let ok = await apiClient.completeMaintenance(id: id, note: note)
            if !ok {
                failed += 1
                lastError = apiClient.lastApiMessage ?? apiClient.errorMessage
            }
        }
        return (failed, lastError)
    }
}

// wires up the toolbar, bottom bar and alerts for bulk complete
struct MaintenanceBulkSelectionModifier: ViewModifier {
    let isActive: Bool
    let selectableRecords: [AssetMaintenance]
    @ObservedObject var apiClient: SnipeITAPIClient
    let onRefresh: () async -> Void

    @Binding var isSelecting: Bool
    @Binding var selectedIds: Set<Int>

    @State private var showConfirm = false
    @State private var completeNote = ""
    @State private var isCompleting = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    func body(content: Content) -> some View {
        content
            .toolbar {
                if isActive {
                    if isSelecting {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.string("cancel")) {
                                cancelSelection()
                            }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button(L10n.string("select_all")) {
                                selectedIds = Set(selectableRecords.map(\.id))
                            }
                            .disabled(selectableRecords.isEmpty)
                        }
                    } else if !selectableRecords.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            Button(L10n.string("select")) {
                                isSelecting = true
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isActive, isSelecting, !selectedIds.isEmpty {
                    MaintenanceBulkSelectionBar(
                        selectedCount: selectedIds.count,
                        isBusy: isCompleting,
                        onComplete: { showConfirm = true }
                    )
                }
            }
            .overlay {
                if isCompleting {
                    ProgressView()
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert(L10n.string("mark_complete_confirm_title"), isPresented: $showConfirm) {
                TextField(L10n.string("note_optional"), text: $completeNote)
                Button(L10n.string("cancel"), role: .cancel) {}
                Button(L10n.string("mark_complete")) {
                    Task { await performBulkComplete() }
                }
            } message: {
                Text(L10n.string("bulk_mark_complete_confirm_message", selectedIds.count))
            }
            .alert(L10n.string("error"), isPresented: $showErrorAlert) {
                Button(L10n.string("ok"), role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onChange(of: isActive) { _, active in
                if !active { cancelSelection() }
            }
    }

    private func cancelSelection() {
        isSelecting = false
        selectedIds.removeAll()
        completeNote = ""
    }

    private func performBulkComplete() async {
        guard !isCompleting, !selectedIds.isEmpty else { return }
        isCompleting = true
        defer { isCompleting = false }

        let trimmed = completeNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = trimmed.isEmpty ? nil : trimmed
        let ids = selectedIds
        let (failed, lastError) = await MaintenanceBulkCompleter.complete(
            ids: ids,
            note: note,
            apiClient: apiClient
        )

        await onRefresh()

        if failed == 0 {
            cancelSelection()
        } else {
            let base = L10n.string("bulk_maintenance_complete_failed", failed)
            errorMessage = lastError.map { "\(base)\n\($0)" } ?? base
            showErrorAlert = true
            if failed < ids.count {
                cancelSelection()
            }
        }
    }
}

extension View {
    func maintenanceBulkSelection(
        isActive: Bool,
        selectableRecords: [AssetMaintenance],
        apiClient: SnipeITAPIClient,
        isSelecting: Binding<Bool>,
        selectedIds: Binding<Set<Int>>,
        onRefresh: @escaping () async -> Void
    ) -> some View {
        modifier(
            MaintenanceBulkSelectionModifier(
                isActive: isActive,
                selectableRecords: selectableRecords,
                apiClient: apiClient,
                onRefresh: onRefresh,
                isSelecting: isSelecting,
                selectedIds: selectedIds
            )
        )
    }
}

// Keeps maintenance form Pickers in sync with async-loaded options.
enum MaintenanceFormPickerSupport {
    static let legacyMaintenanceTypes = [
        "Maintenance", "Repair", "PAT Test/Electrical",
        "Upgrade", "Hardware Support", "Software Support"
    ]

    static func legacyTypeOptions(selectedType: String, recordType: String?) -> [String] {
        var options = legacyMaintenanceTypes
        for extra in [selectedType, recordType].compactMap({ $0 }).filter({ !$0.isEmpty }) {
            if !options.contains(extra) {
                options.append(extra)
            }
        }
        return options
    }

    static func normalizeLegacyTypeSelection(selectedType: inout String, options: [String]) {
        if !options.contains(selectedType), let first = options.first {
            selectedType = first
        }
    }

    static func applyTypeIdSelection(
        selectedTypeId: inout Int,
        types: [MaintenanceType],
        record: AssetMaintenance?
    ) {
        guard !types.isEmpty else { return }
        if let record {
            let target = (record.maintenanceType ?? record.assetMaintenanceType)?.lowercased()
            if let target, !target.isEmpty,
               let match = types.first(where: {
                   $0.name.lowercased() == target || $0.decodedName.lowercased() == target
               }) {
                selectedTypeId = match.id
                return
            }
        }
        if !types.contains(where: { $0.id == selectedTypeId }), let first = types.first {
            selectedTypeId = first.id
        }
    }

    static func reconcileResponsibleSelection(
        selectedId: inout Int,
        users: [User],
        preferredId: Int?,
        defaultUser: User?
    ) {
        guard !users.isEmpty else { return }
        if users.contains(where: { $0.id == selectedId }) { return }
        if let preferredId, users.contains(where: { $0.id == preferredId }) {
            selectedId = preferredId
            return
        }
        if let defaultUser, users.contains(where: { $0.id == defaultUser.id }) {
            selectedId = defaultUser.id
            return
        }
        selectedId = users[0].id
    }

    static func hasValidPickerTag(id: Int, in ids: [Int]) -> Bool {
        ids.contains(id)
    }
}
