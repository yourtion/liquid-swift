//
//  LexerTests.swift
//  Liquid
//
//  Created by YourtionGuo on 28/06/2017.
//
//

import XCTest
@testable import Liquid

class LexerTests: XCTestCase {
    func testEmptyAndUnicodeStrings() throws {
        XCTAssertEqual("".trim(character: " "), "")
        XCTAssertEqual("   ".trim(character: " "), "")
        XCTAssertEqual(" a ".trim(character: " "), "a")
        XCTAssertEqual("  🦉你好  ".trim(character: " "), "🦉你好")
        XCTAssertEqual(try Lexer(templateString: "").tokenize(), [])
        XCTAssertEqual("a 'b c' \"d e\"".smartSplit(), ["a", "'b c'", "\"d e\""])
    }
    
    func testCreateToken() {
        let lexer = Lexer(templateString: "")
        
        let variable = lexer.createToken(string: "{{ a }}")
        XCTAssertEqual(variable.contents, "a")
        XCTAssertEqual(variable, .variable(value: "a"))
        
        let tag = lexer.createToken(string: "{% b %}")
        XCTAssertEqual(tag, .tag(value: "b"))
    }
    
    func testTokenize() throws {
        let lexer = Lexer(templateString: "aab {{ a }} cc{%d%}{{ e}}")
        let tokenize = try lexer.tokenize()
        XCTAssertEqual(tokenize.count, 5)
        XCTAssertEqual(tokenize[0], .text(value: "aab "))
        XCTAssertEqual(tokenize[1], .variable(value: "a"))
        XCTAssertEqual(tokenize[2], .text(value: " cc"))
        XCTAssertEqual(tokenize[3], .tag(value: "d"))
        XCTAssertEqual(tokenize[4], .variable(value: "e"))
        
        XCTAssertThrowsError(try Lexer(templateString: "{{ a").tokenize())
        
    }
    
    func testTokenizePerformance() {
        let lexer = Lexer(templateString: "aab {{ a }} cc{%d%}")
        measure {
            do { _ = try lexer.tokenize() }
            catch { XCTFail("Tokenization failed: \(error)") }
        }
    }

}
