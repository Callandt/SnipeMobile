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

enum CustomFieldDateKind: Equatable {
    case date
    case dateTime
}

enum CustomFieldDate {
    static func kind(element: String?, format: String?) -> CustomFieldDateKind? {
        let element = element?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let format = format?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if element == "datetime_picker" || format == "DATETIME" { return .dateTime }
        if element == "date_picker" || format == "DATE" { return .date }
        return nil
    }

    /// Value to send to Snipe-IT. Display strings such as "01 January, 1990" become `yyyy-MM-dd`.
    /// Ambiguous numeric dates (05/06/1990) stay unchanged.
    static func valueForAPI(_ raw: String, element: String?, format: String?) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let kind = kind(element: element, format: format),
              let date = parse(trimmed, kind: kind) else { return trimmed }
        return apiString(from: date, kind: kind)
    }

    static func parse(_ raw: String, kind: CustomFieldDateKind) -> Date? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00a0}", with: " ")
        guard !trimmed.isEmpty else { return nil }
        let formats = kind == .date ? dateFormats : dateTimeFormats
        formatterLock.lock()
        defer { formatterLock.unlock() }
        formatter.timeZone = TimeZone.current
        let calendar = Calendar.current
        var agreed: (date: Date, stamp: Stamp)?
        for format in formats {
            formatter.dateFormat = format
            guard let date = formatter.date(from: trimmed),
                  formatter.string(from: date) == trimmed else { continue }
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            guard let year = parts.year, let month = parts.month, let day = parts.day else { continue }
            let stamp = Stamp(
                year: year,
                month: month,
                day: day,
                hour: kind == .dateTime ? (parts.hour ?? 0) : 0,
                minute: kind == .dateTime ? (parts.minute ?? 0) : 0
            )
            if let agreed, agreed.stamp != stamp { return nil }
            if agreed == nil { agreed = (date, stamp) }
        }
        return agreed?.date
    }

    static func apiString(from date: Date, kind: CustomFieldDateKind) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = parts.year ?? 1
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        switch kind {
        case .date:
            return String(format: "%04d-%02d-%02d", year, month, day)
        case .dateTime:
            return String(format: "%04d-%02d-%02d %02d:%02d:%02d", year, month, day, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        }
    }

    private struct Stamp: Equatable {
        let year: Int
        let month: Int
        let day: Int
        let hour: Int
        let minute: Int
    }

    // PHP date formats from Snipe-IT's date display setting, plus the full-month form from the field itself.
    private static let dateFormats: [String] = [
        "yyyy-MM-dd",
        "EEE MMM dd, yyyy",
        "MMM d, yyyy",
        "MMM dd, yyyy",
        "dd MMM, yyyy",
        "d MMM, yyyy",
        "dd MMMM, yyyy",
        "d MMMM, yyyy",
        "MMMM d, yyyy",
        "MMMM dd, yyyy",
        "MM/dd/yyyy",
        "M/dd/yy",
        "M/d/yy",
        "dd/MM/yyyy",
        "d/M/yyyy",
        "dd.MM.yyyy",
        "d.M.yyyy",
        "yyyy.MM.dd.",
        "yyyy.MM.dd"
    ]

    private static let timeFormats = ["h:mma", "hh:mma", "h:mm a", "hh:mm a", "HH:mm", "HH:mm:ss"]

    private static let dateTimeFormats: [String] = {
        var formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"]
        for dateFormat in dateFormats {
            for timeFormat in timeFormats {
                formats.append("\(dateFormat) \(timeFormat)")
            }
        }
        return formats
    }()

    private static let formatterLock = NSLock()
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = false
        return formatter
    }()
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
    var format: String?
    var fieldValues: [String]?
    var rawFieldValues: String?
    @Binding var value: String

    var body: some View {
        let parsedOptions = CustomFieldOptions.parse(values: fieldValues, raw: rawFieldValues)
        if let kind = CustomFieldDate.kind(element: type, format: format),
           value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || CustomFieldDate.parse(value, kind: kind) != nil {
            CustomDateField(title: name, kind: kind, value: $value)
        } else if CustomCheckboxValue.isCheckbox(type), !parsedOptions.isEmpty {
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
                stackValue: true
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

private struct CustomDateField: View {
    let title: String
    let kind: CustomFieldDateKind
    @Binding var value: String

    private var isSet: Binding<Bool> {
        Binding(
            get: { CustomFieldDate.parse(value, kind: kind) != nil },
            set: { isOn in
                if isOn {
                    let date = CustomFieldDate.parse(value, kind: kind) ?? Date()
                    value = CustomFieldDate.apiString(from: date, kind: kind)
                } else {
                    value = ""
                }
            }
        )
    }

    private var selection: Binding<Date> {
        Binding(
            get: { CustomFieldDate.parse(value, kind: kind) ?? Date() },
            set: { value = CustomFieldDate.apiString(from: $0, kind: kind) }
        )
    }

    var body: some View {
        HStack {
            Toggle(title, isOn: isSet)
                .font(.caption)
            if isSet.wrappedValue {
                DatePicker(
                    "",
                    selection: selection,
                    displayedComponents: kind == .date ? [.date] : [.date, .hourAndMinute]
                )
                .labelsHidden()
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
