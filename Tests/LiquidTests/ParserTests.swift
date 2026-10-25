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
    func testParseUntilAndCompileFilter() throws {
        let parser = TokenParser(tokens: [.text(value: "a"), .tag(value: "stop"), .variable(value: "missing")], context: Context())
        XCTAssertEqual(try parser.parse { _, token in token == .tag(value: "stop") }, ["a"])
        XCTAssertEqual(try parser.parse(), [""])
        XCTAssertEqual(try parser.compileFilter("'hi' | upcase"), "HI")
        XCTAssertNil(parser.nextToken())
    }
    
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
            do { _ = try parser.parse() }
            catch { XCTFail("Parsing failed: \(error)") }
        }
    }
    
}
