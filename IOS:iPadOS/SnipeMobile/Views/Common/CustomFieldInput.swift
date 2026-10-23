import SwiftUI

struct CustomFieldOption: Hashable {
    let value: String
    let label: String
}

enum CustomFieldOptions {
    // API array only splits on CRLF. Web splits every newline and `value|label`.
    static func parse(values: [String]?, raw: String?) -> [CustomFieldOption] {
        let fromRaw = splitLines(raw ?? "")
        let fromArray = (values ?? []).flatMap(splitLines)
        // Use whichever side actually split the options.
        let lines: [String]
        if fromRaw.count > fromArray.count {
            lines = fromRaw
        } else if !fromArray.isEmpty {
            lines = fromArray
        } else {
            lines = fromRaw
        }
        var result: [CustomFieldOption] = []
        var indexByValue: [String: Int] = [:]
        for line in lines {
            let decoded = HTMLDecoder.decode(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !decoded.isEmpty else { continue }
            let pieces = decoded.split(separator: "|", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let value = pieces.first ?? ""
            guard !value.isEmpty else { continue }
            let label = pieces.count > 1 && !pieces[1].isEmpty ? pieces[1] : value
            let option = CustomFieldOption(value: value, label: label)
            if let index = indexByValue[value] {
                result[index] = option
            } else {
                indexByValue[value] = result.count
                result.append(option)
            }
        }
        return result
    }

    private static func splitLines(_ text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum CustomCheckboxValue {
    // Checked options are joined with ", ".
    static let separator = ", "

    static func isCheckbox(_ type: String?) -> Bool {
        type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "checkbox"
    }

    static func options(from values: [String]?, rawFieldValues: String?) -> [CustomFieldOption] {
        CustomFieldOptions.parse(values: values, raw: rawFieldValues)
    }

    static func selected(in stored: String, options: [CustomFieldOption]) -> Set<String> {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let known = Set(options.map(\.value))
        if known.contains(trimmed) { return [trimmed] }

        let spaced = tokens(in: trimmed, separatedBy: separator)
        let spacedMatch = Set(spaced.filter { known.contains($0) })
        if spacedMatch.count == spaced.count, !spacedMatch.isEmpty {
            return spacedMatch
        }

        let commas = tokens(in: trimmed, separatedBy: ",")
        return Set(commas.filter { known.contains($0) })
    }

    static func storedValue(selected: Set<String>, options: [CustomFieldOption]) -> String {
        options.map(\.value).filter { selected.contains($0) }.joined(separator: separator)
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
        let parsedOptions = CustomFieldOptions.parse(values: fieldValues, raw: rawFieldValues)
        if CustomCheckboxValue.isCheckbox(type), !parsedOptions.isEmpty {
            CustomCheckboxField(title: name, options: parsedOptions, value: $value)
        } else if type == "listbox", !parsedOptions.isEmpty {
            let sortedOptions = parsedOptions.sorted {
                $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
            }
            AdaptivePickerRow(
                title: name,
                items: sortedOptions.map { (value: $0.value, label: $0.label) },
                selection: $value,
                emptyOption: ("", "—"),
                forceSearchable: true
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
    let options: [CustomFieldOption]
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(options, id: \.value) { option in
                Toggle(option.label, isOn: binding(for: option.value))
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
