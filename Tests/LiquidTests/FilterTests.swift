import Foundation
import XCTest
import Liquid

final class FilterTests: XCTestCase {
    private func check(_ expression: String, _ expected: String, variables: [String: Any] = [:], file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try Template("{{ \(expression) }}").render(variables), expected, expression, file: file, line: line)
    }

    func testNumericFilters() throws {
        let examples = [
            ("-2 | abs", "2"), ("2 | at_least: 4", "4"), ("9 | at_most: 4", "4"),
            ("2.1 | ceil", "3"), ("2.9 | floor", "2"), ("5 | plus: 3 | minus: 1 | times: 2", "14"),
            ("5 | divided_by: 2", "2"), ("5 | divided_by: 2.0", "2.5"), ("-5 | divided_by: 2", "-3"),
            ("5 | modulo: 2", "1"), ("2.56 | round: 1", "2.6"), ("2.56 | round", "3"),
            ("-5 | modulo: 2", "1"), ("5 | modulo: -2", "-1"),
            ("'3' | plus: 2", "5"), ("'no number' | plus: 2", "2"), ("1 | plus: 0.5", "1.5")
        ]
        for (expression, expected) in examples { try check(expression, expected) }
    }

    func testStringFiltersAndQuotedArguments() throws {
        let examples = [
            ("'hello' | append: ' world' | prepend: 'Say '", "Say hello world"),
            ("'hELLO WORLD' | capitalize", "Hello world"), ("'HELLO' | downcase | upcase", "HELLO"),
            ("' a b ' | strip", "a b"), ("' a ' | lstrip", "a "), ("' a ' | rstrip", " a"),
            ("'abcabc' | remove: 'a'", "bcbc"), ("'abcabc' | remove_first: 'a'", "bcabc"),
            ("'abcabc' | remove_last: 'a'", "abcbc"), ("'ab ab' | replace: 'ab', 'c'", "c c"),
            ("'ab ab' | replace_first: 'ab', 'c'", "c ab"), ("'ab ab' | replace_last: 'ab', 'c'", "ab c"),
            ("'a|b,c:d' | replace: '|', ':' | append: ',end'", "a:b,c:d,end"),
            ("'你好🦉' | size", "3"), ("'你好🦉' | slice: -2, 2", "好🦉"),
            ("'abcdef' | truncate: 5", "ab..."), ("'a b c d' | truncatewords: 2, '!'", "a b!"),
            ("'short' | truncate", "short"), ("'abc' | slice: -99", ""), ("'abc' | slice: 99", "")
        ]
        for (expression, expected) in examples { try check(expression, expected) }
        try check("text | strip_newlines", "ab", variables: ["text": "a\r\nb\n"])
        try check("text | newline_to_br", "a<br />\nb", variables: ["text": "a\nb"])
    }

    func testHTMLAndURLFilters() throws {
        try check("value | escape", "&lt;a title=&quot;x&quot;&gt;&amp;&#39;&lt;/a&gt;", variables: ["value": "<a title=\"x\">&'</a>"])
        try check("'&amp; <x> & new' | escape_once", "&amp; &lt;x&gt; &amp; new")
        try check("'<p>hi</p><!-- bye -->' | strip_html", "hi")
        try check("'你好 Swift&x' | url_encode | url_decode", "你好 Swift&x")
        try check("'a b+c' | url_encode", "a+b%2Bc")
    }

    func testArrayFilters() throws {
        let examples = [
            ("'a,b,c' | split: ',' | first", "a"), ("'abc' | split: '' | last", "c"),
            ("'a,,b,' | split: ',' | join: ':'", "a::b"), ("'' | split: ',' | size", "0"),
            ("'a,b,a' | split: ',' | uniq | reverse | join: '-'", "b-a"),
            ("'c,a,b' | split: ',' | sort | join", "a b c"),
            ("'b,A,c' | split: ',' | sort_natural | join: ','", "A,b,c"),
            ("xs | compact | join: ','", "1,2"), ("xs | compact | size", "2"),
            ("xs | slice: 1, 2 | compact | join", "2"),
            ("xs | concat: ys | compact | join: ','", "1,2,3,4")
        ]
        for (expression, expected) in examples {
            try check(expression, expected, variables: ["xs": [1, NSNull(), 2], "ys": [3, 4]])
        }
        try check("xs | sort | join: ','", "2,3.5,10", variables: ["xs": [10, 3.5, 2] as [Any]])
    }

    func testObjectArrayFilters() throws {
        let products: [[String: Any]] = [
            ["name": "tea", "price": 3, "available": true],
            ["name": "cup", "price": 2, "available": false],
            ["name": "bag", "price": 1, "available": true]
        ]
        try check("products | sort: 'price' | map: 'name' | join: ','", "bag,cup,tea", variables: ["products": products])
        try check("products | where: 'available' | map: 'name' | join: ','", "tea,bag", variables: ["products": products])
        try check("products | where: 'price', 2 | map: 'name' | first", "cup", variables: ["products": products])
        try check("products | compact: 'available' | size", "3", variables: ["products": products])
    }

    func testDefaultFilter() throws {
        for input: Any in [NSNull(), false, "", [Int]()] {
            try check("x | default: 'fallback'", "fallback", variables: ["x": input])
        }
        try check("0 | default: 7", "0")
        try check("' ' | default: 'x'", " ")
        try check("false | default: true, allow_false: true", "false")
        try check("false | default: true, allow_false: false", "true")
    }

    func testDateFilterFormattingAndOffsets() throws {
        try check("'2024-02-29' | date: '%Y/%m/%d %A'", "2024/02/29 Thursday")
        try check("0 | date: '%F %T %z'", "1970-01-01 00:00:00 +0000")
        try check("'2024-01-01T02:30:00+02:00' | date: '%H:%M'", "02:30")
        try check("'not a date' | date: '%Y'", "not a date")
    }
}
