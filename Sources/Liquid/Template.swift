import Foundation

/// A filter receives the input value and its positional arguments.
public typealias LiquidFilter = (_ value: Any?, _ arguments: [Any?]) throws -> Any?

/// Parses once and renders with fresh variables and counters on each call.
open class Template {
    private let nodes: [Node]
    private let filters: [String: LiquidFilter]
    private let iterationLimit: Int
    private let partials: [String: String]
    private let strictFilters: Bool

    public init(_ source: String = "", filters: [String: LiquidFilter] = [:], iterationLimit: Int = 100_000, partials: [String: String] = [:], strictFilters: Bool = false) throws {
        guard iterationLimit > 0 else { throw TemplateRenderError("iterationLimit must be positive") }
        var parser = SyntaxParser(tokens: try Lexer(templateString: source).tokenize())
        nodes = try parser.parse()
        self.filters = filters
        self.iterationLimit = iterationLimit
        self.partials = partials
        self.strictFilters = strictFilters
    }

    public convenience init(templateString: String) throws { try self.init(templateString) }

    public func render(_ dictionary: [String: Any] = [:], currentTime: Date? = nil) throws -> String {
        try render(context: Context(dictionary: dictionary), currentTime: currentTime)
    }

    public func render(context: Context, currentTime: Date? = nil) throws -> String {
        try RenderState(context: context, filters: filters, iterationLimit: iterationLimit, partials: partials, currentTime: currentTime, strictFilters: strictFilters).render(nodes).parts.joined()
    }
}

final class RenderState {
    final class Budget {
        var iterations = 0
        var depth = 0
        var partialCache: [String: [Node]] = [:]
    }
    enum Flow { case normal, breakLoop, continueLoop }
    struct Result {
        var parts: [String] = []
        var flow: Flow = .normal
    }
    let context: Context
    let filters: [String: LiquidFilter]
    let iterationLimit: Int
    let budget: Budget
    let partials: [String: String]
    let staticEnvironment: [String: Any]
    let currentTime: Date?
    let includeDisabled: Bool
    let strictFilters: Bool
    var iterations: Int {
        get { budget.iterations }
        set { budget.iterations = newValue }
    }
    var counters: [String: Int] = [:]
    var offsets: [String: Int] = [:]
    var cycles: [String: Int] = [:]
    var lastChanged: String?

    func resolve(_ name: String) -> Value {
        if context.hasLocal(name) || context.assignedNames.contains(name) { return context.value(for: name) }
        if let counter = counters[name] { return .number(Double(counter)) }
        if name == "self" && !context.hasVariable(name) { return .selfDrop(SelfLookup(self)) }
        return context.value(for: name)
    }

    init(context: Context, filters: [String: LiquidFilter] = [:], iterationLimit: Int = 100_000,
         partials: [String: String] = [:], currentTime: Date? = nil, budget: Budget = Budget(),
         staticEnvironment: [String: Any]? = nil, includeDisabled: Bool = false, strictFilters: Bool = false) {
        self.context = context
        self.filters = filters
        self.iterationLimit = iterationLimit
        self.partials = partials
        self.currentTime = currentTime
        self.budget = budget
        self.staticEnvironment = staticEnvironment ?? context.dictionaries.mapValues { $0 ?? NSNull() }
        self.includeDisabled = includeDisabled
        self.strictFilters = strictFilters
    }

