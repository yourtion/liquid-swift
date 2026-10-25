import Foundation

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    func trim(character: Character) -> String {
        String(drop(while: { $0 == character }).reversed().drop(while: { $0 == character }).reversed())
    }

    /// Splits only outside quotes, bracket lookups and ranges.
    func splitOutside(_ separator: Character, omittingEmpty: Bool = false) -> [String] {
        var parts: [String] = []
        var part = ""
        var quote: Character?
        var depth = 0
        for character in self {
            if let current = quote {
                part.append(character)
                if character == current { quote = nil }
            } else if character == "'" || character == "\"" {
                quote = character
                part.append(character)
            } else if character == "[" || character == "(" {
                depth += 1
                part.append(character)
            } else if character == "]" || character == ")" {
                depth -= 1
                part.append(character)
            } else if character == separator && depth == 0 {
                if !omittingEmpty || !part.isEmpty { parts.append(part) }
                part = ""
            } else { part.append(character) }
        }
        if !omittingEmpty || !part.isEmpty { parts.append(part) }
        return parts
    }

    func smartSplit(separator: Character = " ") -> [String] {
        splitOutside(separator, omittingEmpty: true)
    }
}
