import Foundation
import Testing
@testable import SuuTensai

private let naturals = """
inductive Nat: Type { zero: Nat; succ: Nat -> Nat; }
"""

private func checkedKernel(_ source: String) throws -> Kernel {
    let kernel = Kernel()
    try kernel.check(Parser(source: source).parse())
    return kernel
}

private func core(_ source: String, in kernel: Kernel) throws -> CoreTerm {
    try kernel.infer(Parser(source: source).parseExpression()).term
}

@Suite struct KernelTests {
    @Test func dependentFunctionsLetsAndDefinitionalEquality() throws {
        let kernel = try checkedKernel("""
        def identity<A:Type>(x:A)->A { x }
        theorem apply<A:Type,B:Type>(a:A,f:A->B)->B { let result:B=f(identity<A>(a)); return result }
        theorem dependent<A:Type,P:A->Type>(x:A,p:P(x))->P(identity<A>(x)) { p }
        theorem alpha<A:Type>(f:(x:A)->A)->(y:A)->A { f }
        """)
        #expect(kernel.globals.count == 4)
        #expect(kernel.globals["apply"]?.axioms.isEmpty == true)
    }

    @Test func betaReductionDoesNotCaptureShadowedVariables() throws {
        let kernel = try checkedKernel(naturals + """
        def const<A:Type>(x:A)->A->A { func(y:A)=>x }
        def capture(y:Nat)->Nat { (func(x:Nat)=>func(y:Nat)=>x)(y)(zero) }
        theorem result()->Nat { const<Nat>(succ(zero))(zero) }
        """)
        #expect(try kernel.same(core("capture(succ(zero))", in: kernel), core("succ(zero)", in: kernel)))
        let outer = kernel.parameter("y", .global("Nat"))
        let inner = kernel.parameter("y", .global("Nat"))
        let source = CoreTerm.lambda(inner, outer.variable)
        let replaced = try kernel.substitute(source, [outer.id: inner.variable])
        guard case .lambda(let fresh, let value) = replaced else { Issue.record("Expected lambda"); return }
        #expect(fresh.id != inner.id)
        #expect(value == inner.variable) // inserted y remains free
    }

    @Test func eitherEliminationCoverageAndIotaReduction() throws {
        let kernel = try checkedKernel(naturals + """
        inductive Either<A:Type,B:Type>:Type { left:A->Either<A,B>; right:B->Either<A,B>; }
        def pick(e:Either<Nat,Nat>)->Nat { match e { left(x)=>x; right(y)=>succ(y); } }
        theorem swap<A:Type,B:Type>(e:Either<A,B>)->Either<B,A> {
            match e { left(x)=>right<B,A>(x); right(y)=>left<B,A>(y); }
        }
        """)
        #expect(try kernel.same(core("pick(right<Nat,Nat>(zero))", in: kernel), core("succ(zero)", in: kernel)))
        #expect(try kernel.same(core("pick(left<Nat,Nat>(zero))", in: kernel), core("zero", in: kernel)))
    }

    @Test func dependentMotiveCanReturnDifferentTypes() throws {
        let kernel = try checkedKernel(naturals + """
        inductive Bool:Type { yes:Bool; no:Bool; }
        def Result(b:Bool)->Type { match b { yes=>Nat; no=>Bool; } }
        def make(b:Bool)->Result(b) {
            match b return func(tag:Bool)=>Result(tag) { yes=>zero; no=>yes; }
        }
        """)
        #expect(try kernel.same(core("make(yes)", in: kernel), core("zero", in: kernel)))
        #expect(try kernel.same(core("make(no)", in: kernel), core("yes", in: kernel)))
    }

    @Test func dependentConstructorFieldsAndCatchAll() throws {
        let kernel = try checkedKernel(naturals + """
        inductive Sigma<A:Type,B:A->Type>:Type { pack:(x:A,p:B(x))->Sigma<A,B>; }
        def first<A:Type,B:A->Type>(s:Sigma<A,B>)->A { match s { pack(x,p)=>x; } }
        def echo(n:Nat)->Nat { match n { zero=>zero; other=>other; } }
        def constant(n:Nat)->Nat { match n { _=>zero; } }
        """)
        #expect(try kernel.same(core("echo(succ(zero))", in: kernel), core("succ(zero)", in: kernel)))
        #expect(try kernel.same(core("constant(succ(zero))", in: kernel), core("zero", in: kernel)))
    }

