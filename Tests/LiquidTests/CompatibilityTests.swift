import Foundation
import XCTest
import Liquid

final class CompatibilityTests: XCTestCase {
    func testModernTagsAndCounterIsolation() throws {
        let source = """
        {% liquid
        # An unmatched apostrophe in a comment must not consume the closing delimiter.
        assign value = 'hi'
        echo value | upcase
        comment
          arbitrary invalid syntax {{
        endcomment
        %}{% doc %}ignored {{ {% enddoc note %}{% for n in (1..3) %}{% cycle 'a', 'b' %}{% endfor %}
        """
        let template = try Template(source)
        XCTAssertEqual(try template.render(), "HIaba")
        XCTAssertEqual(try template.render(), "HIaba")
        XCTAssertEqual(try Template("{% assign x = 'a' %}{% cycle x, 'b' %}{% cycle x, 'b' %}").render(), "aa")
        XCTAssertEqual(try Template("{% for x in xs %}{% ifchanged %}{{ x }}{% endifchanged %}{% endfor %}").render(["xs": [1, 1, 2, 2]]), "12")
    }

    func testPartialScopesParametersAndRegisters() throws {
        let template = try Template("{% assign name = 'outer' %}{% increment c %}{% include 'shared', arg: name %}{{ name }}{% render 'isolated', arg: name %}{% increment c %}", partials: [
            "shared": "{{ arg }}{% assign name = 'changed' %}{% increment c %}",
            "isolated": "[{{ name }}:{{ arg }}:{{ shop }}]{% increment c %}{% assign name = 'hidden' %}",
        ])
        XCTAssertEqual(try template.render(["shop": "global"]), "0outer1changed[:changed:global]02")
        let loop = try Template("{% render 'card' for products as p, label: 'P' %}", partials: ["card": "{{ label }}{{ forloop.index }}:{{ p }};"])
        XCTAssertEqual(try loop.render(["products": ["a", "b"]]), "P1:a;P2:b;")
        let dynamic = try Template("{% include selected %}", partials: ["a": "A", "b": "B"])
        XCTAssertEqual(try dynamic.render(["selected": "a"]), "A")
        XCTAssertEqual(try dynamic.render(["selected": "b"]), "B")
    }

    func testPartialsShareBudgetsAndCannotIncludeFromRender() throws {
        let template = try Template("{% for i in (1..2) %}{% render 'child' %}{% endfor %}", iterationLimit: 4,
                                    partials: ["child": "{% for j in (1..2) %}{{ j }}{% endfor %}"])
        XCTAssertThrowsError(try template.render())
        let recursive = try Template("{% render 'a' %}", partials: ["a": "{% render 'a' %}"])
        XCTAssertThrowsError(try recursive.render())
        let disabled = try Template("{% render 'a' %}", partials: ["a": "{% include 'b' %}", "b": "bad"])
        XCTAssertThrowsError(try disabled.render())
        XCTAssertThrowsError(try Template("{% render template %}"))
        XCTAssertThrowsError(try Template("{% include '../secret' %}", partials: ["../secret": "secret"]).render())
    }

    func testCaseFallthroughCountersAndDynamicLookup() throws {
        XCTAssertEqual(try Template("{% case 'a' %}{% when 'a', 'a' %}M{% when 'a' %}N{% else %}bad{% endcase %}").render(), "MMN")
        XCTAssertEqual(try Template("{{ n }}{% increment n %}:{{ n }}{% decrement n %}:{{ n }}").render(), "0:10:0")
        XCTAssertEqual(try Template("{% assign key = 'title' %}{{ self[key] }}:{{ self.title }}:{{ nil.size }}").render(["title": "Hello"]), "Hello:Hello:")
        XCTAssertEqual(try Template("{% assign xs = (1..3) %}{{ xs }}:{{ xs | join: ',' }}").render(), "1..3:1,2,3")
        XCTAssertEqual(try Template("before{% break %}after").render(), "before")
        XCTAssertEqual(try Template("{% if 5 > true %}bad{% else %}ok{% endif %}").render(), "ok")
        XCTAssertThrowsError(try Template("{% if 5 > 'text' %}{% endif %}").render())
    }

    func testReferenceFilterCoercionAndOptionalForms() throws {
        XCTAssertEqual(try Template("{{ 5 | reverse | join }}:{{ nil | default }}:{{ 'abc' | replace: 'b' }}:{{ 'x' | unknown | upcase }}").render(), "5::ac:X")
        XCTAssertEqual(try Template("{{ 'hello' | first }}{{ 'hello' | last }}:{{ 4 | size }}").render(), "ho:8")
        XCTAssertEqual(try Template("{{ xs | sum }}:{{ text | base64_encode | base64_decode }}").render(["xs": [0.1, 0.2, 0.3], "text": "你好"]), "0.6:你好")
        XCTAssertEqual(try Template("{{ xs | sum }}").render(["xs": [1e200]]), "1.0e+200")
        XCTAssertEqual(try Template("{{ xs | uniq: 'key' | map: 'name' | join: ',' }}").render(["xs": [["key": 1, "name": "a"], ["key": 1, "name": "b"]]]), "a")
        XCTAssertEqual(try Template("{{ 'hi' | replace: '', 'x' }}").render(), "xhxix")
        XCTAssertEqual(try Template("{{ 'hi' | upcase: | append: '!', }}").render(), "HI!")
        XCTAssertEqual(try Template("{{ xs | slice: offset | join }}").render(["xs": [1, 2], "offset": Double.greatestFiniteMagnitude]), "")
    }

    func testFrozenDateAndPortableFormatting() throws {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(try Template("{{ 'now' | date: '%F %T %Z' }}").render(currentTime: date), "1970-01-01 00:00:00 UTC")
        XCTAssertEqual(try Template("{{ '2020-06-05' | date: '%-d|%_d|%0d|%^b|%#B|%C' }}").render(), "5| 5|05|JUN|JUNE|20")
        XCTAssertEqual(try Template("{{ '2021-01-01' | date: '%G-%V-%u' }}").render(), "2020-53-5")
        XCTAssertEqual(try Template("{{ '2020-06-15 14:30:45 -0400' | date: '%H:%M %:z' }}").render(), "14:30 -04:00")
    }

    func testRawBoundariesAndNestedComments() throws {
        XCTAssertEqual(try Template("{% raw -%}  x  {%- endraw %}{%- assign a = 1 %}").render(), "  x  ")
        XCTAssertEqual(try Template("A{% comment %}outer{% comment %}inner{% endcomment %}end{% endcomment %}B").render(), "AB")
        XCTAssertThrowsError(try Template("{% # first\nnot a comment %}"))
    }
}
