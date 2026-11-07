import Testing
@testable import SuuTensai

private func parse(_ source: String) throws -> Program { try Parser(source: source).parse() }
private func expression(_ source: String) throws -> Expression { try Parser(source: source).parseExpression() }

private func theorem(_ source: String) throws -> FunctionDeclaration {
    let program = try parse(source)
    let first = try #require(program.declarations.first)
    guard case .theorem(let value) = first else {
        Issue.record("Expected a theorem")
        throw TestFailure.wrongNode
    }
    return value
}

private enum TestFailure: Error { case wrongNode, missingError }

private func failure(_ source: String, isExpression: Bool = false) throws -> FrontendError {
    do {
        if isExpression { _ = try expression(source) } else { _ = try parse(source) }
    } catch let error as FrontendError {
        #expect(error.span.start.utf8Offset >= 0)
        #expect(error.span.end.utf8Offset <= source.utf8.count)
        #expect(error.span.start.utf8Offset <= error.span.end.utf8Offset)
        return error
    }
    Issue.record("Expected a frontend error for \(source.debugDescription)")
    throw TestFailure.missingError
}

@Suite struct LexerTests {
    @Test func keywordsAndOperators() throws {
        let tokens = try Lexer("theorem def axiom Gamma let return fun Type Prop _ -> => == != && || + - * / % ^ ! = < > ( ) { } : , ;").tokenize()
        #expect(tokens.map(\.kind) == [
            .theorem, .definition, .axiom, .gamma, .let, .return, .fun, .type, .prop, .hole,
            .arrow, .fatArrow, .binaryOp(.equal), .binaryOp(.notEqual), .binaryOp(.logicalAnd),
            .binaryOp(.logicalOr), .binaryOp(.plus), .binaryOp(.minus), .binaryOp(.multiply),
            .binaryOp(.divide), .binaryOp(.remainder), .binaryOp(.power), .bang, .assign,
            .leftAngle, .rightAngle, .leftParen, .rightParen, .leftBrace, .rightBrace,
            .colon, .comma, .semicolon, .endOfFile
        ])
    }

    @Test func keywordBoundariesAndUnicode() throws {
        let tokens = try Lexer("theoremX Type2 _hole α ισότητα değişken x\u{301}").tokenize()
        #expect(tokens.dropLast().allSatisfy { if case .identifier = $0.kind { true } else { false } })
        #expect(tokens[3].lexeme == "α")
        #expect(tokens[6].lexeme == "x\u{301}")
    }

    @Test func nestedCommentsAndLineBreaks() throws {
        let tokens = try Lexer("x/* outer /* inner */\n end */y // tail\r\nz").tokenize()
        #expect(tokens.map(\.lexeme) == ["x", "y", "z", ""])
        #expect(!tokens[0].isPrecededByLineBreak)
        #expect(tokens[1].isPrecededByLineBreak)
        #expect(tokens[2].isPrecededByLineBreak)
        #expect(tokens[2].span.start.line == 3)
    }

    @Test(arguments: ["\n", "\r", "\r\n", "\u{000B}", "\u{000C}", "\u{0085}", "\u{2028}", "\u{2029}"])
    func lineEndings(_ newline: String) throws {
        let tokens = try Lexer("α" + newline + "  β").tokenize()
        #expect(tokens[1].span.start == SourcePosition(utf8Offset: 2 + newline.utf8.count + 2, line: 2, column: 3))
        #expect(tokens[1].isPrecededByLineBreak)
        #expect(!tokens[2].isPrecededByLineBreak)
    }

    @Test func stringsAndEscapes() throws {
        let source = #""hello\n\t\r\0\"\\\u{1F642}\u{03B1}""#
        let tokens = try Lexer(source).tokenize()
        #expect(tokens[0].kind == .string("hello\n\t\r\0\"\\🙂α"))
        #expect(tokens[0].lexeme == source)
        #expect(tokens[0].span.end.utf8Offset == source.utf8.count)
        #expect(try Lexer(#""/* not a comment */ // either""#).tokenize()[0].kind == .string("/* not a comment */ // either"))
    }

    @Test func arbitrarySizeNumbers() throws {
        let digits = String(repeating: "9", count: 20_000)
        #expect(try Lexer(digits).tokenize()[0].kind == .number(digits))
        #expect(try expression(digits).kind == .number(digits))
    }

    @Test(arguments: [
        "@", "#private", ".", "&", "|", "12abc", "12α", "/* never closed",
        "\"never closed", "\"raw\nnewline\"", #""\q""#, #""\u{}""#,
        #""\u{110000}""#, #""\u{D800}""#, #""\u{1234567}""#,
        #""\u{xyz}""#, #""\u1234""#, #""\u{12""#, "\"trailing\\"
    ])
    func invalidLexemes(_ source: String) throws {
        #expect(throws: FrontendError.self) { try Lexer(source).tokenize() }
    }

    @Test func repeatedScanning() throws {
        let lexer = Lexer("theorem id<A: Type>(x: A) -> A { x }")
        #expect(try lexer.tokenize() == lexer.tokenize())
    }

    @Test func exactSpans() throws {
        let source = "  α -> F<β>(123) // end"
        let bytes = Array(source.utf8)
        let tokens = try Lexer(source).tokenize()
        for token in tokens {
            let range = token.span.start.utf8Offset..<token.span.end.utf8Offset
            #expect(String(decoding: bytes[range], as: UTF8.self) == token.lexeme)
        }
        #expect(tokens[0].span.start.column == 3)
        #expect(tokens[0].span.end.column == 4)
        #expect(tokens.last?.span.end.utf8Offset == bytes.count)
    }
}

