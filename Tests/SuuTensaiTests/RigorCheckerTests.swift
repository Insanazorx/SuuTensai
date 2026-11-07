import Testing
@testable import SuuTensai

@Suite struct RigorCheckerTests {
    @Test func verifiesProofsAndDistinguishesEmptyInput() {
        let result = RigorChecker.check("theorem identity<A:Type>(x:A)->A { x }")
        #expect(result.status == .valid)
        #expect(result.declarations == ["identity"])
        #expect(result.axioms.isEmpty)
        #expect(RigorChecker.check("// henüz bir ispat yok").status == .empty)
    }

    @Test func preservesUnicodeDiagnosticOffsets() {
        let source = "// 🧠 Türkçe\r\ntheorem özdeşlik<A:Type>(x:A)->A { eksik }"
        let result = RigorChecker.check(source)
        #expect(result.status == .invalid)
        #expect(result.diagnostic?.phase == .kernel)
        #expect(result.diagnostic?.span.start.line == 2)
        if let span = result.diagnostic?.span {
            let bytes = Array(source.utf8)
            #expect(String(decoding: bytes[span.start.utf8Offset..<span.end.utf8Offset], as: UTF8.self) == "eksik")
        } else { Issue.record("Hata konumu bekleniyordu") }
    }

    @Test func separatesSyntaxErrorsFromProofErrors() {
        let syntax = RigorChecker.check("theorem broken(")
        #expect(syntax.status == .invalid)
        #expect(syntax.diagnostic?.phase == .parser)
        let lexical = RigorChecker.check("@")
        #expect(lexical.diagnostic?.phase == .lexer)
        let proof = RigorChecker.check("theorem wrong<A:Type,B:Type>(x:A)->B { x }")
        #expect(proof.diagnostic?.phase == .kernel)
    }

    @Test func reportsExplicitAndTransitiveAxioms() {
        let result = RigorChecker.check("""
        axiom assume<P:Prop>() -> P;
        theorem use<P:Prop>() -> P { assume<P>() }
        """)
        #expect(result.status == .valid)
        #expect(result.axioms == ["assume"])
    }

    @Test func loadsOnlyExplicitImportsAndChecksTheirContents() {
        let imports = ["Base.rigor": "def identity<A:Type>(x:A)->A { x }"]
        let source = "import \"Base.rigor\"; theorem use<A:Type>(x:A)->A { identity<A>(x) }"
        let result = RigorChecker.check(source, imports: imports)
        #expect(result.status == .valid)
        #expect(result.declarations == ["identity", "use"])
        #expect(RigorChecker.check(source).diagnostic?.phase == .loader)
        let invalid = RigorChecker.check("import \"Bad.rigor\";", imports: ["Bad.rigor": "theorem broken("])
        #expect(invalid.diagnostic?.fileName == "Bad.rigor")
        #expect(invalid.diagnostic?.phase == .parser)
    }

    @Test func rejectsImportCyclesAndDeduplicatesDiamondImports() {
        let imports = [
            "A": "import \"Shared\";", "B": "import \"Shared\";",
            "Shared": "def identity<A:Type>(x:A)->A { x }",
        ]
        let result = RigorChecker.check("import \"A\"; import \"B\";", imports: imports)
        #expect(result.status == .valid)
        #expect(result.declarations == ["identity"])
        let cycle = RigorChecker.check("import \"A\";", imports: ["A": "import \"B\";", "B": "import \"A\";"])
        #expect(cycle.status == .invalid)
        #expect(cycle.diagnostic?.message.contains("döngüsü") == true)
    }

    @Test func rejectsOversizedSourcesAndDoesNotKeepPreviousGlobals() {
        #expect(RigorChecker.check(String(repeating: " ", count: RigorChecker.maximumSourceBytes + 1)).diagnostic?.phase == .input)
        #expect(RigorChecker.check("def identity<A:Type>(x:A)->A { x }").status == .valid)
        #expect(RigorChecker.check("theorem use<A:Type>(x:A)->A { identity<A>(x) }").status == .invalid)
    }

    @Test func cancelledChecksCannotProduceSuccess() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return RigorChecker.check("theorem identity<A:Type>(x:A)->A { x }")
        }
        #expect(await task.value.status == .cancelled)
    }
}
