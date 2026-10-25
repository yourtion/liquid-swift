import Foundation
import XCTest
import Liquid

final class TemplateTests: XCTestCase {
    private func render(_ source: String, _ variables: [String: Any] = [:]) throws -> String {
        try Template(source).render(variables)
    }

    func testPublicAPIAndRepeatedRendering() throws {
        let template = try Template(templateString: "Hello {{ name }}!{% increment n %}")
        XCTAssertEqual(try template.render(["name": "Swift"]), "Hello Swift!0")
        XCTAssertEqual(try template.render(["name": "Liquid"]), "Hello Liquid!0")
        XCTAssertEqual(try Template().render(), "")
        let context = Context(dictionary: ["name": "A"])
        context["name"] = "B"
        XCTAssertEqual(try template.render(context: context), "Hello B!0")
    }

    func testVariablesAndLiterals() throws {
        XCTAssertEqual(try render("{{ missing }}|{{ count }}|{{ yes }}|{{ no }}|{{ nil }}", ["count": 42, "yes": true, "no": false]), "|42|true|false|")
        XCTAssertEqual(try render("{{ '你好 Swift 🦉' }} {{ 2.5 }} {{ -2 }}"), "你好 Swift 🦉 2.5 -2")
        XCTAssertEqual(try render("{{ user.name }}:{{ users[which]['full name'] }}:{{ users[-1].size }}", [
            "user": ["name": "Ada"], "users": [["full name": "Grace"]], "which": 0
        ]), "Ada:Grace:1")
        XCTAssertEqual(try render("{{ xs.first }}{{ xs.last }}{{ xs.size }}{{ xs[99] }}", ["xs": [1, 2, 3]]), "133")
        XCTAssertEqual(try render("{{ obj.size }}", ["obj": ["size": "own property"]]), "own property")
    }

    func testRawCommentAndQuotedDelimiters() throws {
        XCTAssertEqual(try render("A{% raw %}{{ x }}{% if x %}{{{% endraw %}B"), "A{{ x }}{% if x %}{{B")
        XCTAssertEqual(try render("A{% comment %}{{ unclosed {% nonsense %}{% endcomment %}B"), "AB")
        XCTAssertEqual(try render("{{ '}}|%}' }}{% assign x = '%}' %}{{ x }}"), "}}|%}%}")
        XCTAssertEqual(try render("{% raw %}{% endraw %}{% comment %}{% endcomment %}"), "")
    }

    func testWhitespaceControl() throws {
        XCTAssertEqual(try render("A \n {{- 'B' -}} \t C"), "ABC")
        XCTAssertEqual(try render("A \n {%- assign x = 'B' -%} \n {{ x }}"), "AB")
        XCTAssertEqual(try render("A {% raw -%}  {{x}}  {%- endraw %} B"), "A   {{x}}   B")
        XCTAssertEqual(try render("A {%- comment -%} ignored {%- endcomment -%} B"), "AB")
        XCTAssertEqual(try render("{{ '' }} {{ ' ' }}"), "  ")
    }

    func testAssignCaptureAndIndependentCounters() throws {
        let source = "{% assign n = 9 %}{% increment n %}{% increment n %}{{ n }}{% decrement d %}{% decrement d %}{% capture title %}Hi {{ name | upcase }}{% endcapture %}{{ title }}"
        XCTAssertEqual(try render(source, ["name": "sam"]), "019-1-2Hi SAM")
        XCTAssertEqual(try render("{% assign n = 5.0 %}{{ n | divided_by: 2 }}|{{ n | divided_by: 2.0 }}"), "2.5|2.5")
        XCTAssertEqual(try render("{% assign xs = (1..3) %}{{ xs | join: ',' }}"), "1,2,3")
    }

    func testTruthyFalsyEmptyAndBlank() throws {
        for value: Any in [0, "", [Int](), [String: Int]()] {
            XCTAssertEqual(try render("{% if x %}yes{% else %}no{% endif %}", ["x": value]), "yes")
        }
        for value: Any in [false, NSNull()] {
            XCTAssertEqual(try render("{% if x %}yes{% else %}no{% endif %}", ["x": value]), "no")
        }
        XCTAssertEqual(try render("{% if absent == nil %}nil{% endif %}{% if xs == empty %}empty{% endif %}{% if text == blank %}blank{% endif %}", ["xs": [Int](), "text": " \n"]), "nilemptyblank")
        XCTAssertEqual(try render("{% if false == blank %}yes{% endif %}{% if nil == empty %}no{% endif %}"), "yes")
    }

    func testConditionsAndRightToLeftLogic() throws {
        XCTAssertEqual(try render("{% if n > 5 %}a{% elsif n >= 3 %}b{% else %}c{% endif %}", ["n": 3]), "b")
        XCTAssertEqual(try render("{% unless user %}guest{% else %}user{% endunless %}"), "guest")
        XCTAssertEqual(try render("{% if false and true or true %}wrong{% else %}right{% endif %}"), "right")
        XCTAssertEqual(try render("{% if true or false and false %}right{% else %}wrong{% endif %}"), "right")
        XCTAssertEqual(try render("{% if 2 == 2.0 and '2' != 2 and 2 <= 2 and 1 < 2 %}yes{% endif %}"), "yes")
        XCTAssertEqual(try render("{% if title contains 'Swift' and tags contains 'a' %}yes{% endif %}", ["title": "Swift Liquid", "tags": ["a", "b"]]), "yes")
        XCTAssertEqual(try render("{% if true %}{% unless false %}nested{% endunless %}{% endif %}"), "nested")
    }