@Suite struct ParserTests {
    @Test func requestedSyntax() throws {
        let source = "theorem reflexivity<A: Type>(x: A)->A { return x }"
        let value = try theorem(source)
        #expect(value.signature.name == "reflexivity")
        #expect(value.signature.genericParameters.map(\.name) == ["A"])
        #expect(value.signature.genericParameters[0].type.kind == .universe(.type(level: 0)))
        #expect(value.signature.parameters.map(\.name) == ["x"])
        #expect(value.signature.parameters[0].type.kind == .identifier("A"))
        #expect(value.signature.returnType.kind == .identifier("A"))
        #expect(value.body.result == nil)
        #expect(value.body.statements.count == 1)
        guard case .return(let result) = value.body.statements[0].kind else { throw TestFailure.wrongNode }
        #expect(result.kind == .identifier("x"))
        #expect(value.span.start.utf8Offset == 0)
        #expect(value.span.end.utf8Offset == source.utf8.count)
    }

    @Test func allDeclarationFormsAndOrdering() throws {
        let program = try parse("""
        Gamma Base {
            A: Type;
            x: A
            P: A -> Prop
        }
        axiom refl<A: Type>(x: A) -> Eq<A>(x, x);
        def id<A: Type>(x: A) -> A { x };
        theorem use<A: Type>(x: A) -> A { return id<A>(x); }
        """)
        #expect(program.declarations.count == 4)
        guard case .context(let context) = program.declarations[0],
              case .axiom(let axiom) = program.declarations[1],
              case .definition(let definition) = program.declarations[2],
              case .theorem(let theorem) = program.declarations[3] else { throw TestFailure.wrongNode }
        #expect(context.bindings.map(\.name) == ["A", "x", "P"])
        #expect(axiom.name == "refl")
        #expect(axiom.returnType.sourceDescription == "Eq<A>(x, x)")
        #expect(definition.body.result?.kind == .identifier("x"))
        #expect(theorem.signature.name == "use")
    }

    @Test func letsReturnsAndTailExpressions() throws {
        let value = try theorem("""
        theorem test<A: Type>(x: A) -> A {
            let y: A = x
            let z = id<A>(y);
            observe(z);
            z
        }
        """)
        #expect(value.body.statements.count == 3)
        guard case .binding(let name, let annotation, let initializer) = value.body.statements[0].kind else {
            throw TestFailure.wrongNode
        }
        #expect(name == "y")
        #expect(annotation?.kind == .identifier("A"))
        #expect(initializer.kind == .identifier("x"))
        #expect(value.body.result?.kind == .identifier("z"))
    }

