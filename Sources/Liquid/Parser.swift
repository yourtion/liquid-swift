import Foundation

struct ForStatement {
    let variable: String
    let collection: Expression
    var limit: Expression?
    var offset: Expression?
    var continues = false
    var reversed = false
    let key: String
}

indirect enum Node {
    case text(String), output(Expression), assign(String, Expression), capture(String, [Node])
    case counter(String, decrement: Bool)
    case conditional([(Condition, [Node])], [Node])
    case selection(Expression, [([Expression], [Node])], [Node])
    case loop(ForStatement, [Node], [Node])
    case breakLoop, continueLoop
}

struct SyntaxParser {
    let tokens: [Token]
    var index = 0

    static func tag(_ source: String) -> (String, String) {
        let parts = source.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        return (parts.first.map(String.init) ?? "", parts.count > 1 ? String(parts[1]).trimmed : "")
    }

    mutating func parse(until stops: Set<String> = [], loopDepth: Int = 0, depth: Int = 0) throws -> [Node] {
        guard depth < 128 else { throw TemplateSyntaxError("Template nesting exceeds 128 levels") }
        var nodes: [Node] = []
        while index < tokens.count {
            let token = tokens[index]
            if case .tag(let markup) = token, stops.contains(Self.tag(markup).0) { return nodes }
            index += 1
            switch token {
            case .text(let text): nodes.append(.text(text))
            case .variable(let markup): nodes.append(.output(try ExpressionParser.expression(markup)))
            case .tag(let markup):
                let (name, arguments) = Self.tag(markup)
                switch name {
                case "assign":
                    var p = try ExpressionParser(arguments)
                    let variable = try p.identifier()
                    try p.require(.symbol("="))
                    let expression = try p.pipeline()
                    try p.requireEnd()
                    nodes.append(.assign(variable, expression))
                case "capture":
                    let variable = try singleName(arguments)
                    let body = try parse(until: ["endcapture"], loopDepth: loopDepth, depth: depth + 1)
                    try consume("endcapture")
                    nodes.append(.capture(variable, body))
                case "increment", "decrement":
                    nodes.append(.counter(try singleName(arguments), decrement: name == "decrement"))
                case "if", "unless":
                    var condition = try ExpressionParser.condition(arguments)
                    if name == "unless" { condition = .negated(condition) }
                    let end = name == "if" ? "endif" : "endunless"
                    let body = try parse(until: ["elsif", "else", end], loopDepth: loopDepth, depth: depth + 1)
                    var branches: [(Condition, [Node])] = [(condition, body)]
                    while let args = try takeTag("elsif") {
                        let test = try ExpressionParser.condition(args)
                        let branch = try parse(until: ["elsif", "else", end], loopDepth: loopDepth, depth: depth + 1)
                        branches.append((test, branch))
                    }
                    var fallback: [Node] = []
                    if let args = try takeTag("else") {
                        try noArguments(args, tag: "else")
                        fallback = try parse(until: [end], loopDepth: loopDepth, depth: depth + 1)
                    }
                    try consume(end)
                    nodes.append(.conditional(branches, fallback))
                case "case":
                    let expression = try ExpressionParser.expression(arguments)
                    let preamble = try parse(until: ["when", "else", "endcase"], loopDepth: loopDepth, depth: depth + 1)
                    guard preamble.allSatisfy({ if case .text(let text) = $0 { return text.trimmed.isEmpty }; return false }) else {
                        throw TemplateSyntaxError("Only whitespace is allowed before the first when")
                    }
                    var branches: [([Expression], [Node])] = []
                    while let args = try takeTag("when") {
                        var p = try ExpressionParser(args)
                        var alternatives = [try p.primary()]
                        while p.take(.symbol(",")) || p.take(.word("or")) { alternatives.append(try p.primary()) }
                        try p.requireEnd()
                        let body = try parse(until: ["when", "else", "endcase"], loopDepth: loopDepth, depth: depth + 1)
                        branches.append((alternatives, body))
                    }
                    var fallback: [Node] = []
                    if let args = try takeTag("else") {
                        try noArguments(args, tag: "else")
                        fallback = try parse(until: ["endcase"], loopDepth: loopDepth, depth: depth + 1)
                    }
                    try consume("endcase")
                    nodes.append(.selection(expression, branches, fallback))
                case "for":
                    let statement = try forStatement(arguments)
                    let body = try parse(until: ["else", "endfor"], loopDepth: loopDepth + 1, depth: depth + 1)
                    var fallback: [Node] = []
                    if let args = try takeTag("else") {
                        try noArguments(args, tag: "else")
                        fallback = try parse(until: ["endfor"], loopDepth: loopDepth, depth: depth + 1)
                    }
                    try consume("endfor")
                    nodes.append(.loop(statement, body, fallback))
                case "break", "continue":
                    try noArguments(arguments, tag: name)
                    guard loopDepth > 0 else { throw TemplateSyntaxError("\(name) must be inside a for loop") }
                    nodes.append(name == "break" ? .breakLoop : .continueLoop)
                default: throw TemplateSyntaxError("Unknown or unexpected tag: \(name)")
                }
            }
        }
        if !stops.isEmpty { throw TemplateSyntaxError("Missing closing tag (expected \(stops.sorted().joined(separator: ", ")))") }
        return nodes
    }

