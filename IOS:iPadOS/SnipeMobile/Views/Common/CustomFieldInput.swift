import SwiftUI

enum CustomCheckboxValue {
    /// Snipe-IT joins checked options with a comma and a space.
    static let separator = ", "

    static func isCheckbox(_ type: String?) -> Bool {
        type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "checkbox"
    }

    static func options(from values: [String]?, rawFieldValues: String?) -> [String] {
        let fromArray = uniqueOptions(values ?? [])
        if !fromArray.isEmpty { return fromArray }
        guard let rawFieldValues else { return [] }
        return uniqueOptions(rawFieldValues.components(separatedBy: .newlines))
    }

    static func selected(in stored: String, options: [String]) -> Set<String> {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let known = Set(options)
        if known.contains(trimmed) { return [trimmed] }

        let spaced = tokens(in: trimmed, separatedBy: separator)
        let spacedMatch = Set(spaced.filter { known.contains($0) })
        if spacedMatch.count == spaced.count, !spacedMatch.isEmpty {
            return spacedMatch
        }

        let commas = tokens(in: trimmed, separatedBy: ",")
        return Set(commas.filter { known.contains($0) })
    }

    static func storedValue(selected: Set<String>, options: [String]) -> String {
        options.filter { selected.contains($0) }.joined(separator: separator)
    }

    private static func uniqueOptions(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in values {
            let option = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !option.isEmpty, seen.insert(option).inserted else { continue }
            result.append(option)
        }
        return result
    }

    private static func tokens(in stored: String, separatedBy separator: String) -> [String] {
        stored
            .components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct CustomFieldInput: View {
    let name: String
    var type: String?
    var fieldValues: [String]?
    var rawFieldValues: String?
    @Binding var value: String

    var body: some View {
        let checkboxOptions = CustomCheckboxValue.options(from: fieldValues, rawFieldValues: rawFieldValues)
        if CustomCheckboxValue.isCheckbox(type), !checkboxOptions.isEmpty {
            CustomCheckboxField(title: name, options: checkboxOptions, value: $value)
        } else if type == "listbox", let options = fieldValues, !options.isEmpty {
            let sortedOptions = options.sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            AdaptivePickerRow(
                title: name,
                items: sortedOptions.map { (value: $0, label: $0) },
                selection: $value,
                emptyOption: ("", "—")
            )
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(name, text: $value)
            }
        }
    }
}

private struct CustomCheckboxField: View {
    let title: String
    let options: [String]
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(options, id: \.self) { option in
                Toggle(option, isOn: binding(for: option))
                    .toggleStyle(CheckboxToggleStyle())
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func binding(for option: String) -> Binding<Bool> {
        Binding(
            get: {
                CustomCheckboxValue.selected(in: value, options: options).contains(option)
            },
            set: { isOn in
                var next = CustomCheckboxValue.selected(in: value, options: options)
                if isOn {
                    next.insert(option)
                } else {
                    next.remove(option)
                }
                value = CustomCheckboxValue.storedValue(selected: next, options: options)
            }
        )
    }
}

private struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(configuration.isOn ? Color.accentColor : Color.secondary)
                configuration.label
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
