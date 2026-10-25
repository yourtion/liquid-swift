import Foundation

/// Portable strftime formatting without process-global locale or timezone changes.
enum LiquidDate {
    static func format(_ input: Value, format: String, currentTime: Date?) -> String? {
        guard !format.isEmpty else { return input.filterText }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        var date: Date?
        let text = input.text
        if ["now", "today"].contains(text.lowercased()) { date = currentTime ?? Date() }
        else if let timestamp = Double(text), timestamp.isFinite { date = Date(timeIntervalSince1970: timestamp) }
        else {
            let iso = ISO8601DateFormatter()
            date = iso.date(from: text)
            if date == nil { iso.formatOptions.insert(.withFractionalSeconds); date = iso.date(from: text) }
            if date == nil {
                for pattern in ["yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss XXX", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "MMMM d, yyyy", "EEE MMM d HH:mm:ss yyyy", "EEE, dd MMM yyyy HH:mm:ss Z"] {
                    formatter.dateFormat = pattern
                    if let parsed = formatter.date(from: text) { date = parsed; break }
                }
            }
        }
        guard let date else { return nil }
        if Double(text) == nil, let zoneRange = text.range(of: #"[+-][0-9]{2}:?[0-9]{2}$"#, options: .regularExpression) {
            let zone = String(text[zoneRange]).replacingOccurrences(of: ":", with: "")
            let digits = Array(zone)
            let hours = Int(String(digits[1...2])) ?? 0, minutes = Int(String(digits[3...4])) ?? 0
            formatter.timeZone = TimeZone(secondsFromGMT: (hours * 3600 + minutes * 60) * (zone.first == "-" ? -1 : 1))
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = formatter.timeZone
        let day = calendar.component(.day, from: date), year = calendar.component(.year, from: date)
        let weekday = calendar.component(.weekday, from: date) - 1
        let yearday = (calendar.ordinality(of: .day, in: .year, for: date) ?? 1) - 1
        let offset = formatter.timeZone.secondsFromGMT(for: date)
        let zone = String(format: "%@%02d%02d", offset < 0 ? "-" : "+", abs(offset) / 3600, abs(offset) / 60 % 60)
        let patterns: [Character: String] = [
            "Y": "yyyy", "y": "yy", "m": "MM", "d": "dd", "e": "d", "H": "HH", "I": "hh",
            "k": "H", "l": "h", "M": "mm", "S": "ss", "p": "a", "P": "a",
            "B": "MMMM", "b": "MMM", "h": "MMM", "A": "EEEE", "a": "EEE",
            "F": "yyyy-MM-dd", "T": "HH:mm:ss", "R": "HH:mm", "D": "MM/dd/yy",
            "x": "MM/dd/yy", "X": "HH:mm:ss", "r": "hh:mm:ss a"
        ]
        let widths: [Character: Int] = ["Y": 4, "y": 2, "C": 2, "m": 2, "d": 2, "e": 2, "H": 2, "I": 2,
                                        "k": 2, "l": 2, "M": 2, "S": 2, "j": 3, "U": 2, "W": 2, "V": 2, "G": 4, "g": 2]
        var output = ""
        var cursor = format.startIndex
        while cursor < format.endIndex {
            guard format[cursor] == "%" else { output.append(format[cursor]); cursor = format.index(after: cursor); continue }
            let start = cursor
            cursor = format.index(after: cursor)
            var flags = "", widthText = ""
            while cursor < format.endIndex && "-_0^#".contains(format[cursor]) { flags.append(format[cursor]); cursor = format.index(after: cursor) }
            while cursor < format.endIndex && format[cursor].isNumber { widthText.append(format[cursor]); cursor = format.index(after: cursor) }
            var colon = false
            if cursor < format.endIndex && format[cursor] == ":" { colon = true; cursor = format.index(after: cursor) }
            guard cursor < format.endIndex else { output += String(format[start...]); break }
            let directive = format[cursor]
            cursor = format.index(after: cursor)
            var value: String
            switch directive {
            case "%": value = "%"
            case "n": value = "\n"
            case "t": value = "\t"
            case "C": value = String(year / 100)
            case "j": value = String(yearday + 1)
            case "w": value = String(weekday)
            case "u": value = String((weekday + 6) % 7 + 1)
            case "U": value = String((yearday + 7 - weekday) / 7)
            case "W": value = String((yearday + 7 - (weekday + 6) % 7) / 7)
            case "V": value = String(isoCalendar.component(.weekOfYear, from: date))
            case "G": value = String(isoCalendar.component(.yearForWeekOfYear, from: date))
            case "g": value = String(isoCalendar.component(.yearForWeekOfYear, from: date) % 100)
            case "s": value = String(format: "%.0f", date.timeIntervalSince1970.rounded(.down))
            case "z": value = colon ? String(zone.prefix(3)) + ":" + zone.suffix(2) : zone
            case "Z": value = offset == 0 ? "UTC" : formatter.timeZone.abbreviation(for: date) ?? zone
            case "c":
                formatter.dateFormat = "EEE MMM"
                value = formatter.string(from: date) + String(format: " %2d ", day)
                formatter.dateFormat = "HH:mm:ss yyyy"
                value += formatter.string(from: date)
            default:
                guard let pattern = patterns[directive] else { output += String(format[start..<cursor]); continue }
                formatter.dateFormat = pattern
                value = formatter.string(from: date)
                if directive == "P" { value = value.lowercased() }
            }
            if let defaultWidth = widths[directive] {
                let raw = String(value.drop(while: { $0 == "0" || $0 == " " }))
                value = raw.isEmpty ? "0" : raw
                let width = min(1000, Int(widthText) ?? defaultWidth)
                let padding = flags.contains("_") || (!flags.contains("0") && "ekl".contains(directive)) ? " " : "0"
                if !flags.contains("-") { value = String(repeating: padding, count: max(0, width - value.count)) + value }
            }
            if flags.contains("^") { value = value.uppercased() }
            if flags.contains("#") { value = value == value.uppercased() ? value.lowercased() : value.uppercased() }
            output += value
        }
        return output
    }
}
