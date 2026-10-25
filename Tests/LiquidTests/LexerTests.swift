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
            XCTAssertNoThrow(try lexer.tokenize())
        }
    }

}