    @Test func nestedBlocksAndLambdas() throws {
        let value = try theorem("""
        theorem build<A: Type>() -> A -> A {
            let f = fun (x: A,) => { let y = x; return y; }
            f
        }
        """)
        #expect(value.body.statements[0].sourceDescription == "Let f = (fun (x: A) => { Let y = x; Return y })")
        #expect(try expression("fun () => x").sourceDescription == "(fun () => x)")
        #expect(try expression("(fun (x: A) => x)(y)").sourceDescription == "(fun (x: A) => x)(y)")
    }

    @Test func dependentTypes() throws {
        let type = try expression("(A: Type) -> (x: A, _: A) -> Eq<A>(x, x)")
        guard case .dependentFunction(let parameters, let result) = type.kind,
              case .dependentFunction(let inner, _) = result.kind else { throw TestFailure.wrongNode }
        #expect(parameters.map(\.name) == ["A"])
        #expect(inner.map(\.name) == ["x", "_"])
        #expect(try expression("F<(x: A) -> B(x)>").sourceDescription == "F<((x: A) -> B(x))>")
    }

    @Test func nestedGenericsCallsAndTrailingCommas() throws {
        let value = try expression("f<F<G<A>>, B,>(x, g(y,),)()")
        #expect(value.sourceDescription == "f<F<G<A>>, B>(x, g(y))()")
        let function = try theorem("theorem f<A: Type, B: Type,>(x: A, y: B,) -> A {x}")
        #expect(function.signature.genericParameters.count == 2)
        #expect(function.signature.parameters.count == 2)
    }

    @Test(arguments: [
        ("a + b * c", "(a + (b * c))"),
        ("a - b - c", "((a - b) - c)"),
        ("a / b % c", "((a / b) % c)"),
        ("a ^ b ^ c", "(a ^ (b ^ c))"),
        ("-a ^ 2", "(-(a ^ 2))"),
        ("a ^ -b", "(a ^ (-b))"),
        ("!p && q || r", "(((!p) && q) || r)"),
        ("a + b == c * d && p", "(((a + b) == (c * d)) && p)"),
        ("A -> B -> C", "(A -> (B -> C))"),
        ("(A -> B) -> C", "((A -> B) -> C)"),
        ("+f<A>(x) != -y", "((+f<A>(x)) != (-y))")
    ])
    func precedence(_ pair: (String, String)) throws {
        #expect(try expression(pair.0).sourceDescription == pair.1)
    }

    @Test func emptyInputsAndOptionalGenerics() throws {
        #expect(try parse("").declarations.isEmpty)
        #expect(try parse(" // nothing\n /* empty */ ").declarations.isEmpty)
        #expect(try Parser(tokens: []).parse().declarations.isEmpty)
        #expect(try theorem("theorem t() -> Prop {}").body.statements.isEmpty)
        #expect(try theorem("theorem t() -> Prop { _ }").body.result?.kind == .hole)
    }

    @Test func newlinesContinueExpressions() throws {
        let value = try theorem("""
        theorem t() -> A {
            let f = g
                <A>
                (x)
            return
                f +
                y
        }
        """)
        #expect(value.body.statements.map(\.sourceDescription) == ["Let f = g<A>(x)", "Return (f + y)"])
    }

    @Test func parsingDoesNotPerformKernelWork() throws {
        let value = try theorem("theorem nonsense<A: Unknown, A: A>(x: Missing, x: Other) -> Bogus { return unbound; let z = _; }")
        #expect(value.signature.genericParameters.count == 2)
        #expect(value.signature.parameters.count == 2)
        #expect(value.body.statements.count == 2)
    }

