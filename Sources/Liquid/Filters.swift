import Foundation

enum BuiltinFilters {
    private static let arities: [String: ClosedRange<Int>] = [
        "abs": 0...0, "at_least": 1...1, "at_most": 1...1, "ceil": 0...0,
        "divided_by": 1...1, "floor": 0...0, "minus": 1...1, "modulo": 1...1,
        "plus": 1...1, "round": 0...1, "times": 1...1,
        "append": 1...1, "capitalize": 0...0, "downcase": 0...0, "upcase": 0...0,
        "prepend": 1...1, "remove": 1...1, "remove_first": 1...1, "remove_last": 1...1,
        "replace": 1...2, "replace_first": 1...2, "replace_last": 2...2,
        "lstrip": 0...0, "rstrip": 0...0, "strip": 0...0, "strip_newlines": 0...0,
        "newline_to_br": 0...0, "strip_html": 0...0, "escape": 0...0, "escape_once": 0...0,
        "url_encode": 0...0, "url_decode": 0...0,
        "size": 0...0, "slice": 1...2, "split": 1...1, "truncate": 0...2, "truncatewords": 0...2,
        "concat": 1...1, "compact": 0...1, "first": 0...0, "last": 0...0, "join": 0...1,
        "map": 1...1, "reverse": 0...0, "sort": 0...1, "sort_natural": 0...1, "uniq": 0...1,
        "where": 1...2, "reject": 1...2, "has": 1...2, "find": 1...2, "find_index": 1...2,
        "sum": 0...1, "squish": 0...0, "h": 0...0,
        "base64_encode": 0...0, "base64_decode": 0...0, "base64_url_safe_encode": 0...0, "base64_url_safe_decode": 0...0,
        "default": 0...2, "date": 1...1
    ]

