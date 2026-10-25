import Foundation

struct ForStatement {
    let variable: String
    let collection: Expression
    var limit: Expression?
    var offset: Expression?
    var continues = false
    var reversed = false
    var columns: Expression?
    let key: String
}

struct PartialStatement {
    let isolated: Bool
    let name: Expression
    var binding: Expression?
    var each = false
    var alias: String?
    var arguments: [(String, Expression)] = []
}

indirect enum Node {
    case text(String), output(Expression), assign(String, Expression), capture(String, [Node])
    case rawText(String)
    case counter(String, decrement: Bool)
    case conditional([(Condition, [Node])], [Node])
    case selection(Expression, [([Expression]?, [Node])])
    case loop(ForStatement, [Node], [Node])
    case table(ForStatement, [Node])
    case cycle(Expression?, [Expression], String)
    case ifchanged([Node])
    case partial(PartialStatement)
    case breakLoop, continueLoop

    var isBlank: Bool {
        switch self {
        case .text(let text): return text.trimmed.isEmpty
        case .assign, .capture: return true
        case .conditional(let branches, let fallback): return branches.allSatisfy { $0.1.allSatisfy(\.isBlank) } && fallback.allSatisfy(\.isBlank)
        case .selection(_, let branches): return branches.allSatisfy { $0.1.allSatisfy(\.isBlank) }
        case .loop(_, let body, let fallback): return body.allSatisfy(\.isBlank) && fallback.allSatisfy(\.isBlank)
        default: return false
        }
    }
}

struct SyntaxParser {
    let tokens: [Token]
    var index = 0