    @Test(arguments: [
        "theorem", "theorem 42() -> A {}", "theorem Type() -> A {}",
        "theorem f<>()->A{}", "theorem f<A Type>()->A{}", "theorem f<A: Type()->A{}",
        "theorem f(x A)->A{}", "theorem f(x:A y:B)->A{}", "theorem f(x:A, ,)->A{}",
        "theorem f(x:A) A{}", "theorem f(x:A)->", "theorem f()->A", "theorem f()->A{",
        "theorem f()->A{return}", "theorem f()->A{return x y}", "theorem f()->A{let x:A;}",
        "theorem f()->A{let x = ;}", "theorem f()->A{let x = a let y = b}",
        "theorem f()->A{a b}", "theorem f()->A{} junk", "theorem f()->A{ theorem g()->A{} }",
        "axiom a()->A {}", "axiom a()->A axiom b()->B;", "Gamma C { x A }",
        "Gamma C { x: A y: B }", "Gamma C { x: A", "return x"
    ])
    func malformedPrograms(_ source: String) throws {
        let error = try failure(source)
        #expect(error.phase == .parser)
    }

    @Test(arguments: ["", "()", "(x", "(x: A)", "(x: A) => x", "f<>", "f(x y)", "F<A", "f(,)", "f(x,,)", "x =", "x +", "fun (x:A) -> x", "x y", "x < y", "x > y", "x === y"])
    func malformedExpressions(_ source: String) throws {
        let error = try failure(source, isExpression: true)
        #expect(error.phase == .parser)
    }

