import SwiftUI

struct CardLayoutSettingsView: View {
    @AppStorage("cardLayoutsJSON") private var cardLayoutsJSON = ""
    @AppStorage("preferAssetNameInLists") private var preferAssetNameInLists = false

    private var store: CardLayoutStore {
        CardLayoutStore.decode(cardLayoutsJSON, preferAssetNameInLists: preferAssetNameInLists)
    }

    var body: some View {
        Form {
            Section {
                ForEach(CardKind.allCases) { kind in
                    NavigationLink(value: SettingsRoute.cardLayoutKind(kind)) {
                        HStack(spacing: 12) {
                            cardKindIcon(kind)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.string(kind.titleKey))
                                Text(summary(for: kind))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.string("card_layout_settings"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summary(for kind: CardKind) -> String {
        let spec = CardKindSpec.spec(for: kind)
        let layout = store.layout(for: kind).resolved(against: spec)
        var parts: [String] = [L10n.string(CardKindSpec.labelKey(for: layout.title))]
        for id in layout.details ?? [] {
            parts.append(L10n.string(CardKindSpec.labelKey(for: id)))
        }
        for id in layout.meta ?? [] {
            parts.append(L10n.string(CardKindSpec.labelKey(for: id)))
        }
        return parts.joined(separator: " · ")
    }

    private func cardKindIcon(_ kind: CardKind) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(kind.settingsIconColor.gradient)
            .frame(width: 29, height: 29)
            .overlay(
                Image(systemName: kind.settingsIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

private struct RemovedCardField: Equatable {
    var id: String
    var asMeta: Bool
    var icon: String?
}

struct CardLayoutKindEditor: View {
    let kind: CardKind
    @AppStorage("cardLayoutsJSON") private var cardLayoutsJSON = ""
    @AppStorage("preferAssetNameInLists") private var preferAssetNameInLists = false
    @State private var iconPickerFieldID: String?
    @State private var removedFields: [RemovedCardField] = []

    private var spec: CardKindSpec { CardKindSpec.spec(for: kind) }

    private var store: CardLayoutStore {
        CardLayoutStore.decode(cardLayoutsJSON, preferAssetNameInLists: preferAssetNameInLists)
    }

    private var layout: CardSlotLayout {
        store.layout(for: kind).resolved(against: spec)
    }

    var body: some View {
        Form {
            Section {
                CardLayoutPreviewCard(kind: kind, layout: layout)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
            } header: {
                Text(L10n.string("card_layout_preview"))
            }

            Section {
                Picker(L10n.string("card_layout_title_slot"), selection: titleBinding) {
                    ForEach(spec.fields, id: \.self) { fieldID in
                        Text(L10n.string(CardKindSpec.labelKey(for: fieldID))).tag(fieldID)
                    }
                }
            } header: {
                Text(L10n.string("card_layout_title_slot"))
            }

            Section {
                ForEach(Array((layout.details ?? []).enumerated()), id: \.element) { index, fieldID in
                    Picker(
                        L10n.string(CardKindSpec.labelKey(for: fieldID)),
                        selection: detailBinding(at: index, current: fieldID)
                    ) {
                        ForEach(spec.fields, id: \.self) { option in
                            Text(L10n.string(CardKindSpec.labelKey(for: option))).tag(option)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            rememberRemoved(fieldID, asMeta: false)
                            save(layout.removingDetail(at: index))
                        } label: {
                            Label(L10n.string("card_layout_remove_field"), systemImage: "trash")
                        }
                    }
                }
                if (layout.details ?? []).count < CardKindSpec.maxDetailLines,
                   !layout.unusedFields(in: spec).isEmpty {
                    Menu {
                        ForEach(layout.unusedFields(in: spec), id: \.self) { fieldID in
                            Button(L10n.string(CardKindSpec.labelKey(for: fieldID))) {
                                forgetRemoved(fieldID)
                                save(layout.appendingDetail(fieldID))
                            }
                        }
                    } label: {
                        Label(L10n.string("card_layout_add_field"), systemImage: "plus")
                    }
                }
            } header: {
                Text(L10n.string("card_layout_detail_slot"))
            } footer: {
                Text(L10n.string("card_layout_swipe_remove_footer"))
            }

            Section {
                ForEach(Array((layout.meta ?? []).enumerated()), id: \.element) { index, fieldID in
                    HStack(spacing: 10) {
                        Picker(
                            L10n.string(CardKindSpec.labelKey(for: fieldID)),
                            selection: metaBinding(at: index, current: fieldID)
                        ) {
                            ForEach(spec.fields, id: \.self) { option in
                                Text(L10n.string(CardKindSpec.labelKey(for: option))).tag(option)
                            }
                        }
                        .layoutPriority(1)
                        metaIconPicker(for: fieldID)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            rememberRemoved(fieldID, asMeta: true)
                            save(layout.removingMeta(at: index))
                        } label: {
                            Label(L10n.string("card_layout_remove_field"), systemImage: "trash")
                        }
                    }
                }
                if !layout.unusedFields(in: spec).isEmpty {
                    Menu {
                        ForEach(layout.unusedFields(in: spec), id: \.self) { fieldID in
                            Button(L10n.string(CardKindSpec.labelKey(for: fieldID))) {
                                forgetRemoved(fieldID)
                                save(layout.appendingMeta(fieldID))
                            }
                        }
                    } label: {
                        Label(L10n.string("card_layout_add_field"), systemImage: "plus")
                    }
                }
            } header: {
                Text(L10n.string("card_layout_meta_slot"))
            } footer: {
                Text(L10n.string("card_layout_swipe_remove_footer"))
            }

            Section {
                Button(L10n.string("card_layout_reset")) {
                    save(layoutByResetting())
                    removedFields = []
                }
                .disabled(layout.matchesDefault(of: spec) && removedFields.isEmpty)
            }
        }
        .navigationTitle(L10n.string(kind.titleKey))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metaIconPicker(for fieldID: String) -> some View {
        let selected = layout.icon(for: fieldID)
        return Button {
            iconPickerFieldID = fieldID
        } label: {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: CardIcon.systemName(selected))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .accessibilityLabel(L10n.string("card_layout_icon"))
        .popover(isPresented: Binding(
            get: { iconPickerFieldID == fieldID },
            set: { if !$0 { iconPickerFieldID = nil } }
        )) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
                spacing: 8
            ) {
                ForEach(CardIcon.all, id: \.self) { icon in
                    Button {
                        save(layout.settingIcon(icon, for: fieldID))
                        iconPickerFieldID = nil
                    } label: {
                        Image(systemName: CardIcon.systemName(icon))
                            .font(.body)
                            .foregroundStyle(icon == selected ? Color.accentColor : Color.secondary)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(icon == selected ? Color.accentColor.opacity(0.15) : Color(.tertiarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.string(CardIcon.labelKey(icon)))
                }
            }
            .padding(12)
            .frame(width: 220)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { layout.title },
            set: { save(layout.placingTitle($0)) }
        )
    }

    private func detailBinding(at index: Int, current: String) -> Binding<String> {
        Binding(
            get: { current },
            set: { save(layout.replacingDetail(at: index, with: $0)) }
        )
    }

    private func metaBinding(at index: Int, current: String) -> Binding<String> {
        Binding(
            get: { current },
            set: { save(layout.replacingMeta(at: index, with: $0)) }
        )
    }

    private func rememberRemoved(_ id: String, asMeta: Bool) {
        forgetRemoved(id)
        removedFields.append(
            RemovedCardField(id: id, asMeta: asMeta, icon: asMeta ? layout.icons?[id] : nil)
        )
    }

    private func forgetRemoved(_ id: String) {
        removedFields.removeAll { $0.id == id }
    }

    private func layoutByResetting() -> CardSlotLayout {
        var next = spec.defaultLayout
        var used = next.usedIDs()
        for item in removedFields where !used.contains(item.id) {
            if item.asMeta || (next.details ?? []).count >= CardKindSpec.maxDetailLines {
                next = next.appendingMeta(item.id)
            } else {
                next = next.appendingDetail(item.id)
            }
            if let icon = item.icon {
                next = next.settingIcon(icon, for: item.id)
            }
            used.insert(item.id)
        }
        return next
    }

    private func save(_ layout: CardSlotLayout) {
        let next = store.replacing(kind, with: layout.resolved(against: spec))
        cardLayoutsJSON = next.encodeJSON()
        CloudSettingsStore.shared.setCardLayoutsJSON(cardLayoutsJSON)
        if kind == .asset {
            preferAssetNameInLists = next.layout(for: .asset).title == CardFieldID.name
        }
    }
}
