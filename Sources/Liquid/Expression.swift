import Foundation

indirect enum LookupPart {
    case property(String)
    case bracket(Expression)
}

indirect enum Expression {
    case literal(Value)
    case lookup(String)
    case range(Expression, Expression)
    case filter(Expression, String, [Expression])
    case named(String, Expression)
    case access(Expression, [LookupPart])

    func evaluate(_ state: RenderState) throws -> Value {
        switch self {
        case .access(let base, let path):
            var value = try base.evaluate(state)
            for key in path {
                switch key {
                case .property(let name): value = value.member(name)
                case .bracket(let expression): value = value.member(try expression.evaluate(state))
                }
            }
            return value
        case .named(let name, let expression): return .object([name: try expression.evaluate(state)])
        case .literal(let value): return value
        case .lookup(let root): return state.resolve(root)
        case .range(let first, let last):
            let start = try first.evaluate(state).numeric
            let end = try last.evaluate(state).numeric
            guard start.isFinite, end.isFinite, start >= Double(Int.min), start < Double(Int.max),
                  end >= Double(Int.min), end < Double(Int.max) else {
                throw TemplateRenderError("Range bounds must be finite integers")
            }
            guard start <= end else { return .range(Int(start), Int(end)) }
            guard end - start < Double(state.iterationLimit) else {
                throw TemplateRenderError("Range exceeds the iteration limit")
            }
            return .range(Int(start), Int(end))
        case .filter(let input, let name, let arguments):
            let value = try input.evaluate(state)
            let args = try arguments.map { try $0.evaluate(state) }
            if let custom = state.filters[name] { return Value(try custom(value.any, args.map(\.any))) }
            return try BuiltinFilters.apply(name, to: value, arguments: args, currentTime: state.currentTime, strict: state.strictFilters)
        }
    }
}

indirect enum Condition {
    case negated(Condition)
    case value(Expression)
    case comparison(Expression, String, Expression)
    case logical(Condition, String, Condition)

    func evaluate(_ state: RenderState) throws -> Bool {
        switch self {
        case .negated(let condition): return try !condition.evaluate(state)
        case .value(let expression): return try expression.evaluate(state).truthy
        case .logical(let left, let op, let right):
            let lhs = try left.evaluate(state)
            if op == "and" && !lhs { return false }
            if op == "or" && lhs { return true }
            return try right.evaluate(state)
        case .comparison(let left, let op, let right):
            let lhs = try left.evaluate(state)
            let rhs = try right.evaluate(state)
            switch op {
            case "==": return lhs.equals(rhs)
            case "!=": return !lhs.equals(rhs)
            case "contains":
                if !rhs.truthy || !lhs.truthy { return false }
                if case .string(let text) = lhs {
                    let needle = rhs.filterText
                    return needle.isEmpty || text.contains(needle)
                }
                if rhs == .empty || rhs == .blank { return false }
                if case .array(let values) = lhs { return values.contains { $0.equals(rhs) } }
                if case .range(let first, let last) = lhs, rhs.isNumeric {
                    return rhs.numeric >= Double(first) && rhs.numeric <= Double(last)
                }
                return false
            default:
                let order: ComparisonResult
                if lhs.isNumeric && rhs.isNumeric {
                    let a = lhs.numeric, b = rhs.numeric
                    guard a.isFinite, b.isFinite else { return false }
                    order = a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
                } else if case .string(let a) = lhs, case .string(let b) = rhs { order = a.compare(b) }
                else if lhs == .null || rhs == .null { return false }
                else {
                    switch (lhs, rhs) {
                    case (.number, .string), (.decimal, .string), (.string, .number), (.string, .decimal):
                        throw TemplateRenderError("comparison of \(lhs.typeName) with \(rhs.typeName) failed")
                    default: return false
                    }
                }
                switch op {
                case ">": return order == .orderedDescending
                case "<": return order == .orderedAscending
                case ">=": return order != .orderedAscending
                case "<=": return order != .orderedDescending
                default: return false
                }
            }
        }
    }
}

enum ExpressionToken: Equatable {
    case word(String), string(String), number(Double), decimal(Double), symbol(String)
}

/// A small tokenizer/parser shared by output expressions and tag arguments.
struct ExpressionParser {
    let tokens: [ExpressionToken]
    var index = 0
    var current: ExpressionToken? { index < tokens.count ? tokens[index] : nil }
    var isAtEnd: Bool { index == tokens.count }

