import Foundation

struct Lexer {
    let templateString: String

    func createToken(string: String) -> Token {
        guard string.count >= 4, string.hasPrefix("{{") || string.hasPrefix("{%") else {
            return .text(value: string)
        }
        var body = String(string.dropFirst(2).dropLast(2))
        if body.hasPrefix("-") { body.removeFirst() }
        if body.hasSuffix("-") { body.removeLast() }
        return string.hasPrefix("{{") ? .variable(value: body.trimmed) : .tag(value: body.trimmed)
    }

    func tokenize() throws -> [Token] {
        let source = templateString
        var position = source.startIndex
        var tokens: [Token] = []
        var trimNext = false

        func appendText(_ text: String) {
            let value = trimNext ? String(text.drop(while: \.isWhitespace)) : text
            trimNext = false
            if !value.isEmpty { tokens.append(.text(value: value)) }
        }
        func trimPrevious() {
            if case .text(let value) = tokens.last {
                tokens.removeLast()
                let trimmed = String(value.reversed().drop(while: \.isWhitespace).reversed())
                if !trimmed.isEmpty { tokens.append(.text(value: trimmed)) }
            }
        }

        while position < source.endIndex {
            let variable = source.range(of: "{{", range: position..<source.endIndex)
            let tag = source.range(of: "{%", range: position..<source.endIndex)
            guard let start = [variable, tag].compactMap({ $0 }).min(by: { $0.lowerBound < $1.lowerBound }) else {
                appendText(String(source[position...]))
                break
            }
            appendText(String(source[position..<start.lowerBound]))
            let isVariable = source[start] == "{{"
            let closing = isVariable ? "}}" : "%}"
            var cursor = start.upperBound
            var quote: Character?
            var end: Range<String.Index>?
            while cursor < source.endIndex {
                let character = source[cursor]
                if let current = quote {
                    if character == current { quote = nil }
                } else if source[cursor...].hasPrefix(closing) {
                    end = cursor..<source.index(cursor, offsetBy: 2)
                    break
                } else if character == "'" || character == "\"" { quote = character }
                cursor = source.index(after: cursor)
            }
            guard let end else { throw TemplateSyntaxError("Unclosed \(isVariable ? "output" : "tag") delimiter") }
            let markup = String(source[start.lowerBound..<end.upperBound])
            if markup.hasPrefix(isVariable ? "{{-" : "{%-") { trimPrevious() }
            trimNext = markup.hasSuffix(isVariable ? "-}}" : "-%}")
            let token = createToken(string: markup)
            position = end.upperBound

            // These bodies may contain arbitrary, even malformed, Liquid markup.
            if case .tag(let name) = token, name == "raw" || name == "comment" {
                let pattern = #"\{%-?\s*end"# + name + #"\s*-?%\}"#
                let regex = try NSRegularExpression(pattern: pattern)
                let search = NSRange(position..<source.endIndex, in: source)
                guard let match = regex.firstMatch(in: source, range: search),
                      let closingRange = Range(match.range, in: source) else {
                    throw TemplateSyntaxError("Missing end\(name)")
                }
                if name == "raw" { appendText(String(source[position..<closingRange.lowerBound])) }
                let closingMarkup = String(source[closingRange])
                if closingMarkup.hasPrefix("{%-") { trimPrevious() }
                trimNext = closingMarkup.hasSuffix("-%}")
                position = closingRange.upperBound
            } else { tokens.append(token) }
        }
        return tokens
    }
}