    func render(_ nodes: [Node]) throws -> Result {
        var result = Result()
        for node in nodes {
            switch node {
            case .partial(let statement):
                let rendered = try renderPartial(statement)
                result.parts += rendered.parts
                if rendered.flow != .normal { result.flow = rendered.flow; return result }
            case .cycle(let group, let values, let implicitKey):
                let key = try group.map { try $0.evaluate(self).text } ?? implicitKey
                let index = cycles[key, default: 0] % values.count
                result.parts.append(try values[index].evaluate(self).text)
                cycles[key] = (index + 1) % values.count
            case .ifchanged(let body):
                let rendered = try render(body)
                let text = rendered.parts.joined()
                if text != lastChanged { result.parts.append(text); lastChanged = text }
                if rendered.flow != .normal { result.flow = rendered.flow; return result }
            case .table(let statement, let body):
                result.parts += try renderTable(statement, body: body).parts
            case .text(let text), .rawText(let text): result.parts.append(text)
            case .output(let expression): result.parts.append(try expression.evaluate(self).text)
            case .assign(let name, let expression): context.set(try expression.evaluate(self), for: name)
            case .capture(let name, let body):
                let captured = try render(body)
                context.set(.string(captured.parts.joined()), for: name)
                if captured.flow != .normal { result.flow = captured.flow; return result }
            case .counter(let name, let decrement):
                let value = counters[name, default: 0] - (decrement ? 1 : 0)
                counters[name] = value + (decrement ? 0 : 1)
                result.parts.append(String(value))
            case .conditional(let branches, let fallback):
                var body = fallback
                for (test, branch) in branches where try test.evaluate(self) { body = branch; break }
                let rendered = try render(body)
                result.parts += rendered.parts
                if rendered.flow != .normal { result.flow = rendered.flow; return result }
            case .selection(let expression, let branches):
                let value = try expression.evaluate(self)
                var matched = false
                for (alternatives, branch) in branches {
                    if let alternatives {
                        for alternative in alternatives where try value.equals(alternative.evaluate(self)) {
                            matched = true
                            let rendered = try render(branch)
                            result.parts += rendered.parts
                            if rendered.flow != .normal { result.flow = rendered.flow; return result }
                        }
                    } else if !matched {
                        let rendered = try render(branch)
                        result.parts += rendered.parts
                        if rendered.flow != .normal { result.flow = rendered.flow; return result }
                    }
                }
            case .loop(let statement, let body, let fallback):
                let rendered = try renderLoop(statement, body: body, fallback: fallback)
                result.parts += rendered.parts
                if rendered.flow != .normal { result.flow = rendered.flow; return result }
            case .breakLoop: result.flow = .breakLoop; return result
            case .continueLoop: result.flow = .continueLoop; return result
            }
        }
        return result
    }

