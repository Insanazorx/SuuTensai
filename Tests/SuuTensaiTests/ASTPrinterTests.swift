import Testing
@testable import SuuTensai

private enum PrinterTestFailure: Error { case wrongNode }

@Suite struct ASTPrinterTests {
    @Test func returnMatchIsStructuredAndPrintedRecursively() throws {
        let program = try Parser(source: """
        theorem example(x: A) -> B {
            return match x return func (v: A) => B {
                C(a) => g(a)
            }
        }
        """).parse()
        guard case .theorem(let function) = program.declarations[0],
              case .return(let result) = function.body.statements[0].kind,
              case .match(let match) = result.kind,
              case .lambda(let parameters, let motiveBody) = match.motive?.kind,
              case .constructor(let constructor, let fields) = match.cases[0].pattern.kind,
              case .application(let callee, let arguments) = match.cases[0].body.kind else {
            throw PrinterTestFailure.wrongNode
        }
        #expect(match.scrutinee.kind == .identifier("x"))
        #expect(parameters.map(\.name) == ["v"])
        #expect(motiveBody.kind == .identifier("B"))
        #expect(constructor == "C")
        #expect(fields[0].kind == .name("a"))
        #expect(callee.kind == .identifier("g"))
        #expect(arguments[0].kind == .identifier("a"))
        #expect(function.body.statements[0].astDescription == """
        Return
          Match
            Scrutinee
              Identifier x
            Motive
              Lambda
                Parameters
                  Parameter v
                    Type
                      Identifier A
                Body
                  Identifier B
            Cases
              Case
                Pattern
                  ConstructorPattern C
                    Arguments
                      NamePattern a
                Body
                  Application
                    Callee
                      Identifier g
                    Arguments
                      Identifier a
        """)
        #expect(program.astDescription.contains("Theorem example\n    Signature example"))
        #expect(!program.astDescription.contains("Return match"))
        #expect(!program.astDescription.contains("=>"))
    }

    @Test func everyDeclarationShowsItsTypedChildren() throws {
        let program = try Parser(source: """
        import "Fundamentals.rigor";
        Gamma Context { A: Type }
        inductive Box<A: Type>: Type { box: A -> Box<A> }
        axiom witness<A: Type>() -> A;
        def identity<A: Type>(x: A) -> A { x }
        theorem proof<A: Type>(x: A) -> A { return x }
        """).parse()
        let output = program.astDescription
        for label in [
            "  Import \"Fundamentals.rigor\"", "  Context Context",
            "  Inductive Box", "      Constructor box", "          Arrow",
            "  Axiom witness", "  Definition identity", "  Theorem proof",
            "        Universe Type(0)"
        ] {
            #expect(output.contains(label))
        }
        #expect(!output.contains("box: (A ->"))
        guard case .theorem(let function) = program.declarations.last else { throw PrinterTestFailure.wrongNode }
        #expect(function.signature.parameters[0].astDescription == """
        Parameter x
          Type
            Identifier A
        """)
        #expect(function.signature.astDescription.contains("Returns\n    Identifier A"))
        #expect(function.astDescription.hasPrefix("Function proof\n"))
    }

    @Test func bindingsStatementsTailValuesAndNestedBlocksAreSeparate() throws {
        let program = try Parser(source: """
        theorem t(x: A) -> A {
            let y: A = { let z = x; z };
            observe(y);
            y
        }
        """).parse()
        guard case .theorem(let function) = program.declarations[0] else { throw PrinterTestFailure.wrongNode }
        #expect(function.body.statements[0].astDescription == """
        Binding y
          Annotation
            Identifier A
          Value
            Block
              Statements
                Binding z
                  Value
                    Identifier x
              Result
                Identifier z
        """)
        #expect(function.body.statements[1].astDescription.hasPrefix("ExpressionStatement\n  Application\n"))
        #expect(function.body.result?.astDescription == "Identifier y")
    }

    @Test(arguments: [
        ("x", "Identifier x"),
        ("Type", "Universe Type(0)"),
        ("Type(2)", "Universe Type(2)"),
        ("Prop", "Universe Prop"),
        ("123", "Number 123"),
        (#""hello\nworld""#, #"String "hello\nworld""#),
        ("_", "Hole"),
        ("-x", "Unary -\n  Operand\n    Identifier x"),
        ("x + y", "Binary +\n  Left\n    Identifier x\n  Right\n    Identifier y"),
        ("A -> B", "Arrow\n  Domain\n    Identifier A\n  Codomain\n    Identifier B"),
        ("f()", "Application\n  Callee\n    Identifier f\n  Arguments"),
        ("F<A>", "Specialization\n  Callee\n    Identifier F\n  Arguments\n    Identifier A"),
        ("func (x: A) => x", "Lambda\n  Parameters\n    Parameter x\n      Type\n        Identifier A\n  Body\n    Identifier x"),
        ("(x: A) -> B(x)", "DependentFunction\n  Parameters\n    Parameter x\n      Type\n        Identifier A\n  Result\n    Application\n      Callee\n        Identifier B\n      Arguments\n        Identifier x"),
        ("{}", "Block\n  Statements"),
        ("match x {}", "Match\n  Scrutinee\n    Identifier x\n  Cases")
    ])
    func expressionTrees(_ sample: (String, String)) throws {
        #expect(try Parser(source: sample.0).parseExpression().astDescription == sample.1)
    }

    @Test func nestedPatternsStayIndented() throws {
        let expression = try Parser(source: "match xs { cons(pair(a,_),tail) => a }").parseExpression()
        guard case .match(let match) = expression.kind else { throw PrinterTestFailure.wrongNode }
        #expect(match.cases[0].pattern.astDescription == """
        ConstructorPattern cons
          Arguments
            ConstructorPattern pair
              Arguments
                NamePattern a
                WildcardPattern
            NamePattern tail
        """)
        #expect(match.astDescription == expression.astDescription)
        #expect(match.cases[0].astDescription.hasPrefix("Case\n  Pattern\n    ConstructorPattern cons"))
    }

    @Test func lambdaSpellingsHaveTheSameAST() throws {
        let short = try Parser(source: "fun (x: A) => x").parseExpression()
        let long = try Parser(source: "func (x: A) => x").parseExpression()
        #expect(short.astDescription == long.astDescription)
        #expect(short.sourceDescription == "(fun (x: A) => x)")
    }

    @Test func emptyProgramsAndBoundaryDepthPrintWithoutFlattening() throws {
        #expect(try Parser(source: "").parse().astDescription == "Program")
        let expression = try Parser(source: String(repeating: "!", count: 31) + "x").parseExpression()
        let output = expression.astDescription
        #expect(output.split(separator: "\n").filter { $0.drop(while: { $0 == " " }) == "Unary !" }.count == 31)
        #expect(output.hasSuffix(String(repeating: "  ", count: 62) + "Identifier x"))
        let wide = (0..<500).map { "C\($0) => x;" }.joined()
        let match = try Parser(source: "match x {\(wide)}").parseExpression()
        #expect(match.astDescription.split(separator: "\n").filter { $0 == "    Case" }.count == 500)
    }
}
