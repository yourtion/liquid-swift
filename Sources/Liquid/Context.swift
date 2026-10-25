import Foundation
import CoreFoundation

/// Variables shared by a render. Use a separate mutable context per task.
public final class Context {
    var dictionaries: [String: Any?]
    private var scopes: [[String: Any?]] = []
    private(set) var assignedNames: Set<String> = []

    public init(dictionary: [String: Any]? = nil) {
        dictionaries = (dictionary ?? [:]).mapValues { $0 }
    }

    public subscript(key: String) -> Any? {
        get {
            for scope in scopes.reversed() where scope.keys.contains(key) { return scope[key] ?? nil }
            return dictionaries[key] ?? nil
        }
        set { dictionaries[key] = newValue }
    }

    func value(for name: String) -> Value { Value(self[name]) }
    func set(_ value: Value, for name: String) { self[name] = value.any; assignedNames.insert(name) }
    func pushScope(_ values: [String: Any?] = [:]) { scopes.append(values) }
    func popScope() { scopes.removeLast() }
    func setLocal(_ value: Any?, for name: String) {
        scopes[scopes.count - 1].updateValue(value, forKey: name)
    }
    func hasLocal(_ name: String) -> Bool { scopes.contains { $0.keys.contains(name) } }
    func hasVariable(_ name: String) -> Bool { hasLocal(name) || dictionaries.keys.contains(name) || assignedNames.contains(name) }
}

private struct LiquidRange { let first: Int; let last: Int }

final class SelfLookup: Equatable {
    weak var state: RenderState?
    weak var context: Context?
    init(_ state: RenderState) { self.state = state; context = state.context }
    static func == (lhs: SelfLookup, rhs: SelfLookup) -> Bool {
        guard let context = lhs.context else { return lhs === rhs }
        return context === rhs.context
    }
    func lookup(_ key: String) -> Value {
        if key == "self", context?.hasVariable(key) == false { return .selfDrop(self) }
        return state?.resolve(key) ?? context?.value(for: key) ?? .null
    }
}