    static func apply(_ name: String, to input: Value, arguments args: [Value], currentTime: Date? = nil, strict: Bool = false) throws -> Value {
        guard let arity = arities[name] else {
            if strict { throw TemplateRenderError("Unknown filter: \(name)") }
            return input
        }
        guard arity.contains(args.count) else { throw TemplateRenderError("Wrong number of arguments for filter \(name)") }
        let text = input.filterText
        let number = input.numeric
        let arg = args.first ?? .null
        let array: [Value]
        array = input == .null ? [] : input.flattened

        func integer(_ value: Value) throws -> Int {
            let n = value.numeric
            guard n.isFinite, value != .null, value != .string("") else {
                throw TemplateRenderError("Integer argument out of range for \(name)")
            }
            if n >= Double(Int.max) { return Int.max }
            if n <= Double(Int.min) { return Int.min }
            return Int(n)
        }
        func numeric(_ value: Double, floating: Bool? = nil) throws -> Value {
            guard value.isFinite else { throw TemplateRenderError("Non-finite result in \(name)") }
            return (floating ?? (input.isDecimal || args.contains(where: \.isDecimal))) ? .decimal(value) : .number(value)
        }
        func arithmetic(_ operation: (Decimal, Decimal) -> Decimal, fallback: Double) -> Double {
            guard input.isDecimal || arg.isDecimal,
                  let left = Decimal(string: String(number), locale: Locale(identifier: "en_US_POSIX")),
                  let right = Decimal(string: String(arg.numeric), locale: Locale(identifier: "en_US_POSIX")) else { return fallback }
            let value = operation(left, right)
            return value.isNaN ? fallback : NSDecimalNumber(decimal: value).doubleValue
        }
        func replaceOne(last: Bool, replacement: String) -> Value {
            if arg.text.isEmpty { return .string(last ? text + replacement : replacement + text) }
            guard let range = text.range(of: arg.text, options: last ? .backwards : []) else { return .string(text) }
            var value = text
            value.replaceSubrange(range, with: replacement)
            return .string(value)
        }

        switch name {
        case "squish": return .string(text.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        case "base64_encode", "base64_url_safe_encode":
            let value = Data(text.utf8).base64EncodedString()
            return .string(name == "base64_encode" ? value : value.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_"))
        case "base64_decode", "base64_url_safe_decode":
            var value = text
            if name == "base64_url_safe_decode" {
                value = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                value += String(repeating: "=", count: (4 - value.count % 4) % 4)
            }
            guard let data = Data(base64Encoded: value), let decoded = String(data: data, encoding: .utf8) else {
                throw TemplateRenderError("invalid base64")
            }
            return .string(decoded)
        case "sum":
            let values = array.map { args.isEmpty ? $0 : $0.member(arg.text) }.flatMap(\.flattened)
            var sum = Decimal.zero
            var decimalValid = true
            for value in values {
                guard let number = Decimal(string: String(value.numeric), locale: Locale(identifier: "en_US_POSIX")) else { decimalValid = false; break }
                sum += number
                if sum.isNaN { decimalValid = false; break }
            }
            let total = decimalValid ? NSDecimalNumber(decimal: sum).doubleValue : values.reduce(0) { $0 + $1.numeric }
            return try numeric(total, floating: values.contains(where: \.isDecimal))
        case "abs": return try numeric(abs(number))
        case "at_least": return try numeric(max(number, arg.numeric), floating: number >= arg.numeric ? input.isDecimal : arg.isDecimal)
        case "at_most": return try numeric(min(number, arg.numeric), floating: number <= arg.numeric ? input.isDecimal : arg.isDecimal)
        case "ceil": return try numeric(ceil(number), floating: false)
        case "floor": return try numeric(floor(number), floating: false)
        case "plus": return try numeric(arithmetic(+, fallback: number + arg.numeric))
        case "minus": return try numeric(arithmetic(-, fallback: number - arg.numeric))
        case "times": return try numeric(arithmetic(*, fallback: number * arg.numeric))
        case "divided_by", "modulo":
            guard arg.numeric != 0 else { throw TemplateRenderError("Division by zero in \(name)") }
            if name == "modulo" {
                let remainder = number.truncatingRemainder(dividingBy: arg.numeric)
                return try numeric(remainder != 0 && (remainder < 0) != (arg.numeric < 0) ? remainder + arg.numeric : remainder)
            }
            let quotient = arithmetic(/, fallback: number / arg.numeric)
            // Liquid integer division follows the divisor's type; decimal literals preserve fractions.
            let integerDivisor: Bool
            integerDivisor = !input.isDecimal && !arg.isDecimal
            return try numeric(integerDivisor ? floor(quotient) : quotient, floating: !integerDivisor)
        case "round":
            let places = try args.isEmpty ? 0 : integer(arg)
            guard (-15...15).contains(places) else { throw TemplateRenderError("round precision must be between -15 and 15") }
            let scale = pow(10, Double(places))
            return try numeric((number * scale).rounded() / scale, floating: places > 0 && input.isDecimal)
        case "append": return .string(text + arg.text)
        case "prepend": return .string(arg.text + text)
        case "capitalize": return .string(text.prefix(1).uppercased() + text.dropFirst().lowercased())
        case "downcase": return .string(text.lowercased())
        case "upcase": return .string(text.uppercased())
        case "remove": return .string(text.replacingOccurrences(of: arg.text, with: ""))
        case "replace":
            let replacement = args.count > 1 ? args[1].filterText : ""
            if arg.text.isEmpty { return .string(replacement + text.map(String.init).joined(separator: replacement) + replacement) }
            return .string(text.replacingOccurrences(of: arg.filterText, with: replacement))
        case "remove_first", "remove_last": return replaceOne(last: name == "remove_last", replacement: "")
        case "replace_first", "replace_last": return replaceOne(last: name == "replace_last", replacement: args.count > 1 ? args[1].text : "")
        case "strip": return .string(text.trimmed)
        case "lstrip": return .string(String(text.drop(while: \.isWhitespace)))
        case "rstrip": return .string(String(text.reversed().drop(while: \.isWhitespace).reversed()))
        case "strip_newlines": return .string(text.replacingOccurrences(of: "\r\n", with: "").replacingOccurrences(of: "\n", with: ""))
        case "newline_to_br": return .string(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "<br />\n"))
        case "strip_html":
            let strippedBlocks = text.replacingOccurrences(of: #"(?is)<script.*?</script\s*>|<style.*?</style\s*>|<!--.*?-->"#, with: "", options: .regularExpression)
            return .string(strippedBlocks.replacingOccurrences(of: #"(?s)<.*?>"#, with: "", options: .regularExpression))
        case "escape", "escape_once", "h":
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
            if case .selfDrop = input { return .number(0) }
            if case .object(let values) = input { return .number(Double(values.count)) }
            return input.member("size") == .null ? .number(0) : input.member("size")
        case "split":
            if arg.text.isEmpty { return .array(text.map { .string(String($0)) }) }
            if arg.text == " " { return .array(text.components(separatedBy: CharacterSet(charactersIn: " \t\r\n\u{000B}\u{000C}")).filter { !$0.isEmpty }.map(Value.string)) }
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
            if input == .null { return .string("") }
            let length = try args.isEmpty ? (name == "truncate" ? 50 : 15) : max(0, integer(arg))
            let omission = args.count > 1 ? args[1].text : "..."
            if name == "truncate" {
                return text.count > length ? .string(String(text.prefix(max(0, length - omission.count))) + omission) : .string(text)
            }
            let words = text.components(separatedBy: CharacterSet(charactersIn: " \t\r\n\u{000B}\u{000C}")).filter { !$0.isEmpty }
            return words.count > max(1, length) ? .string(words.prefix(max(1, length)).joined(separator: " ") + omission) : .string(text)
        case "first":
            if case .selfDrop = input { return .null }
            if case .string(let value) = input { return .string(String(value.prefix(1))) }
            return input.member("first")
        case "last":
            if case .selfDrop = input { return .null }
            if case .string(let value) = input { return .string(String(value.suffix(1))) }
            return input.member("last")
        case "join": return .string(array.map(\.filterText).joined(separator: args.isEmpty ? " " : arg.filterText))
        case "concat":
            guard case .array(let other) = arg else { throw TemplateRenderError("concat requires an array") }
            return .array(array + other)
        case "compact": return .array(array.filter { (args.isEmpty ? $0 : $0.member(arg.text)) != .null })
        case "map": return .array(array.map { $0.member(arg.text) })
        case "reverse": return .array(array.reversed())
        case "uniq":
            var values: [Value] = []
            var keys: [Value] = []
            for value in array {
                let key = args.isEmpty ? value : value.member(arg.text)
                if !keys.contains(where: { $0.equals(key) }) { keys.append(key); values.append(value) }
            }
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
        case "where", "reject", "has", "find", "find_index":
            func matches(_ value: Value) -> Bool {
                let property: Value
                if case .string(let text) = value { property = arg.text.isEmpty || text.contains(arg.text) ? .string(arg.text) : .null }
                else { property = value.member(arg.text) }
                return args.count > 1 && args[1] != .null ? property.equals(args[1]) : property.truthy
            }
            if name == "has" { return .bool(array.contains(where: matches)) }
            if name == "find" { return array.first(where: matches) ?? .null }
            if name == "find_index" { return array.firstIndex(where: matches).map { .number(Double($0)) } ?? .null }
            return .array(array.filter { name == "reject" ? !matches($0) : matches($0) })
        case "default":
            let allowFalse = args.count > 1 && args[1].member("allow_false") == .bool(true)
            return input == .null || input.isEmpty || (input == .bool(false) && !allowFalse) ? (args.isEmpty ? .string("") : arg) : input
        case "date": return .string(LiquidDate.format(input, format: arg.text, currentTime: currentTime) ?? text)
        default: throw TemplateRenderError("Unknown filter: \(name)")
        }
    }

}
