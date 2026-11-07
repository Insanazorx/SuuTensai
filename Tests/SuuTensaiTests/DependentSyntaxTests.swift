import Testing
@testable import SuuTensai

private func featureProgram(_ source: String) throws -> Program { try Parser(source: source).parse() }
private func featureExpression(_ source: String) throws -> Expression { try Parser(source: source).parseExpression() }
private enum FeatureTestFailure: Error { case wrongNode }

private func matchNode(_ source: String) throws -> MatchExpression {
    guard case .match(let value) = try featureExpression(source).kind else { throw FeatureTestFailure.wrongNode }
    return value
}

private let featureSource = """
import "Fundamentals.rigor";
inductive Nat: Type {
    zero: Nat;
    succ: Nat -> Nat;
}
inductive Id<A: Type>(x: A, y: A): Type {
    refl: (value: A) -> Id<A>(value, value);
}
theorem pred(n: Nat) -> Nat {
    return match n return fun (value: Nat) => Nat {
        zero => zero;
        succ(k) => k;
    }
}
"""

@Suite struct DependentSyntaxTests {
    @Test func newKeywordBoundaries() throws {
        let tokens = try Lexer("inductive match import inductiveX matchX importX").tokenize()
        #expect(tokens.map(\.kind) == [
            .inductive, .match, .import, .identifier("inductiveX"),
            .identifier("matchX"), .identifier("importX"), .endOfFile
        ])
    }

    @Test func explicitUniverseLevelsAndDefault() throws {
        #expect(try featureExpression("Type").kind == .universe(.type(level: 0)))
        #expect(try featureExpression("Type(0)").kind == .universe(.type(level: 0)))
        #expect(try featureExpression("Type ( /* level */ 2 )").kind == .universe(.type(level: 2)))
        #expect(try featureExpression("Type(0003)").kind == .universe(.type(level: 3)))
        #expect(try featureExpression("Type(\(Int.max))").kind == .universe(.type(level: Int.max)))
        #expect(try featureExpression("Prop").kind == .universe(.prop))
        let value = try featureExpression("Type(1) -> Type(2)")
        #expect(value.sourceDescription == "(Type(1) -> Type(2))")
        #expect(try featureExpression("F<Type(1)>(Type(0))").sourceDescription == "F<Type(1)>(Type)")
    }

    @Test(arguments: ["Type()", "Type(-1)", "Type(u)", "Type(1 + 1)", "Type(1,2)", "Type(1", "Type(" + String(repeating: "9", count: 100) + ")"])
    func invalidUniverseLevels(_ source: String) throws {
        #expect(throws: FrontendError.self) { try featureExpression(source) }
    }

    @Test func uniformParametersAndIndicesAreSeparate() throws {
        let program = try featureProgram(featureSource)
        #expect(program.declarations.count == 4)
        guard case .inductive(let nat) = program.declarations[1],
              case .inductive(let id) = program.declarations[2] else { throw FeatureTestFailure.wrongNode }
        #expect(nat.name == "Nat")
        #expect(nat.parameters.isEmpty)
        #expect(nat.indices.isEmpty)
        #expect(nat.constructors.map(\.name) == ["zero", "succ"])
        #expect(nat.sort.kind == .universe(.type(level: 0)))
        #expect(id.parameters.map(\.name) == ["A"])
        #expect(id.indices.map(\.name) == ["x", "y"])
        #expect(id.constructors[0].type.sourceDescription == "((value: A) -> Id<A>(value, value))")
    }

    @Test func emptyFamiliesDependentFieldsAndTrailingCommas() throws {
        let program = try featureProgram("""
        inductive Empty: Type {}
        inductive Sigma<A: Type, B: A -> Type,>(): Type {
            pair: (x: A, proof: B(x),) -> Sigma<A, B>
        };
        inductive Indexed<A: Type>(x: A,): Type(1) {}
        """)
        guard case .inductive(let empty) = program.declarations[0],
              case .inductive(let sigma) = program.declarations[1],
              case .inductive(let indexed) = program.declarations[2] else { throw FeatureTestFailure.wrongNode }
        #expect(empty.constructors.isEmpty)
        #expect(sigma.parameters.count == 2)
        #expect(sigma.indices.isEmpty)
        #expect(indexed.indices.count == 1)
        #expect(indexed.sort.kind == .universe(.type(level: 1)))
    }

    @Test func importsAreOnlySyntaxAndKeepDecodedPaths() throws {
        let program = try featureProgram(#"import "DefinitelyMissing.rigor"; import "folder\\proof.rigor""#)
        guard case .import(let first) = program.declarations[0],
              case .import(let second) = program.declarations[1] else { throw FeatureTestFailure.wrongNode }
        #expect(first.path == "DefinitelyMissing.rigor")
        #expect(second.path == "folder\\proof.rigor")
        #expect(try featureProgram("import \"a.rigor\"\nimport \"b.rigor\"\n").declarations.count == 2)
    }

    @Test func matchPatternsMotiveAndBranchBodies() throws {
        let value = try matchNode("""
        match value return fun (v: Either<A,B>) => C {
            left(a) => fromA(a);
            right(b) => { let answer = fromB(b); answer }
        }
        """)
        #expect(value.scrutinee.kind == .identifier("value"))
        #expect(value.motive != nil)
        #expect(value.cases.count == 2)
        guard case .constructor(let name, let args) = value.cases[0].pattern.kind else { throw FeatureTestFailure.wrongNode }
        #expect(name == "left")
        #expect(args[0].kind == .name("a"))
        #expect(value.cases[0].body.sourceDescription == "fromA(a)")
        guard case .block = value.cases[1].body.kind else { throw FeatureTestFailure.wrongNode }
    }

    @Test func nestedPatternsAndAllBranchSeparators() throws {
        let value = try matchNode("""
        match xs {
            nil() => zero,
            cons(pair(x, _), tail,) => x
            fallback => fallback;
        }
        """)
        #expect(value.cases.map { $0.pattern.sourceDescription } == ["nil()", "cons(pair(x, _), tail)", "fallback"])
        #expect(value.motive == nil)
        guard case .constructor(_, let fields) = value.cases[1].pattern.kind,
              case .constructor(_, let nested) = fields[0].kind else { throw FeatureTestFailure.wrongNode }
        #expect(nested[1].kind == .wildcard)
    }

    @Test func dependentMotiveMayBindIndicesAndProof() throws {
        let value = try matchNode("""
        match p return fun (x: A, y: A, proof: Id<A>(x,y)) => P(x,y,proof) {
            refl(z) => base(z)
        }
        """)
        guard case .lambda(let binders, _) = value.motive?.kind else { throw FeatureTestFailure.wrongNode }
        #expect(binders.map(\.name) == ["x", "y", "proof"])
    }

    @Test func emptyMatchNestedMatchAndPostfix() throws {
        #expect(try matchNode("match impossible return fun (e: Empty) => A {}").cases.isEmpty)
        let nested = try matchNode("match x { outer(y) => match y { inner(z) => z; _ => fallback } }")
        guard case .match = nested.cases[0].body.kind else { throw FeatureTestFailure.wrongNode }
        let applied = try featureExpression("(match x { _ => f })(y)")
        guard case .application(let callee, _) = applied.kind,
              case .match = callee.kind else { throw FeatureTestFailure.wrongNode }
    }

    @Test func recursorsUseExistingApplicationSyntax() throws {
        let value = try featureExpression("NatInd<fun (n: Nat) => P(n)>(base, step, n)")
        guard case .application(let callee, let arguments) = value.kind,
              case .specialization(let function, let motives) = callee.kind else { throw FeatureTestFailure.wrongNode }
        #expect(function.kind == .identifier("NatInd"))
        #expect(arguments.count == 3)
        #expect(motives.count == 1)
    }

    @Test func sourceSpansCoverAllNewNodes() throws {
        let source = """
        import "α.rigor";
        inductive T<A: Type>(x: A): Type(1) {
            ctor: A -> T<A>(x);
        }
        """
        let program = try featureProgram(source)
        let bytes = Array(source.utf8)
        func text(_ span: SourceSpan) -> String {
            String(decoding: bytes[span.start.utf8Offset..<span.end.utf8Offset], as: UTF8.self)
        }
        guard case .import(let file) = program.declarations[0],
              case .inductive(let type) = program.declarations[1] else { throw FeatureTestFailure.wrongNode }
        #expect(text(file.span) == "import \"α.rigor\";")
        #expect(text(type.parameters[0].span) == "A: Type")
        #expect(text(type.indices[0].span) == "x: A")
        #expect(text(type.sort.span) == "Type(1)")
        #expect(text(type.constructors[0].span) == "ctor: A -> T<A>(x);")
        let match = try matchNode("match x { cons(y, _) => y; }")
        #expect(match.span.start.utf8Offset == 0)
        #expect(match.cases[0].pattern.span.start.column == 11)
        #expect(match.cases[0].body.span.start.column == 25)
    }

    @Test func printerCoversNewDeclarationsAndExpressions() throws {
        let printed = try featureProgram(featureSource).astDescription
        #expect(printed.contains("Import \"Fundamentals.rigor\""))
        #expect(printed.contains("Inductive Id"))
        #expect(printed.contains("Indices\n      Parameter x\n        Type\n          Identifier A"))
        #expect(printed.contains("Constructor refl\n        Type\n          DependentFunction"))
        #expect(printed.contains("Return\n            Match\n              Scrutinee\n                Identifier n"))
        #expect(printed.contains("Motive\n                Lambda"))
        #expect(printed.contains("ConstructorPattern succ"))
    }

    @Test func semanticValidationRemainsForTheKernel() throws {
        _ = try featureProgram("""
        inductive Bad<A: Unknown>(x: Missing): NotAUniverse {
            bad: (Bad<A>(x) -> Nat) -> Wrong;
            bad: Missing;
        }
        theorem t() -> A { return match x { ctor(a,a) => missing; ctor(_) => missing } }
        """)
        // Positivity, valid universes, scope, constructor arity, duplicate names,
        // motive well-formedness, coverage, and termination are not parser checks.
    }

    @Test(arguments: [
        "inductive", "inductive 1: Type {}", "inductive N Type {}", "inductive N: Type",
        "inductive N<>: Type {}", "inductive N<A Type>: Type {}",
        "inductive N(x A): Type {}", "inductive N: Type { c Nat }",
        "inductive N: Type { c: }", "inductive N: Type { c: N d: N }",
        "inductive N: Type { c: N", "import", "import file", "import \"a\" import \"b\"",
        "theorem t()->A {import \"a.rigor\";}"
    ])
    func malformedDeclarations(_ source: String) throws {
        #expect(throws: FrontendError.self) { try featureProgram(source) }
    }

    @Test(arguments: [
        "match", "match x", "match x return {}", "match x { => x }", "match x { c -> x }",
        "match x { c => }", "match x { c => x d => y }", "match x { c(,) => x }",
        "match x { c(x,,) => x }", "match x { c(x => x }", "match x { 1 => x }",
        "match x { _() => x }", "match x { c<A>(x) => x }", "match x { c => x"
    ])
    func malformedMatches(_ source: String) throws {
        #expect(throws: FrontendError.self) { try featureExpression(source) }
    }

    @Test func deeplyNestedPatternsMatchesAndCombinedBudget() throws {
        let accepted = "match x { " + String(repeating: "cons(", count: 16) + "_" + String(repeating: ")", count: 16) + " => x }"
        _ = try matchNode(accepted)
        let deepPattern = "match x { " + String(repeating: "cons(", count: 10_000) + "_" + String(repeating: ")", count: 10_000) + " => x }"
        let deepMatches = String(repeating: "match x { _ => ", count: 10_000) + "x" + String(repeating: " }", count: 10_000)
        let mixed = String(repeating: "(", count: 20) + accepted + String(repeating: ")", count: 20)
        for source in [deepPattern, deepMatches, mixed] {
            #expect(throws: FrontendError.self) { try featureExpression(source) }
        }
        for depth in [16, 40] {
            let source = String(repeating: "match x { _ => ", count: depth) + "x" + String(repeating: " }", count: depth)
            if depth == 16 { _ = try featureExpression(source) }
            else { #expect(throws: FrontendError.self) { try featureExpression(source) } }
        }
    }

    @Test func wideConstructorsBranchesAndPatterns() throws {
        let constructors = (0..<2_000).map { "c\($0): N;" }.joined()
        let program = try featureProgram("inductive N: Type {\(constructors)}")
        guard case .inductive(let type) = program.declarations[0] else { throw FeatureTestFailure.wrongNode }
        #expect(type.constructors.count == 2_000)
        let cases = (0..<2_000).map { "c\($0) => x;" }.joined()
        #expect(try matchNode("match x {\(cases)}").cases.count == 2_000)
        let fields = (0..<2_000).map { "x\($0)" }.joined(separator: ",")
        let value = try matchNode("match x { ctor(\(fields)) => x }")
        guard case .constructor(_, let arguments) = value.cases[0].pattern.kind else { throw FeatureTestFailure.wrongNode }
        #expect(arguments.count == 2_000)
    }

    @Test func truncationAndMutationFuzzingForNewGrammar() throws {
        for end in featureSource.indices {
            let source = String(featureSource[..<end])
            do { _ = try featureProgram(source) }
            catch let error as FrontendError { #expect(error.span.end.utf8Offset <= source.utf8.count) }
        }
        var state: UInt64 = 0xC0FFEE_2026
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 32) % UInt64(bound))
        }
        let seeds = [
            featureSource, "match x return fun (x: Nat) => Nat { zero => zero; succ(k) => k; }",
            "match xs { cons(pair(a,_),tail) => a; nil() => fallback; }"
        ]
        let alphabet = Array("abc012(){}<>,:;_+-=>\" \n")
        for _ in 0..<2_000 {
            var characters = Array(seeds[next(seeds.count)])
            for _ in 0...next(5) {
                let index = next(characters.count + 1)
                if next(2) == 0 { characters.insert(alphabet[next(alphabet.count)], at: index) }
                else if index < characters.count { characters.remove(at: index) }
            }
            let source = String(characters)
            do {
                if source.hasPrefix("match") { _ = try featureExpression(source) }
                else { _ = try featureProgram(source) }
            } catch let error as FrontendError {
                #expect(error.span.start.utf8Offset >= 0)
                #expect(error.span.end.utf8Offset <= source.utf8.count)
            }
        }
    }
}