    @Test func emptyEliminationAndPropRestriction() throws {
        _ = try checkedKernel("""
        inductive Empty:Type {}
        theorem absurd<A:Type>(e:Empty)->A { match e {} }
        inductive False:Prop {}
        theorem logical<P:Prop>(e:False)->P { match e {} }
        """)
        #expect(throws: KernelError.self) {
            try checkedKernel("inductive False:Prop {} theorem bad<A:Type>(e:False)->A { match e {} }")
        }
    }

    @Test func fundamentalsAndInductionProofsWorkWithoutSpecialNames() throws {
        let kernel = Kernel()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let report = try RigorLoader(kernel: kernel).checkFile(root.appendingPathComponent("Examples/kernel.rigor"))
        #expect(report.axioms.isEmpty)
        #expect(kernel.globals["J"] != nil)
        #expect(kernel.globals["addZeroRight"] != nil)
        #expect(try kernel.same(core("add(succ(zero),succ(zero))", in: kernel), core("succ(succ(zero))", in: kernel)))
        #expect(try kernel.same(core("transport<Nat>(func(n:Nat)=>Nat,zero,zero,refl<Nat>(zero),succ(zero))", in: kernel),
                                core("succ(zero)", in: kernel)))
        // Aynı mekanizma, farklı isimli equality ailesinde de çalışmalı.
        try kernel.check(Parser(source: """
        inductive Path<A:Type>(x:A,y:A):Type { sameAt:(a:A)->Path<A>(a,a); }
        theorem reverse<A:Type>(x:A,y:A,p:Path<A>(x,y))->Path<A>(y,x) {
            PathInd<A>(func(a:A,b:A,q:Path<A>(a,b))=>Path<A>(b,a),func(a:A)=>sameAt<A>(a),x,y,p)
        }
        """).parse())
    }

    @Test func axiomsAreTrackedTransitively() throws {
        let kernel = Kernel()
        let report = try kernel.check(Parser(source: """
        axiom A()->Type;
        axiom assumed()->A;
        theorem first()->A { assumed }
        theorem second()->A { first() }
        """).parse())
        #expect(report.axioms == ["A", "assumed"])
        #expect(kernel.globals["second"]?.axioms == Set(["A", "assumed"]))
    }

    @Test func indexedRecursiveFamilyProducesSpecializedHypotheses() throws {
        let kernel = try checkedKernel(naturals + """
        inductive Vec<A:Type>(n:Nat):Type {
            empty:Vec<A>(zero);
            push:(n:Nat,head:A,tail:Vec<A>(n))->Vec<A>(succ(n));
        }
        def length<A:Type>(n:Nat,xs:Vec<A>(n))->Nat {
            VecInd<A>(
                func(k:Nat,vs:Vec<A>(k))=>Nat,
                zero,
                func(k:Nat,h:A,t:Vec<A>(k),ih:Nat)=>succ(ih),
                n,xs
            )
        }
        """)
        #expect(try kernel.same(core("length<Nat>(succ(zero),push<Nat>(zero,zero,empty<Nat>))", in: kernel),
                                core("succ(zero)", in: kernel)))
    }

    @Test func inductionComputesAnIHForEveryRecursiveField() throws {
        let kernel = try checkedKernel(naturals + """
        inductive Tree:Type { leaf:Tree; node:Tree->Tree->Tree; }
        def add(n:Nat,m:Nat)->Nat { NatInd(func(k:Nat)=>Nat,m,func(k:Nat,ih:Nat)=>succ(ih),n) }
        def size(t:Tree)->Nat {
            TreeInd(func(t:Tree)=>Nat,succ(zero),func(l:Tree,il:Nat,r:Tree,ir:Nat)=>add(il,ir),t)
        }
        """)
        #expect(try kernel.same(core("size(node(leaf,leaf))", in: kernel), core("succ(succ(zero))", in: kernel)))
    }

    @Test func positivityChecksDefinitionsAndUniformParameters() throws {
        for source in [
            naturals + "def Negative<A:Type>()->Type {A->Nat} inductive Bad:Type {c:Negative<Bad>()->Bad;}",
            "inductive List<A:Type>:Type {nil:List<A>;} inductive Bad:Type {c:List<Bad>->Bad;}",
            "inductive Bad<A:Type,B:Type>:Type {c:A->Bad<B,A>;}",
            naturals + "inductive Bad:Type {c:(Nat->Bad)->Bad;}"
        ] {
            #expect(throws: KernelError.self) { try checkedKernel(source) }
        }
    }

    @Test func indexedEliminationCannotInventAnEquality() throws {
        // Açık motive varken de kural bütün indeksler için kontrol edilmeli.
        // refl dalını geçirip farklı x,y için refl kanıtı üretmek mümkün değil.
        #expect(throws: KernelError.self) {
            try checkedKernel("""
            inductive Id<A:Type>(x:A,y:A):Type {refl:(v:A)->Id<A>(v,v);}
            theorem fake<A:Type>(x:A,y:A)->Id<A>(x,y) {refl<A>(x)}
            """)
        }
        #expect(throws: KernelError.self) {
            try checkedKernel("""
            inductive Id<A:Type>(x:A,y:A):Type {refl:(v:A)->Id<A>(v,v);}
            theorem fake<A:Type,B:Type>(x:A,y:A,p:Id<A>(x,y))->B {
                match p return func(a:A,b:A,q:Id<A>(a,b))=>B {refl(v)=>v;}
            }
            """)
        }
    }

    @Test func manyIndependentTheoremsAndBoundedComputation() throws {
        let declarations = (0..<500).map { "theorem identity\($0)<A:Type>(x:A)->A {let y=x; return y}" }.joined(separator: "\n")
        let kernel = try checkedKernel(declarations)
        #expect(kernel.globals.count == 500)
        // Budget testi sonsuz recursion gerektirmez: sonlanan fakat pahalı
        // bir beta hesabının da kontrollü olarak durdurulabildiğini ölçer.
        let source = naturals + "def twice<A:Type>(f:A->A,x:A)->A {f(f(x))}"
        let normal = try checkedKernel(source)
        var function = "succ"
        for _ in 0..<6 { function = "func(x:Nat)=>twice<Nat>(\(function),x)" }
        let expression = try Parser(source: "(\(function))(zero)").parseExpression()
        _ = try normal.infer(expression) // Girdi gerçekten iyi türlenmiş.
        let limited = Kernel(limits: KernelLimits(maxSteps: 500, maxDepth: 64, maxBinders: 32))
        try limited.check(Parser(source: source).parse())
        #expect(throws: KernelError.self) {
            let term = try limited.infer(expression).term
            limited.resetBudget()
            _ = try limited.normalForm(term)
        }
    }

    @Test func failedProgramsDoNotLeaveTrustedDeclarationsBehind() throws {
        let kernel = try checkedKernel(naturals)
        #expect(throws: KernelError.self) {
            try kernel.check(Parser(source: "def good()->Nat {zero} theorem bad()->Nat {Type}").parse())
        }
        #expect(kernel.globals["good"] == nil)
        #expect(kernel.globals["Nat"] != nil)
        #expect(throws: KernelError.self) {
            try kernel.check(Parser(source: "inductive Bad:Type { okay:Bad; broken:Type->Bad; }").parse())
        }
        #expect(kernel.globals["Bad"] == nil)
        #expect(kernel.families["Bad"] == nil)
    }

    @Test(arguments: [
        "theorem wrong<A:Type,B:Type>(a:A)->B { a }",
        "theorem hole<A:Type>()->A { _ }",
        "theorem missing<A:Type>()->A { unknown }",
        "def recursive<A:Type>()->A { recursive<A>() }",
        "def small()->Type { Type }",
        "def big()->Type(2) { Type }",
        "def overflow()->Type(\(Int.max)) { Type(\(Int.max)) }",
        "def noResult<A:Type>(a:A)->A { a; }",
        "def unreachable<A:Type>(a:A)->A { return a; a }",
        "def badAnnotation<A:Type,B:Type>(a:A)->A { let x:B=a; x }",
        "def duplicate<A:Type>(x:A,x:A)->A {x}",
        "axiom A()->Type; axiom A()->Type;",
        "def operator<A:Type>(x:A)->A { x+x }",
        "def number()->Type {123}",
        "def string()->Type {\"x\"}",
        "Gamma C { A:Type; x:A } theorem leak()->A {x}",
        "def scope<A:Type>(x:A)->A {x} theorem leak()->Type {x}",
        "inductive Bad:Type { negative: (Bad->Bad)->Bad; }",
        "inductive Bad:Type { large:Type->Bad; }",
        "inductive Bad:Type { wrong:Type; }",
        "inductive Bad:Type { c:Bad; c:Bad; }",
        "inductive Bad<A:Type>:Type { c:Bad<Type>; }",
        "inductive Bad:Type { BadInd:Bad; }",
        "import \"missing.rigor\";"
    ])
    func invalidProofsAreRejected(_ source: String) throws {
        #expect(throws: KernelError.self) { try checkedKernel(source) }
    }

    @Test(arguments: [
        "def bad(n:Nat)->Nat { match n { zero=>zero; } }",
        "def bad(n:Nat)->Nat { match n { zero=>zero; zero=>zero; succ(k)=>k; } }",
        "def bad(n:Nat)->Nat { match n { zero(x)=>x; succ(k)=>k; } }",
        "def bad(n:Nat)->Nat { match n { zero=>zero; succ()=>zero; } }",
        "def bad(n:Nat)->Nat { match n { _=>zero; succ(k)=>k; } }",
        "def bad(n:Nat)->Nat { match n { zero=>Type; succ(k)=>k; } }",
        "def bad(n:Nat)->Nat { match n return func(x:Type)=>Nat { _=>zero; } }",
        "def bad(n:Nat)->Nat { match n return func(x:Nat)=>zero { _=>zero; } }",
        "def bad(n:Nat)->Nat { let result=match n {_=>zero;}; result }",
        "def bad(n:Nat)->Nat { match n { succ(succ(k))=>k; zero=>zero; } }",
        "def good(n:Nat)->Nat { match n { zero=>zero; succ(k)=>k; } } def bad()->Nat {k}"
    ])
    func invalidMatchesAreRejected(_ source: String) throws {
        #expect(throws: KernelError.self) { try checkedKernel(naturals + source) }
    }

    @Test func limitsFailWithDiagnostics() throws {
        let kernel = Kernel(limits: KernelLimits(maxSteps: 5, maxDepth: 8, maxBinders: 4))
        #expect(throws: KernelError.self) { try kernel.check(Parser(source: naturals).parse()) }
        let tooWide = (0..<40).map { "x\($0):Type" }.joined(separator: ",")
        #expect(throws: KernelError.self) { try checkedKernel("def wide(\(tooWide))->Type { x0 }") }
    }
}
