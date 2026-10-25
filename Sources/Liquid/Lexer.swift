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

        func appendLiquid(_ markup: String) throws {
            var ignored: [String] = []
            for line in markup.components(separatedBy: .newlines) where !line.trimmed.isEmpty {
                let value = line.trimmed
                let (name, arguments) = SyntaxParser.tag(value)
                if let top = ignored.last {
                    if name == "end" + top { ignored.removeLast() }
                    else if top != "raw" && ["comment", "doc", "raw"].contains(name) { ignored.append(name) }
                    continue
                }
                if name == "comment" || name == "doc" { ignored.append(name) }
                else if name == "liquid" { try appendLiquid(arguments) }
                else { tokens.append(.tag(value: value)) }
            }
            if let name = ignored.last { throw TemplateSyntaxError("Missing end\(name)") }
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
            let header = source[start.upperBound...].drop(while: { $0.isWhitespace || $0 == "-" })
            let inlineComment = !isVariable && header.hasPrefix("#")
            let liquidTag = !isVariable && header.hasPrefix("liquid")
            var commentLine = inlineComment
            var lineStart = false
            var end: Range<String.Index>?
            while cursor < source.endIndex {
                let character = source[cursor]
                if character == "\n" { commentLine = inlineComment; lineStart = true }
                else if liquidTag && lineStart && !character.isWhitespace {
                    commentLine = character == "#"; lineStart = false
                }
                if commentLine {
                    if source[cursor...].hasPrefix(closing) {
                        end = cursor..<source.index(cursor, offsetBy: 2); break
                    }
                } else if let current = quote {
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
            if case .tag(let body) = token, ["raw", "comment", "doc"].contains(SyntaxParser.tag(body).0) {
                let name = SyntaxParser.tag(body).0
                let pattern: String
                if name == "raw" { pattern = #"\{%-?\s*(endraw)\s*-?%\}"# }
                else if name == "doc" { pattern = #"\{%-?\s*(enddoc)\b[^%{]*?%\}"# }
                else { pattern = #"\{%-?\s*(\w+|#)?[\s\S]*?%\}"# }
                let regex = try NSRegularExpression(pattern: pattern)
                let search = NSRange(position..<source.endIndex, in: source)
                var stack = [name]
                var closing: Range<String.Index>?
                for match in regex.matches(in: source, range: search) {
                    guard let wordRange = Range(match.range(at: 1), in: source), let range = Range(match.range, in: source) else { continue }
                    let word = String(source[wordRange])
                    if word == "end" + (stack.last ?? "") {
                        stack.removeLast()
                        if stack.isEmpty { closing = range; break }
                    } else if stack.last == "comment" && ["raw", "comment", "doc"].contains(word) { stack.append(word) }
                }
                guard let closingRange = closing else { throw TemplateSyntaxError("Missing end\(name)") }
                trimNext = false
                if name == "raw" {
                    tokens.append(.tag(value: "raw"))
                    appendText(String(source[position..<closingRange.lowerBound]))
                    tokens.append(.tag(value: "endraw"))
                } else { tokens.append(.tag(value: "#")) }
                let closingMarkup = String(source[closingRange])
                trimNext = closingMarkup.hasSuffix("-%}")
                position = closingRange.upperBound
            } else if case .tag(let markup) = token, SyntaxParser.tag(markup).0 == "liquid" {
                try appendLiquid(SyntaxParser.tag(markup).1)
            } else { tokens.append(token) }
        }
        return tokens
    }
}