    func testCaseAlternativesAndFallback() throws {
        let source = "{% case color %}\n{% when 'red', 'pink' %}warm{% when 'blue' or 'green' %}cool{% else %}other{% endcase %}"
        XCTAssertEqual(try render(source, ["color": "pink"]), "warm")
        XCTAssertEqual(try render(source, ["color": "green"]), "cool")
        XCTAssertEqual(try render(source, ["color": "black"]), "other")
    }

    func testLoopOptionsAndElse() throws {
        let source = "{% for n in (1..6) limit: 3 offset: 1 reversed %}{{ forloop.index }}:{{ n }};{% endfor %}"
        XCTAssertEqual(try render(source), "1:4;2:3;3:2;")
        XCTAssertEqual(try render("{% for n in xs %}bad{% else %}empty{% endfor %}", ["xs": []]), "empty")
        XCTAssertEqual(try render("{% for n in (3..1) %}bad{% else %}empty{% endfor %}"), "empty")
        XCTAssertEqual(try render("{% for n in (1..4) limit: 2 %}{{ n }}{% endfor %}{% for n in (1..4) offset: continue %}{{ n }}{% endfor %}"), "1234")
        XCTAssertEqual(try render("{% for n in (1..3) offset: 99 %}bad{% else %}empty{% endfor %}"), "empty")
    }

    func testBreakContinueAndNestedLoops() throws {
        let source = "{% for i in (1..5) %}{% if i == 2 %}{% continue %}{% endif %}{% if i == 4 %}{% break %}{% endif %}{{ i }}{% endfor %}"
        XCTAssertEqual(try render(source), "13")
        XCTAssertEqual(try render("{% for i in (1..2) %}{% for j in (1..2) %}{{ forloop.parentloop.index }}{{ j }}{% break %}{% endfor %}{{ forloop.index }}{% endfor %}"), "111212")
        XCTAssertEqual(try render("{% for i in (1..2) %}{{ forloop.first }}:{{ forloop.last }}:{{ forloop.rindex0 }};{% endfor %}"), "true:false:1;false:true:0;")
        let context = Context(dictionary: ["i": "original"])
        XCTAssertEqual(try Template("{% for i in (1..2) %}{% assign saved = i %}{% endfor %}{{ i }}{{ saved }}{{ forloop }}").render(context: context), "original2")
    }

    func testDictionaryLoop() throws {
        XCTAssertEqual(try render("{% for pair in obj %}{{ pair[0] }}={{ pair[1] }};{% endfor %}", ["obj": ["b": 2, "a": 1]]), "a=1;b=2;")
    }

    func testIntegration() throws {
        let source = """
        {%- assign title = heading | default: 'Products' -%}
        {{ title | escape }}:
        {%- for product in products -%}
          {%- if product.stock > 0 -%}
            [{{ forloop.index }} {{ product.name | upcase }} {{ product.price | times: 2 }}]
          {%- endif -%}
        {%- else -%} none
        {%- endfor -%}
        """
        XCTAssertEqual(try render(source, ["products": [["name": "tea", "stock": 2, "price": 3], ["name": "cup", "stock": 0, "price": 4]]]), "Products:[1 TEA 6]")
    }

    func testCustomFiltersAndErrors() throws {
        let template = try Template("{{ name | greet: '!' }}", filters: [
            "greet": { input, args in "Hi \(input as? String ?? "")\(args.first as? String ?? "")" }
        ])
        XCTAssertEqual(try template.render(["name": "Ada"]), "Hi Ada!")
        let failing = try Template("{{ 'x' | fail }}", filters: ["fail": { _, _ in throw TemplateRenderError("custom failure") }])
        XCTAssertThrowsError(try failing.render()) { XCTAssertEqual($0 as? TemplateRenderError, TemplateRenderError("custom failure")) }
    }

    func testInvalidTemplatesThrowSyntaxErrors() {
        let invalid = [
            "{{", "{%", "{{ | }}", "{{ 'unterminated }}", "{{ a[ }}", "{{ x | }}", "{{ x | : }}",
            "{% wat %}", "{% endif %}", "{% if x %}", "{% if %}x{% endif %}",
            "{% if x %}{% endfor %}", "{% if x %}{% else nope %}{% endif %}",
            "{% for x in xs %}", "{% for x xs %}{% endfor %}", "{% for x in xs limit: %}{% endfor %}",
            "{% for x in xs reversed reversed %}{% endfor %}",
            "{% assign x %}", "{% capture x %}", "{% increment %}", "{% raw %}", "{% comment %}",
            "{% if false %}{% invalid %}{% endif %}", "{% if (true) %}{% endif %}"
        ]
        for source in invalid {
            XCTAssertThrowsError(try Template(source), source) { XCTAssertTrue($0 is TemplateSyntaxError, "\(source): \($0)") }
        }
    }

    func testRuntimeErrorsAndResourceLimits() throws {
        for source in ["{{ 1 | divided_by: 0 }}", "{{ 2 | modulo: 0 }}", "{{ 'x' | replace }}", "{{ 1 | round: 99 }}", "{{ x | append: }}"] {
            XCTAssertThrowsError(try render(source, ["huge": Double.greatestFiniteMagnitude])) { XCTAssertTrue($0 is TemplateRenderError) }
        }
        XCTAssertThrowsError(try Template("{{ x | unknown }}", strictFilters: true).render())
        XCTAssertThrowsError(try Template("{% for x in (1..10) %}{{ x }}{% endfor %}", iterationLimit: 3).render())
        XCTAssertThrowsError(try Template("{% for x in xs %}{% for y in xs %}x{% endfor %}{% endfor %}", iterationLimit: 3).render(["xs": [1, 2]]))
        XCTAssertThrowsError(try Template("", iterationLimit: 0))
        XCTAssertThrowsError(try Template(String(repeating: "{% if true %}", count: 130) + String(repeating: "{% endif %}", count: 130)))
    }
}
