import Foundation

/// A filter receives the input value and its positional arguments.
public typealias LiquidFilter = (_ value: Any?, _ arguments: [Any?]) throws -> Any?

/// Parses once and renders with fresh variables and counters on each call.
open class Template {
    private let nodes: [Node]
    private let filters: [String: LiquidFilter]
    private let iterationLimit: Int

    public init(_ source: String = "", filters: [String: LiquidFilter] = [:], iterationLimit: Int = 100_000) throws {
        guard iterationLimit > 0 else { throw TemplateRenderError("iterationLimit must be positive") }
        var parser = SyntaxParser(tokens: try Lexer(templateString: source).tokenize())
        nodes = try parser.parse()
        self.filters = filters
        self.iterationLimit = iterationLimit
    }

    public convenience init(templateString: String) throws { try self.init(templateString) }

    public func render(_ dictionary: [String: Any] = [:]) throws -> String {
        try render(context: Context(dictionary: dictionary))
    }

    public func render(context: Context) throws -> String {
        try RenderState(context: context, filters: filters, iterationLimit: iterationLimit).render(nodes).parts.joined()
    }
}

final class RenderState {
    enum Flow { case normal, breakLoop, continueLoop }
    struct Result {
        var parts: [String] = []
        var flow: Flow = .normal
    }
    let context: Context
    let filters: [String: LiquidFilter]
    let iterationLimit: Int
    var iterations = 0
    var counters: [String: Int] = [:]
    var offsets: [String: Int] = [:]

    init(context: Context, filters: [String: LiquidFilter] = [:], iterationLimit: Int = 100_000) {
        self.context = context
        self.filters = filters
        self.iterationLimit = iterationLimit
    }

    func render(_ nodes: [Node]) throws -> Result {
        var result = Result()
        for node in nodes {
            switch node {
            case .text(let text): result.parts.append(text)
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
            case .selection(let expression, let branches, let fallback):
                let value = try expression.evaluate(self)
                var body = fallback
                for (alternatives, branch) in branches {
                    if try alternatives.contains(where: { value.equals(try $0.evaluate(self)) }) { body = branch; break }
                }
                let rendered = try render(body)
                result.parts += rendered.parts
                if rendered.flow != .normal { result.flow = rendered.flow; return result }
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
        case .array(let values): items = values
        case .object(let values): items = values.keys.sorted().map { .array([.string($0), values[$0] ?? .null]) }
        default: items = []
        }
        func bounded(_ expression: Expression?, default defaultValue: Int) throws -> Int {
            guard let expression else { return defaultValue }
            let value = try expression.evaluate(self).numeric
            guard value.isFinite else { throw TemplateRenderError("Invalid for limit or offset") }
            return Int(min(Double(items.count), max(0, value)))
        }
        let offset = statement.continues ? min(offsets[statement.key, default: 0], items.count) : try bounded(statement.offset, default: 0)
        let limit = try bounded(statement.limit, default: items.count)
        items = Array(items.dropFirst(offset).prefix(limit))
        if statement.reversed { items.reverse() }
        guard !items.isEmpty else { return try render(fallback) }
        let previousItem = context[statement.variable]
        let previousLoop = context["forloop"]
        defer {
            context[statement.variable] = previousItem
            context["forloop"] = previousLoop
        }
        var result = Result()
        for (index, item) in items.enumerated() {
            iterations += 1
            guard iterations <= iterationLimit else { throw TemplateRenderError("Loop iteration limit exceeded") }
            context.set(item, for: statement.variable)
            context["forloop"] = [
                "name": statement.key, "index": index + 1, "index0": index,
                "rindex": items.count - index, "rindex0": items.count - index - 1,
                "first": index == 0, "last": index == items.count - 1, "length": items.count,
                "parentloop": previousLoop ?? NSNull()
            ] as [String: Any]
            offsets[statement.key] = offset + index + 1
            let rendered = try render(body)
            result.parts += rendered.parts
            if rendered.flow == .breakLoop { break }
        }
        return result
    }
}
