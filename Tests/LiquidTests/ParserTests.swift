//
//  ParserTests.swift
//  Liquid
//
//  Created by YourtionGuo on 28/06/2017.
//
//

import XCTest
@testable import Liquid

class ParserTests: XCTestCase {
    
    func testParseText() throws {
        let lexer = Lexer(templateString: "aab  cc dd")
        let tokenize = try lexer.tokenize()
        let parser = TokenParser(tokens: tokenize, context: Context())
        let res = try parser.parse()
        XCTAssertEqual(res, ["aab  cc dd"])
    }
    
    func testParseVariable() throws {
        let dic = ["a": "A", "b": "BB", "c": "CCcCC"]
        let lexer = Lexer(templateString: "aab {{ a }} {{b}}c{{c}} d")
        let tokenize = try lexer.tokenize()
        let parser = TokenParser(tokens: tokenize, context: Context(dictionary: dic))
        let res = try parser.parse()
        XCTAssertEqual(res, ["aab ", "A", " ","BB","c", "CCcCC"," d"])
    }
    
    func testParseVariablePerformance() throws {
        let dic = ["a": "A", "b": "BB", "c": "CCcCC"]
        let lexer = Lexer(templateString: "aab {{ a }} {{b}}c{{c}} d")
        let tokenize = try lexer.tokenize()
        measure {
            let parser = TokenParser(tokens: tokenize, context: Context(dictionary: dic))
            XCTAssertNoThrow(try parser.parse())
        }
    }
    
}