    static func tag(_ source: String) -> (String, String) {
        if source.hasPrefix("#") { return ("#", String(source.dropFirst())) }
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
                case "raw":
                    let body = try parse(until: ["endraw"], loopDepth: loopDepth, depth: depth + 1)
                    nodes += body.map { if case .text(let text) = $0 { return .rawText(text) }; return $0 }
                    try consume("endraw")
                case "include", "render":
                    var p = try ExpressionParser(arguments)
                    let expression = try p.primary()
                    if name == "render", case .literal(.string) = expression {} else if name == "render" {
                        throw TemplateSyntaxError("Syntax error in tag 'render' - Template name must be a quoted string")
                    }
                    var statement = PartialStatement(isolated: name == "render", name: expression)
                    if p.current == .word("with") || p.current == .word("for") {
                        statement.each = p.take(.word("for"))
                        if !statement.each { try p.require(.word("with")) }
                        statement.binding = try p.primary()
                    }
                    if p.take(.word("as")) { statement.alias = try p.identifier() }
                    _ = p.take(.symbol(","))
                    while !p.isAtEnd {
                        let key = try p.identifier()
                        try p.require(.symbol(":"))
                        statement.arguments.append((key, try p.primary()))
                        _ = p.take(.symbol(","))
                    }
                    nodes.append(.partial(statement))
                case "echo": nodes.append(.output(try ExpressionParser.expression(arguments)))
                case "#":
                    for line in arguments.components(separatedBy: .newlines).dropFirst() where !line.trimmed.isEmpty && !line.trimmed.hasPrefix("#") {
                        throw TemplateSyntaxError("Syntax error in tag '#' - Each line of comments must be prefixed by the '#' character")
                    }
                case "ifchanged":
                    try noArguments(arguments, tag: name)
                    let body = try parse(until: ["endifchanged"], loopDepth: loopDepth, depth: depth + 1)
                    try consume("endifchanged")
                    nodes.append(.ifchanged(body))
                case "cycle":
                    var p = try ExpressionParser(arguments)
                    let first = try p.primary()
                    let group = p.take(.symbol(":")) ? first : nil
                    var values: [Expression] = group == nil ? [first] : [try p.primary()]
                    while p.take(.symbol(",")) {
                        if p.isAtEnd { break }
                        values.append(try p.primary())
                    }
                    try p.requireEnd()
                    let literals = values.allSatisfy { if case .literal = $0 { return true }; return false }
                    let key = literals ? String(describing: values) : UUID().uuidString
                    nodes.append(.cycle(group, values, key))
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
                    if branches.allSatisfy({ $0.1.allSatisfy(\.isBlank) }) && fallback.allSatisfy(\.isBlank) {
                        branches = branches.map { ($0.0, Self.removeBlankText($0.1)) }
                        fallback = Self.removeBlankText(fallback)
                    }
                    nodes.append(.conditional(branches, fallback))
                case "case":
                    let expression = try ExpressionParser.expression(arguments)
                    _ = try parse(until: ["when", "else", "endcase"], loopDepth: loopDepth, depth: depth + 1)
                    var branches: [([Expression]?, [Node])] = []
                    while true {
                        let alternatives: [Expression]?
                        if let args = try takeTag("when") {
                            var p = try ExpressionParser(args)
                            var values = [try p.primary()]
                            while p.take(.symbol(",")) || p.take(.word("or")) { values.append(try p.primary()) }
                            try p.requireEnd()
                            alternatives = values
                        } else if let args = try takeTag("else") {
                            try noArguments(args, tag: "else")
                            alternatives = nil
                        } else { break }
                        let body = try parse(until: ["when", "else", "endcase"], loopDepth: loopDepth, depth: depth + 1)
                        branches.append((alternatives, body))
                    }
                    try consume("endcase")
                    if branches.allSatisfy({ $0.1.allSatisfy(\.isBlank) }) {
                        branches = branches.map { ($0.0, Self.removeBlankText($0.1)) }
                    }
                    nodes.append(.selection(expression, branches))
                case "for", "tablerow":
                    let statement = try forStatement(arguments, table: name == "tablerow")
                    if name == "tablerow" {
                        let body = try parse(until: ["endtablerow"], loopDepth: loopDepth, depth: depth + 1)
                        try consume("endtablerow")
                        nodes.append(.table(statement, body))
                        continue
                    }
                    var body = try parse(until: ["else", "endfor"], loopDepth: loopDepth + 1, depth: depth + 1)
                    var fallback: [Node] = []
                    if let args = try takeTag("else") {
                        try noArguments(args, tag: "else")
                        fallback = try parse(until: ["endfor"], loopDepth: loopDepth, depth: depth + 1)
                    }
                    try consume("endfor")
                    if body.allSatisfy(\.isBlank) && fallback.allSatisfy(\.isBlank) {
                        body = Self.removeBlankText(body)
                        fallback = Self.removeBlankText(fallback)
                    }
                    nodes.append(.loop(statement, body, fallback))
                case "break", "continue":
                    try noArguments(arguments, tag: name)
                    nodes.append(name == "break" ? .breakLoop : .continueLoop)
                default: throw TemplateSyntaxError("Unknown tag '\(name)'")
                }
            }
        }
        if !stops.isEmpty { throw TemplateSyntaxError("Missing closing tag (expected \(stops.sorted().joined(separator: ", ")))") }
        return nodes
    }

    private static func removeBlankText(_ nodes: [Node]) -> [Node] {
        nodes.filter { if case .text = $0 { return false }; return true }
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

    private func forStatement(_ source: String, table: Bool = false) throws -> ForStatement {
        var p = try ExpressionParser(source)
        let variable = try p.identifier()
        try p.require(.word("in"))
        let collectionStart = p.index
        let collection = try p.primary()
        let collectionName = p.tokens[collectionStart..<p.index].map { token -> String in
            switch token {
            case .word(let s), .symbol(let s), .string(let s): return s
            case .number(let n): return Value.number(n).text
            case .decimal(let n): return Value.decimal(n).text
            }
        }.joined()
        let key = variable + "-" + collectionName
        var statement = ForStatement(variable: variable, collection: collection, key: key)
        var seen: Set<String> = []
        while !p.isAtEnd {
            if p.take(.symbol(",")) && p.isAtEnd { break }
            let option = try p.identifier()
            if !seen.insert(option).inserted && option == "reversed" { throw TemplateSyntaxError("Duplicate for option: \(option)") }
            if option == "reversed" { statement.reversed = true; continue }
            try p.require(.symbol(":"))
            if option == "offset", p.take(.word("continue")) { statement.continues = true }
            else if option == "offset" { statement.offset = try p.primary(); statement.continues = false }
            else if option == "cols" && table { statement.columns = try p.primary() }
            else if option == "limit" { statement.limit = try p.primary() }
            else { _ = try p.primary() }
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