    @Test func diagnosticsHaveExactLocations() throws {
        let source = "theorem t() -> A {\n  let x = ;\n}"
        let error = try failure(source)
        #expect(error.span.start.line == 2)
        #expect(error.span.start.column == 11)
        #expect(error.render(source: source, fileName: "bad.rigor") == """
        bad.rigor:2:11: parser: Expected an expression; found ";".
          let x = ;
                  ^
        """)
        let unclosed = try failure("theorem t() -> A {\n")
        #expect(unclosed.span.start.line == 2)
        #expect(unclosed.span.start.column == 1)
        #expect(unclosed.message.contains("'}'"))
    }

    @Test func repeatedCallsAndTokenStreamValidation() throws {
        let source = "theorem t() -> A {return x}"
        let parser = try Parser(source: source)
        #expect(try parser.parse() == parser.parse())
        let tokens = try Lexer(source).tokenize()
        #expect(try Parser(tokens: Array(tokens.dropLast())).parse() == parser.parse())
        #expect(throws: FrontendError.self) { try Parser(tokens: [Token(kind: .endOfFile, lexeme: ""), Token(kind: .type, lexeme: "Type")]).parse() }
        let invalid = try Parser(source: "theorem")
        #expect(throws: FrontendError.self) { try invalid.parse() }
        #expect(throws: FrontendError.self) { try invalid.parse() }
    }
}

/// Fixed seed makes every generated regression reproducible.
private struct Generator {
    var state: UInt64 = 0x5A17_2026
    mutating func next(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 32) % UInt64(bound))
    }

    // A separate model supplies the expected structure instead of using the
    // parser/printer itself as the oracle.
    mutating func term(_ depth: Int) -> (source: String, shape: String) {
        if depth == 0 {
            let number = next(100)
            return ("\(number)", "n\(number)")
        }
        switch next(6) {
        case 0:
            let a = term(depth - 1), b = term(depth - 1)
            return ("(\(a.source) + \(b.source))", "+(\(a.shape),\(b.shape))")
        case 1:
            let a = term(depth - 1), b = term(depth - 1)
            return ("(\(a.source) * \(b.source))", "*(\(a.shape),\(b.shape))")
        case 2:
            let a = term(depth - 1), b = term(depth - 1)
            return ("(\(a.source) -> \(b.source))", "->(\(a.shape),\(b.shape))")
        case 3:
            let a = term(depth - 1)
            return ("(-\(a.source))", "neg(\(a.shape))")
        case 4:
            let a = term(depth - 1), b = term(depth - 1)
            return ("f(\(a.source), \(b.source),)", "call(f,\(a.shape),\(b.shape))")
        default:
            let a = term(depth - 1)
            return ("F<\(a.source)>", "spec(F,\(a.shape))")
        }
    }
}

private func shape(_ expression: Expression) -> String {
    switch expression.kind {
    case .number(let digits): return "n" + digits
    case .identifier(let name): return name
    case .binary(let op, let a, let b): return "\(op.rawValue)(\(shape(a)),\(shape(b)))"
    case .arrow(let a, let b): return "->(\(shape(a)),\(shape(b)))"
    case .unary(.negate, let a): return "neg(\(shape(a)))"
    case .application(let f, let args): return "call(" + ([shape(f)] + args.map(shape)).joined(separator: ",") + ")"
    case .specialization(let f, let args): return "spec(" + ([shape(f)] + args.map(shape)).joined(separator: ",") + ")"
    default: return "unexpected"
    }
}

@Suite struct StressTests {
    @Test func tenThousandDeclarations() throws {
        let source = (0..<10_000).map { "theorem t\($0)<A: Type>(x:A)->A{return x;}" }.joined(separator: "\n")
        let program = try parse(source)
        #expect(program.declarations.count == 10_000)
        guard case .theorem(let last) = program.declarations[9_999] else { throw TestFailure.wrongNode }
        #expect(last.signature.name == "t9999")
    }

    @Test func wideParameterArgumentAndStatementLists() throws {
        let parameters = (0..<2_000).map { "x\($0): A" }.joined(separator: ",")
        let arguments = (0..<2_000).map { "x\($0)" }.joined(separator: ",")
        let statements = (0..<5_000).map { "let y\($0) = x0;" }.joined()
        let value = try theorem("theorem wide(\(parameters))->A{\(statements)return f(\(arguments));}")
        #expect(value.signature.parameters.count == 2_000)
        #expect(value.body.statements.count == 5_001)
        guard case .return(let result) = value.body.statements.last?.kind,
              case .application(_, let args) = result.kind else { throw TestFailure.wrongNode }
        #expect(args.count == 2_000)
    }

    @Test func hugeCommentsAndIdentifiers() throws {
        let nested = String(repeating: "/*", count: 10_000) + String(repeating: "*/", count: 10_000)
        let identifier = "x" + String(repeating: "a", count: 100_000)
        let source = nested + String(repeating: " ", count: 500_000) + identifier
        let tokens = try Lexer(source).tokenize()
        #expect(tokens.count == 2)
        #expect(tokens[0].kind == .identifier(identifier))
        #expect(try Lexer("//" + String(repeating: "a", count: 500_000)).tokenize().count == 1)
    }

    @Test func acceptedDepthAndControlledRejection() throws {
        #expect(try expression(String(repeating: "(", count: 24) + "x" + String(repeating: ")", count: 24)).kind == .identifier("x"))
        let accepted = String(repeating: "F<", count: 24) + "A" + String(repeating: ">", count: 24)
        #expect(try expression(accepted).treeDepth == 25)
        let inputs = [
            String(repeating: "(", count: 10_000) + "x" + String(repeating: ")", count: 10_000),
            String(repeating: "!", count: 10_000) + "x",
            String(repeating: "A -> ", count: 10_000) + "A",
            String(repeating: "a + ", count: 10_000) + "a",
            String(repeating: "a ^ ", count: 10_000) + "a",
            "f" + String(repeating: "()", count: 10_000),
            String(repeating: "F<", count: 10_000) + "A" + String(repeating: ">", count: 10_000),
            String(repeating: "{", count: 10_000) + "x" + String(repeating: "}", count: 10_000),
            String(repeating: "fun (x: A) => ", count: 1_000) + "x",
            String(repeating: "(x: A) -> ", count: 1_000) + "A"
        ]
        for source in inputs {
            let error = try failure(source, isExpression: true)
            #expect(error.message.contains("depth limit"))
        }
        #expect(throws: FrontendError.self) { try Parser(source: "f()()()", maxNesting: 2).parseExpression() }
    }

    @Test func aThousandGeneratedExpressionTrees() throws {
        var generator = Generator()
        for _ in 0..<1_000 {
            let generated = generator.term(4)
            #expect(try shape(expression(generated.source)) == generated.shape)
        }
    }

    @Test func depthBoundaryAcrossEveryRecursivePath() throws {
        let wrappers: [(String, String)] = [
            ("(", ")"), ("F<", ">"), ("f(", ")"), ("!", ""),
            ("A -> ", ""), ("a ^ ", ""), ("{", "}"),
            ("{ let y = ", "; y }"), ("fun (x: A) => ", ""),
            ("(x: A) -> ", ""), ("(x: ", ") -> A")
        ]
        for (prefix, suffix) in wrappers {
            let accepted = String(repeating: prefix, count: 16) + "x" + String(repeating: suffix, count: 16)
            _ = try expression(accepted)
            let rejected = String(repeating: prefix, count: 40) + "x" + String(repeating: suffix, count: 40)
            // Even requesting an unlimited ceiling must stay safe on a worker.
            #expect(throws: FrontendError.self) { try Parser(source: rejected, maxNesting: .max).parseExpression() }
        }
        #expect(try Parser(source: "x", maxNesting: 0).parseExpression().kind == .identifier("x"))
        #expect(throws: FrontendError.self) { try Parser(source: "f()", maxNesting: .min).parseExpression() }
        _ = try expression(String(repeating: "(", count: 31) + "x" + String(repeating: ")", count: 31))
        #expect(throws: FrontendError.self) {
            try expression(String(repeating: "(", count: 32) + "x" + String(repeating: ")", count: 32))
        }
    }

    @Test func malformedTokenStreamFuzzing() throws {
        let kinds: [TokenKind] = [
            .identifier("x"), .type, .theorem, .definition, .axiom, .gamma, .let, .return,
            .fun, .prop, .hole, .number("1"), .string("x"), .arrow, .fatArrow, .assign,
            .leftParen, .rightParen, .leftAngle, .rightAngle, .leftBrace, .rightBrace,
            .comma, .colon, .semicolon, .binaryOp(.plus), .bang, .endOfFile
        ]
        var generator = Generator()
        for _ in 0..<1_000 {
            let tokens = (0..<generator.next(80)).map { _ in
                Token(kind: kinds[generator.next(kinds.count)], lexeme: "?",
                      isPrecededByLineBreak: generator.next(2) == 0)
            }
            do { _ = try Parser(tokens: tokens).parse() }
            catch is FrontendError { /* Rejection is the expected outcome for most streams. */ }
        }
    }

    @Test func allTruncationPoints() throws {
        let source = """
        Gamma C { A: Type; x: A; }
        axiom r<A: Type>(x: A) -> Eq<A>(x,x);
        theorem t<A: Type>(x: A) -> A {
            let f = fun (y: A) => { return y; };
            return f<A>(x);
        }
        """
        for end in source.indices {
            let truncated = String(source[..<end])
            do { _ = try parse(truncated) }
            catch let error as FrontendError { #expect(error.span.end.utf8Offset <= truncated.utf8.count) }
        }
    }

    @Test func deterministicMutationFuzzing() throws {
        let seed = Array("theorem t<A: Type>(x: A)->A { let f = fun (y:A)=>y; return f<A>(x); }")
        let insertions = Array("<>{}():;,=+-*/!^&|\"\\@_ abc123\n")
        var generator = Generator()
        for _ in 0..<2_000 {
            var characters = seed
            for _ in 0...generator.next(5) {
                let index = generator.next(characters.count + 1)
                switch generator.next(3) {
                case 0: characters.insert(insertions[generator.next(insertions.count)], at: index)
                case 1 where index < characters.count: characters.remove(at: index)
                case 2 where index < characters.count: characters[index] = insertions[generator.next(insertions.count)]
                default: break
                }
            }
            let source = String(characters)
            do { _ = try parse(source) }
            catch let error as FrontendError { #expect(error.span.end.utf8Offset <= source.utf8.count) }
        }
    }

    @Test func randomTextFuzzing() throws {
        let alphabet = Array("abcXYZ0123<>-+*/^%!=&|(){}:;, _\n\r\t\"\\@α🙂")
        var generator = Generator()
        for _ in 0..<3_000 {
            let source = String((0..<generator.next(160)).map { _ in alphabet[generator.next(alphabet.count)] })
            do { _ = try parse(source) }
            catch let error as FrontendError {
                #expect(error.span.start.utf8Offset >= 0)
                #expect(error.span.end.utf8Offset <= source.utf8.count)
            }
        }
    }
}