    private func singleName(_ source: String) throws -> String {
        var p = try ExpressionParser(source)
        let name = try p.identifier()
        try p.requireEnd()
        return name
    }

    private func noArguments(_ source: String, tag: String) throws {
        guard source.isEmpty else { throw TemplateSyntaxError("\(tag) does not accept arguments") }
    }

    private mutating func takeTag(_ name: String) throws -> String? {
        guard index < tokens.count, case .tag(let source) = tokens[index] else { return nil }
        let (tag, args) = Self.tag(source)
        guard tag == name else { return nil }
        index += 1
        return args
    }

    private mutating func consume(_ name: String) throws {
        guard let arguments = try takeTag(name) else { throw TemplateSyntaxError("Missing \(name)") }
        try noArguments(arguments, tag: name)
    }

    private func forStatement(_ source: String) throws -> ForStatement {
        var p = try ExpressionParser(source)
        let variable = try p.identifier()
        try p.require(.word("in"))
        let collection = try p.primary()
        let key = variable + ":" + String(describing: collection)
        var statement = ForStatement(variable: variable, collection: collection, key: key)
        var seen: Set<String> = []
        while !p.isAtEnd {
            let option = try p.identifier()
            guard seen.insert(option).inserted else { throw TemplateSyntaxError("Duplicate for option: \(option)") }
            if option == "reversed" { statement.reversed = true; continue }
            guard option == "limit" || option == "offset" else { throw TemplateSyntaxError("Unknown for option: \(option)") }
            try p.require(.symbol(":"))
            if option == "offset", p.take(.word("continue")) { statement.continues = true }
            else if option == "offset" { statement.offset = try p.primary() }
            else { statement.limit = try p.primary() }
        }
        return statement
    }
}

/// Low-level token renderer. Parsing throws instead of crashing on invalid input.
public final class TokenParser {
    private let tokens: [Token]
    private let context: Context
    private var index = 0

    public init(tokens: [Token], context: Context) {
        self.tokens = tokens
        self.context = context
    }

    public func nextToken() -> Token? {
        guard index < tokens.count else { return nil }
        defer { index += 1 }
        return tokens[index]
    }

    public func parse() throws -> [String] { try parse(nil) }

    public func parse(_ parseUntil: ((_ parser: TokenParser, _ token: Token) -> Bool)?) throws -> [String] {
        var selected: [Token] = []
        while let token = nextToken() {
            if parseUntil?(self, token) == true { break }
            selected.append(token)
        }
        var parser = SyntaxParser(tokens: selected)
        let nodes = try parser.parse()
        return try RenderState(context: context).render(nodes).parts
    }

    public func compileFilter(_ token: String) throws -> String {
        try ExpressionParser.expression(token).evaluate(RenderState(context: context)).text
    }
}