    init(_ source: String) throws {
        var result: [ExpressionToken] = []
        var cursor = source.startIndex
        while cursor < source.endIndex {
            let c = source[cursor]
            if c.isWhitespace { cursor = source.index(after: cursor); continue }
            if c == "'" || c == "\"" {
                let start = source.index(after: cursor)
                guard let end = source[start...].firstIndex(of: c) else { throw TemplateSyntaxError("Unclosed string literal") }
                result.append(.string(String(source[start..<end])))
                cursor = source.index(after: end)
                continue
            }
            if let op = ["..", "==", "!=", ">=", "<="].first(where: { source[cursor...].hasPrefix($0) }) {
                result.append(.symbol(op)); cursor = source.index(cursor, offsetBy: op.count); continue
            }
            if "[]().,:|><=".contains(c) {
                result.append(.symbol(String(c))); cursor = source.index(after: cursor); continue
            }
            let start = cursor
            let after = source.index(after: cursor)
            if c.isNumber || (c == "-" && after < source.endIndex && source[after].isNumber) {
                cursor = after
                while cursor < source.endIndex && source[cursor].isNumber { cursor = source.index(after: cursor) }
                if cursor < source.endIndex && source[cursor] == "." && !source[cursor...].hasPrefix("..") {
                    cursor = source.index(after: cursor)
                    while cursor < source.endIndex && source[cursor].isNumber { cursor = source.index(after: cursor) }
                }
                guard let number = Double(source[start..<cursor]), number.isFinite else { throw TemplateSyntaxError("Invalid number") }
                result.append(source[start..<cursor].contains(".") ? .decimal(number) : .number(number))
            } else {
                guard c.isLetter || c == "_" else { throw TemplateSyntaxError("Unexpected character '\(c)'") }
                cursor = after
                while cursor < source.endIndex && (source[cursor].isLetter || source[cursor].isNumber || "_-?".contains(source[cursor])) {
                    cursor = source.index(after: cursor)
                }
                result.append(.word(String(source[start..<cursor])))
            }
        }
        tokens = result
    }

    mutating func take(_ token: ExpressionToken) -> Bool {
        guard current == token else { return false }
        index += 1; return true
    }

    mutating func require(_ token: ExpressionToken) throws {
        guard take(token) else { throw TemplateSyntaxError("Expected \(token)") }
    }

    mutating func identifier() throws -> String {
        guard case .word(let value) = current else { throw TemplateSyntaxError("Expected a variable or filter name") }
        index += 1; return value
    }

    func requireEnd() throws {
        guard isAtEnd else { throw TemplateSyntaxError("Unexpected expression token: \(String(describing: current))") }
    }

    static func expression(_ source: String) throws -> Expression {
        if source.trimmed.isEmpty { return .literal(.null) }
        var parser = try Self(source)
        let value = try parser.pipeline()
        try parser.requireEnd()
        return value
    }

    static func condition(_ source: String) throws -> Condition {
        var parser = try Self(source)
        let condition = try parser.condition()
        try parser.requireEnd()
        return condition
    }

    mutating func pipeline() throws -> Expression {
        var value = try primary()
        while take(.symbol("|")) {
            let name = try identifier()
            var args: [Expression] = []
            if take(.symbol(":")) {
                if !isAtEnd && current != .symbol("|") { args.append(try argument()) }
                while take(.symbol(",")) {
                    if isAtEnd || current == .symbol("|") { break }
                    args.append(try argument())
                }
            }
            value = .filter(value, name, args)
        }
        return value
    }

    mutating func primary() throws -> Expression {
        var value: Expression
        switch current {
        case .string(let text): index += 1; value = .literal(.string(text))
        case .number(let number): index += 1; value = .literal(.number(number))
        case .decimal(let number): index += 1; value = .literal(.decimal(number))
        case .word(let name):
            index += 1
            if current == .symbol(".") || current == .symbol("[") { value = .lookup(name) }
            else { switch name {
            case "nil", "null": value = .literal(.null)
            case "true": value = .literal(.bool(true))
            case "false": value = .literal(.bool(false))
            case "empty": value = .literal(.empty)
            case "blank": value = .literal(.blank)
            default: value = .lookup(name)
            } }
        case .symbol("["):
            throw TemplateSyntaxError("Bare bracket access is not allowed. Use self[...] instead.")
        case .symbol("("):
            index += 1
            let first = try primary()
            try require(.symbol(".."))
            let last = try primary()
            try require(.symbol(")"))
            value = .range(first, last)
        default: throw TemplateSyntaxError("Expected a Liquid expression")
        }
        var path: [LookupPart] = []
        while true {
            if take(.symbol(".")) { path.append(.property(try identifier())) }
            else if take(.symbol("[")) { path.append(.bracket(try primary())); try require(.symbol("]")) }
            else { break }
        }
        if !path.isEmpty { value = .access(value, path) }
        return value
    }

    mutating func argument() throws -> Expression {
        if case .word(let name) = current, index + 1 < tokens.count, tokens[index + 1] == .symbol(":") {
            index += 2
            return .named(name, try primary())
        }
        return try primary()
    }

    mutating func condition() throws -> Condition {
        let left = try primary()
        var result: Condition = .value(left)
        if let op = current, ["==", "!=", ">", "<", ">=", "<="].map(ExpressionToken.symbol).contains(op) || op == .word("contains") {
            index += 1
            let name: String
            switch op { case .word(let s), .symbol(let s): name = s; default: name = "" }
            result = .comparison(left, name, try primary())
        }
        // Liquid evaluates logical operators from right to left (no grouping parentheses).
        if current == .word("and") || current == .word("or") {
            let name = try identifier()
            result = .logical(result, name, try condition())
        }
        return result
    }
}
