import Foundation

enum BuiltinFilters {
    private static let arities: [String: ClosedRange<Int>] = [
        "abs": 0...0, "at_least": 1...1, "at_most": 1...1, "ceil": 0...0,
        "divided_by": 1...1, "floor": 0...0, "minus": 1...1, "modulo": 1...1,
        "plus": 1...1, "round": 0...1, "times": 1...1,
        "append": 1...1, "capitalize": 0...0, "downcase": 0...0, "upcase": 0...0,
        "prepend": 1...1, "remove": 1...1, "remove_first": 1...1, "remove_last": 1...1,
        "replace": 2...2, "replace_first": 2...2, "replace_last": 2...2,
        "lstrip": 0...0, "rstrip": 0...0, "strip": 0...0, "strip_newlines": 0...0,
        "newline_to_br": 0...0, "strip_html": 0...0, "escape": 0...0, "escape_once": 0...0,
        "url_encode": 0...0, "url_decode": 0...0,
        "size": 0...0, "slice": 1...2, "split": 1...1, "truncate": 0...2, "truncatewords": 0...2,
        "concat": 1...1, "compact": 0...1, "first": 0...0, "last": 0...0, "join": 0...1,
        "map": 1...1, "reverse": 0...0, "sort": 0...1, "sort_natural": 0...1, "uniq": 0...0,
        "where": 1...2, "default": 1...2, "date": 1...1
    ]