    private func renderLoop(_ statement: ForStatement, body: [Node], fallback: [Node]) throws -> Result {
        let collection = try statement.collection.evaluate(self)
        var items: [Value]
        switch collection {
        case .range: items = collection.flattened
        case .array(let values): items = values
        case .object(let values): items = values.keys.sorted().map { .array([.string($0), values[$0] ?? .null]) }
        case .string(let value): items = value.isEmpty ? [] : [collection]
        default: items = []
        }
        func bounded(_ expression: Expression?, default defaultValue: Int) throws -> Int {
            guard let expression else { return defaultValue }
            let resolved = try expression.evaluate(self)
            if resolved == .null { return 0 }
            if case .string(let text) = resolved {
                guard text.trimmed.range(of: #"^[+-]?[0-9]+$"#, options: .regularExpression) != nil else { throw TemplateRenderError("invalid integer") }
            } else if !resolved.isNumeric { throw TemplateRenderError("invalid integer") }
            let value = resolved.numeric
            guard value.isFinite else { throw TemplateRenderError("Invalid for limit or offset") }
            return Int(min(Double(items.count), max(0, value)))
        }
        let offset = statement.continues ? min(offsets[statement.key, default: 0], items.count) : try bounded(statement.offset, default: 0)
        let limit = try bounded(statement.limit, default: items.count)
        items = Array(items.dropFirst(offset).prefix(limit))
        if statement.reversed { items.reverse() }
        offsets[statement.key] = offset + items.count
        guard !items.isEmpty else { return try render(fallback) }
        let previousLoop = context["forloop"]
        context.pushScope()
        defer { context.popScope() }
        var result = Result()
        for (index, item) in items.enumerated() {
            iterations += 1
            guard iterations <= iterationLimit else { throw TemplateRenderError("Loop iteration limit exceeded") }
            context.setLocal(item.any, for: statement.variable)
            context.setLocal([
                "name": statement.key, "index": index + 1, "index0": index,
                "rindex": items.count - index, "rindex0": items.count - index - 1,
                "first": index == 0, "last": index == items.count - 1, "length": items.count,
                "parentloop": previousLoop ?? NSNull()
            ] as [String: Any], for: "forloop")
            let rendered = try render(body)
            result.parts += rendered.parts
            if rendered.flow == .breakLoop { break }
        }
        return result
    }

    private func renderTable(_ statement: ForStatement, body: [Node]) throws -> Result {
        let collection = try statement.collection.evaluate(self)
        guard collection.truthy else { return Result() }
        var values: [Value] = []
        if case .array(let array) = collection { values = array }
        if case .range = collection { values = collection.flattened }
        if case .object(let object) = collection { values = object.keys.sorted().map { .array([.string($0), object[$0] ?? .null]) } }
        func integer(_ expression: Expression?, default fallback: Int) throws -> Int {
            guard let expression else { return fallback }
            let resolved = try expression.evaluate(self)
            switch resolved {
            case .number, .decimal, .string, .null: break
            default: throw TemplateRenderError("invalid integer")
            }
            let value = resolved.numeric
            guard value.isFinite, value >= Double(Int.min), value < Double(Int.max) else { throw TemplateRenderError("Invalid tablerow attribute") }
            return max(0, Int(value))
        }
        let offset = try integer(statement.offset, default: 0)
        let limit = try integer(statement.limit, default: values.count)
        if case .string(let string) = collection { values = string.isEmpty ? [] : [collection] }
        else { values = Array(values.dropFirst(offset).prefix(limit)) }
        let columnCount = try integer(statement.columns, default: values.count)
        let columns = columnCount > 0 ? columnCount : Int.max
        context.pushScope()
        defer { context.popScope() }
        var result = Result(parts: ["<tr class=\"row1\">\n"])
        for (index, item) in values.enumerated() {
            iterations += 1
            guard iterations <= iterationLimit else { throw TemplateRenderError("Loop iteration limit exceeded") }
            let col = index % columns + 1, row = index / columns + 1
            context.setLocal(item.any, for: statement.variable)
            context.setLocal([
                "index": index + 1, "index0": index, "rindex": values.count - index, "rindex0": values.count - index - 1,
                "first": index == 0, "last": index == values.count - 1, "length": values.count,
                "col": col, "col0": col - 1, "col_first": col == 1, "col_last": col == columns, "row": row
            ] as [String: Any], for: "tablerowloop")
            if index > 0 && col == 1 { result.parts.append("</tr>\n<tr class=\"row\(row)\">") }
            result.parts.append("<td class=\"col\(col)\">")
            let rendered = try render(body)
            result.parts += rendered.parts
            result.parts.append("</td>")
            if rendered.flow == .breakLoop { break }
        }
        result.parts.append("</tr>\n")
        return result
    }

    private func renderPartial(_ statement: PartialStatement) throws -> Result {
        guard statement.isolated || !includeDisabled else { throw TemplateRenderError("include usage is not allowed in this context") }
        guard budget.depth < 64 else { throw TemplateRenderError("Partial nesting too deep (limit 64)") }
        guard case .string(let name) = try statement.name.evaluate(self) else { throw TemplateRenderError("Illegal template name") }
        guard !name.hasPrefix("/"), !name.split(separator: "/").contains("..") else {
            throw TemplateRenderError("Illegal template name: \(name)")
        }
        let nodes: [Node]
        if let cached = budget.partialCache[name] { nodes = cached }
        else {
            guard let source = partials[name] ?? partials[name + ".liquid"] else { throw TemplateRenderError("Could not find template '\(name)'") }
            var parser = SyntaxParser(tokens: try Lexer(templateString: source).tokenize())
            nodes = try parser.parse()
            budget.partialCache[name] = nodes
        }
        budget.depth += 1
        defer { budget.depth -= 1 }
        let variable = statement.alias ?? String(name.split(separator: "/").last ?? "")
        let binding = try statement.binding?.evaluate(self) ?? (statement.isolated ? .null : context.value(for: name))
        let arguments = statement.isolated ? try statement.arguments.map { ($0.0, try $0.1.evaluate(self).any) } : []
        let items: [Value]
        if case .array(let array) = binding, statement.each || !statement.isolated { items = array }
        else { items = [binding] }
        var result = Result()
        for (index, item) in items.enumerated() {
            if statement.each || items.count > 1 {
                iterations += 1
                guard iterations <= iterationLimit else { throw TemplateRenderError("Loop iteration limit exceeded") }
            }
            let state: RenderState
            if statement.isolated {
                state = RenderState(context: Context(dictionary: staticEnvironment), filters: filters, iterationLimit: iterationLimit,
                                    partials: partials, currentTime: currentTime, budget: budget,
                                    staticEnvironment: staticEnvironment, includeDisabled: true, strictFilters: strictFilters)
            } else { state = self }
            state.context.pushScope(Dictionary(arguments, uniquingKeysWith: { _, last in last }))
            defer { state.context.popScope() }
            if !statement.isolated {
                for (key, expression) in statement.arguments { state.context.setLocal(try expression.evaluate(self).any, for: key) }
            }
            if item != .null || !statement.isolated { state.context.setLocal(item.any, for: variable) }
            if statement.each && statement.isolated {
                state.context.setLocal([
                    "name": name, "length": items.count, "index": index + 1, "index0": index,
                    "rindex": items.count - index, "rindex0": items.count - index - 1,
                    "first": index == 0, "last": index == items.count - 1
                ] as [String: Any], for: "forloop")
            }
            let rendered = try state.render(nodes)
            result.parts += rendered.parts
            if rendered.flow != .normal && !statement.isolated { result.flow = rendered.flow; return result }
        }
        return result
    }
}