indirect enum Value: Equatable {
    case null, bool(Bool), number(Double), decimal(Double), string(String), array([Value]), object([String: Value])
    case empty, blank
    case range(Int, Int)
    case selfDrop(SelfLookup)

    init(_ value: Any?) {
        guard let value, !(value is NSNull) else { self = .null; return }
        switch value {
        case let value as SelfLookup: self = .selfDrop(value)
        case let value as LiquidRange: self = .range(value.first, value.last)
        case let value as String: self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() { self = .bool(value.boolValue) }
            else if ["f", "d"].contains(String(cString: value.objCType)) { self = .decimal(value.doubleValue) }
            else { self = .number(value.doubleValue) }
        case let value as [Any?]: self = .array(value.map(Value.init))
        case let value as [String: Any?]: self = .object(value.mapValues(Value.init))
        default: self = .string(String(describing: value))
        }
    }

    var any: Any? {
        switch self {
        case .selfDrop(let value): return value
        case .range(let first, let last): return LiquidRange(first: first, last: last)
        case .null: return nil
        case .bool(let value): return value
        case .number(let value):
            return value.isFinite && value.rounded() == value && value >= Double(Int.min) && value < Double(Int.max) ? Int(value) as Any : value as Any
        case .decimal(let value): return value
        case .string(let value): return value
        case .array(let value): return value.map { $0.any ?? NSNull() }
        case .object(let value): return value.mapValues { $0.any ?? NSNull() }
        case .empty, .blank: return nil
        }
    }

    var text: String {
        switch self {
        case .selfDrop: return "Liquid::SelfDrop"
        case .range(let first, let last): return "\(first)..\(last)"
        case .null, .empty, .blank: return ""
        case .object: return inspected
        case .bool(let value): return value ? "true" : "false"
        case .number(let value):
            guard value.isFinite else { return "" }
            return value.rounded() == value ? String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), value) : String(value)
        case .decimal(let value):
            guard value.isFinite else { return "" }
            let string = String(value)
            if let exponent = string.firstIndex(of: "e"), !string[..<exponent].contains(".") {
                return String(string[..<exponent]) + ".0" + string[exponent...]
            }
            return string
        case .string(let value): return value
        case .array(let value): return value.map(\.text).joined()
        }
    }

    var truthy: Bool {
        switch self { case .null, .bool(false): return false; default: return true }
    }

    var isEmpty: Bool {
        switch self {
        case .string(let v): return v.isEmpty
        case .array(let v): return v.isEmpty
        case .object(let v): return v.isEmpty
        case .empty: return true
        default: return false
        }
    }

    var isBlank: Bool {
        if case .string(let v) = self { return v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return !truthy || isEmpty || self == .blank
    }

    var numeric: Double {
        switch self {
        case .number(let value), .decimal(let value): return value
        case .string(let value):
            let pattern = #"^[\s]*[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)"#
            guard let range = value.range(of: pattern, options: .regularExpression) else { return 0 }
            return Double(String(value[range]).trimmed) ?? 0
        default: return 0
        }
    }

    /// Filters use Ruby-style collection stringification, unlike array output.
    var filterText: String {
        switch self { case .array, .object: return inspected; default: return text }
    }

    var inspected: String {
        switch self {
        case .null: return "nil"
        case .string(let string):
            if let data = try? JSONEncoder().encode(string), let result = String(data: data, encoding: .utf8) { return result.replacingOccurrences(of: "\\/", with: "/") }
            return "\"\""
        case .array(let values): return "[" + values.map(\.inspected).joined(separator: ", ") + "]"
        case .object(let object): return "{" + object.keys.sorted().map { Value.string($0).inspected + "=>" + (object[$0] ?? .null).inspected }.joined(separator: ", ") + "}"
        default: return text
        }
    }

    var flattened: [Value] {
        switch self {
        case .range(let first, let last): return first <= last ? (first...last).map { .number(Double($0)) } : []
        case .array(let values): return values.flatMap(\.flattened)
        case .null: return [.null]
        default: return [self]
        }
    }

    func member(_ key: String) -> Value {
        switch self {
        case .selfDrop(let value): return value.lookup(key)
        case .range(let first, let last):
            if key == "size" { return .number(first <= last ? Double(last - first + 1) : 0) }
            if key == "first" { return .number(Double(first)) }
            if key == "last" { return .number(Double(last)) }
            return .null
        case .object(let values):
            if let value = values[key] { return value }
            if key == "first", let first = values.keys.sorted().first { return .array([.string(first), values[first] ?? .null]) }
            return key == "size" ? .number(Double(values.count)) : .null
        case .array(let values):
            if key == "size" { return .number(Double(values.count)) }
            if key == "first" { return values.first ?? .null }
            if key == "last" { return values.last ?? .null }
            if let index = Int(key) {
                let offset = index < 0 ? values.count + index : index
                return values.indices.contains(offset) ? values[offset] : .null
            }
            return .null
        case .string(let value): return key == "size" ? .number(Double(value.count)) : .null
        case .number: return key == "size" ? .number(8) : .null
        default: return .null
        }
    }

    func member(_ key: Value) -> Value {
        switch key {
        case .string(let value):
            if case .array = self { return .null }
            if case .object(let values) = self { return values[value] ?? .null }
            return member(value)
        case .number(let value), .decimal(let value):
            guard case .array = self, value.isFinite, value >= Double(Int.min), value < Double(Int.max) else { return .null }
            return member(String(Int(value)))
        default: return .null
        }
    }

    func equals(_ other: Value) -> Bool {
        if (self == .empty || self == .blank) && (other == .empty || other == .blank) { return false }
        if self == .empty { return other.isEmpty }
        if other == .empty { return isEmpty }
        if self == .blank { return other.isBlank }
        if other == .blank { return isBlank }
        if isNumeric && other.isNumeric { return numeric == other.numeric }
        if case .array(let lhs) = self, case .array(let rhs) = other {
            return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.equals($1) }
        }
        if case .object(let lhs) = self, case .object(let rhs) = other {
            return lhs.count == rhs.count && lhs.allSatisfy { key, value in
                rhs[key].map { value.equals($0) } ?? false
            }
        }
        return self == other
    }

    var isNumeric: Bool {
        switch self { case .number, .decimal: return true; default: return false }
    }

    var typeName: String {
        switch self {
        case .number: return "Integer"
        case .decimal: return "Float"
        case .string: return "String"
        case .array: return "Array"
        case .object: return "Hash"
        case .bool(let value): return value ? "TrueClass" : "FalseClass"
        case .null: return "NilClass"
        case .range: return "Range"
        case .selfDrop: return "Liquid::SelfDrop"
        case .empty, .blank: return "Symbol"
        }
    }

    var isDecimal: Bool {
        if case .decimal = self { return true }
        if case .string(let value) = self {
            return value.trimmed.range(of: #"^[+-]?[0-9]*\.[0-9]+"#, options: .regularExpression) != nil
        }
        return false
    }
}