    static func apply(_ name: String, to input: Value, arguments args: [Value]) throws -> Value {
        guard let arity = arities[name] else { throw TemplateRenderError("Unknown filter: \(name)") }
        guard arity.contains(args.count) else { throw TemplateRenderError("Wrong number of arguments for filter \(name)") }
        let text = input.text
        let number = input.numeric
        let arg = args.first ?? .null
        let array: [Value]
        if case .array(let values) = input { array = values } else { array = [] }

        func integer(_ value: Value) throws -> Int {
            let n = value.numeric
            guard n.isFinite, n >= Double(Int.min), n < Double(Int.max) else {
                throw TemplateRenderError("Integer argument out of range for \(name)")
            }
            return Int(n)
        }
        func numeric(_ value: Double, floating: Bool? = nil) throws -> Value {
            guard value.isFinite else { throw TemplateRenderError("Non-finite result in \(name)") }
            return (floating ?? (input.isDecimal || args.contains(where: \.isDecimal))) ? .decimal(value) : .number(value)
        }
        func replaceOne(last: Bool, replacement: String) -> Value {
            guard !arg.text.isEmpty, let range = text.range(of: arg.text, options: last ? .backwards : []) else { return input }
            var value = text
            value.replaceSubrange(range, with: replacement)
            return .string(value)
        }

        switch name {
        case "abs": return try numeric(abs(number))
        case "at_least": return try numeric(max(number, arg.numeric))
        case "at_most": return try numeric(min(number, arg.numeric))
        case "ceil": return try numeric(ceil(number), floating: false)
        case "floor": return try numeric(floor(number), floating: false)
        case "plus": return try numeric(number + arg.numeric)
        case "minus": return try numeric(number - arg.numeric)
        case "times": return try numeric(number * arg.numeric)
        case "divided_by", "modulo":
            guard arg.numeric != 0 else { throw TemplateRenderError("Division by zero in \(name)") }
            if name == "modulo" {
                let remainder = number.truncatingRemainder(dividingBy: arg.numeric)
                return try numeric(remainder != 0 && (remainder < 0) != (arg.numeric < 0) ? remainder + arg.numeric : remainder)
            }
            let quotient = number / arg.numeric
            // Liquid integer division follows the divisor's type; decimal literals preserve fractions.
            let integerDivisor: Bool
            integerDivisor = !arg.isDecimal && !arg.text.contains(".")
            return try numeric(integerDivisor ? floor(quotient) : quotient, floating: !integerDivisor)
        case "round":
            let places = try args.isEmpty ? 0 : integer(arg)
            guard (-15...15).contains(places) else { throw TemplateRenderError("round precision must be between -15 and 15") }
            let scale = pow(10, Double(places))
            return try numeric((number * scale).rounded() / scale, floating: places > 0)
        case "append": return .string(text + arg.text)
        case "prepend": return .string(arg.text + text)
        case "capitalize": return .string(text.prefix(1).uppercased() + text.dropFirst().lowercased())
        case "downcase": return .string(text.lowercased())
        case "upcase": return .string(text.uppercased())
        case "remove": return .string(text.replacingOccurrences(of: arg.text, with: ""))
        case "replace": return .string(text.replacingOccurrences(of: arg.text, with: args[1].text))
        case "remove_first", "remove_last": return replaceOne(last: name == "remove_last", replacement: "")
        case "replace_first", "replace_last": return replaceOne(last: name == "replace_last", replacement: args[1].text)
        case "strip": return .string(text.trimmed)
        case "lstrip": return .string(String(text.drop(while: \.isWhitespace)))
        case "rstrip": return .string(String(text.reversed().drop(while: \.isWhitespace).reversed()))
        case "strip_newlines": return .string(text.replacingOccurrences(of: "\r\n", with: "").replacingOccurrences(of: "\n", with: ""))
        case "newline_to_br": return .string(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "<br />\n"))
        case "strip_html": return .string(text.replacingOccurrences(of: #"(?s)<!--.*?-->|<[^>]*>"#, with: "", options: .regularExpression))
        case "escape", "escape_once":
            var result = name == "escape_once"
                ? text.replacingOccurrences(of: #"&(?!#\d+;|#x[0-9A-Fa-f]+;|[A-Za-z][A-Za-z0-9]+;)"#, with: "&amp;", options: .regularExpression)
                : text.replacingOccurrences(of: "&", with: "&amp;")
            for (a, b) in [("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;"), ("'", "&#39;")] { result = result.replacingOccurrences(of: a, with: b) }
            return .string(result)
        case "url_encode":
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            return .string((text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text).replacingOccurrences(of: "%20", with: "+"))
        case "url_decode":
            let value = text.replacingOccurrences(of: "+", with: " ")
            return .string(value.removingPercentEncoding ?? value)
        case "size":
            if case .object(let values) = input { return .number(Double(values.count)) }
            return input.member("size") == .null ? .number(0) : input.member("size")
        case "split":
            if arg.text.isEmpty { return .array(text.map { .string(String($0)) }) }
            if arg.text == " " { return .array(text.split(whereSeparator: \.isWhitespace).map { .string(String($0)) }) }
            var parts = text.components(separatedBy: arg.text)
            while parts.last == "" { parts.removeLast() }
            return .array(parts.map(Value.string))
        case "slice":
            let count = { if case .array = input { return array.count }; return text.count }()
            let start = try integer(arg)
            let offset = start < 0 ? max(0, count + max(start, -count - 1)) : min(start, count)
            let length = try args.count > 1 ? max(0, integer(args[1])) : 1
            if start < -count { return .null }
            if case .array = input { return .array(Array(array.dropFirst(offset).prefix(length))) }
            return .string(String(text.dropFirst(offset).prefix(length)))
        case "truncate", "truncatewords":
            let length = try args.isEmpty ? (name == "truncate" ? 50 : 15) : max(0, integer(arg))
            let omission = args.count > 1 ? args[1].text : "..."
            if name == "truncate" {
                return text.count > length ? .string(String(text.prefix(max(0, length - omission.count))) + omission) : input
            }
            let words = text.split(whereSeparator: \.isWhitespace)
            return words.count > length ? .string(words.prefix(length).joined(separator: " ") + omission) : input
        case "first": return array.first ?? .null
        case "last": return array.last ?? .null
        case "join": return .string(array.map(\.text).joined(separator: args.isEmpty ? " " : arg.text))
        case "concat":
            guard case .array(let other) = arg else { throw TemplateRenderError("concat requires an array") }
            return .array(array + other)
        case "compact": return .array(array.filter { (args.isEmpty ? $0 : $0.member(arg.text)) != .null })
        case "map": return .array(array.map { $0.member(arg.text) })
        case "reverse": return .array(array.reversed())
        case "uniq":
            var values: [Value] = []
            for value in array where !values.contains(where: { $0.equals(value) }) { values.append(value) }
            return .array(values)
        case "sort", "sort_natural":
            return .array(array.sorted { a, b in
                let lhs = args.isEmpty ? a : a.member(arg.text)
                let rhs = args.isEmpty ? b : b.member(arg.text)
                if lhs == .null { return false }
                if rhs == .null { return true }
                if lhs.isNumeric && rhs.isNumeric { return lhs.numeric < rhs.numeric }
                return lhs.text.compare(rhs.text, options: name == "sort_natural" ? [.caseInsensitive] : []) == .orderedAscending
            })
        case "where":
            return .array(array.filter { args.count > 1 ? $0.member(arg.text).equals(args[1]) : $0.member(arg.text).truthy })
        case "default":
            let allowFalse = args.count > 1 && args[1].member("allow_false") == .bool(true)
            return input == .null || input.isEmpty || (input == .bool(false) && !allowFalse) ? arg : input
        case "date": return .string(formatDate(input, format: arg.text) ?? text)
        default: throw TemplateRenderError("Unknown filter: \(name)")
        }
    }

    private static func formatDate(_ input: Value, format: String) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        var date: Date?
        if input.text == "now" || input.text == "today" { date = Date() }
        else if input.isNumeric, input.numeric.isFinite { date = Date(timeIntervalSince1970: input.numeric) }
        else {
            let iso = ISO8601DateFormatter()
            date = iso.date(from: input.text)
            if date == nil {
                iso.formatOptions.insert(.withFractionalSeconds)
                date = iso.date(from: input.text)
            }
            if date == nil {
                for pattern in ["yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "MMMM d, yyyy"] {
                    formatter.dateFormat = pattern
                    if let parsed = formatter.date(from: input.text) { date = parsed; break }
                }
            }
        }
        guard let date else { return nil }
        let formats: [Character: String] = [
            "Y": "yyyy", "y": "yy", "m": "MM", "d": "dd", "e": "d", "H": "HH", "I": "hh",
            "M": "mm", "S": "ss", "p": "a", "B": "MMMM", "b": "MMM", "h": "MMM", "A": "EEEE",
            "a": "EEE", "j": "DDD", "z": "xx", "Z": "zzz", "F": "yyyy-MM-dd", "T": "HH:mm:ss",
            "R": "HH:mm", "D": "MM/dd/yy"
        ]
        var output = ""
        var percent = false
        for character in format {
            if percent {
                if character == "%" { output.append("%") }
                else if character == "s" { output += String(format: "%.0f", date.timeIntervalSince1970.rounded(.down)) }
                else if let pattern = formats[character] { formatter.dateFormat = pattern; output += formatter.string(from: date) }
                else { output += "%" + String(character) }
                percent = false
            } else if character == "%" { percent = true }
            else { output.append(character) }
        }
        if percent { output.append("%") }
        return output
    }
}
