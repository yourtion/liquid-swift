import Foundation
import CoreFoundation

/// Variables shared by a render. Use a separate mutable context per task.
public final class Context {
    var dictionaries: [String: Any?]

    public init(dictionary: [String: Any]? = nil) {
        dictionaries = (dictionary ?? [:]).mapValues { $0 }
    }

    public subscript(key: String) -> Any? {
        get { dictionaries[key] ?? nil }
        set { dictionaries[key] = newValue }
    }

    func value(for name: String) -> Value { Value(self[name]) }
    func set(_ value: Value, for name: String) { self[name] = value.any }
}

indirect enum Value: Equatable {
    case null, bool(Bool), number(Double), decimal(Double), string(String), array([Value]), object([String: Value])
    case empty, blank

    init(_ value: Any?) {
        guard let value, !(value is NSNull) else { self = .null; return }
        switch value {
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
        case .null, .empty, .blank, .object: return ""
        case .bool(let value): return value ? "true" : "false"
        case .number(let value):
            guard value.isFinite else { return "" }
            return value.rounded() == value ? String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), value) : String(value)
        case .decimal(let value): return value.isFinite ? String(value) : ""
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
        switch self { case .number(let value), .decimal(let value): return value; default: break }
        return Double(text) ?? 0
    }

    func member(_ key: String) -> Value {
        switch self {
        case .object(let values):
            if let value = values[key] { return value }
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
        default: return .null
        }
    }

    func equals(_ other: Value) -> Bool {
        if self == .empty { return other.isEmpty }
        if other == .empty { return isEmpty }
        if self == .blank { return other.isBlank }
        if other == .blank { return isBlank }
        if isNumeric && other.isNumeric { return numeric == other.numeric }
        return self == other
    }

    var isNumeric: Bool {
        switch self { case .number, .decimal: return true; default: return false }
    }

    var isDecimal: Bool {
        if case .decimal = self { return true }
        return false
    }
}
