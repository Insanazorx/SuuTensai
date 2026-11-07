/// Okuma sırası: Kernel -> Elaboration -> Reduction -> Inductives.
///
/// AST kaynak yazımını korur. CoreTerm ise isimleri çözülmüş, her bağlayıcısı
/// benzersiz kimliğe sahip küçük bir lambda hesabıdır. Kernel kaynak ağacını
/// doğrudan değiştirerek çalışmaz; önce doğrulanmış bir core terim oluşturur.
/// Böylece parser'ın kabul etmesi ile ispatın doğrulanması ayrı kalır.
final class Kernel: TypeChecker {
    private(set) var globals: [String: GlobalEntry] = [:]
    private(set) var families: [String: InductiveInfo] = [:]
    private(set) var contexts: [String: LocalContext] = [:]
    let limits: KernelLimits

    // Sayaç kernel'in ömrü boyunca artar. Aynı yazılan iki `x` farklı kapsamda
    // bulunabilir; kimliklerinin aynı olmasına hiçbir zaman güvenmeyiz.
    private var nextID = 0
    private var steps = 0
    private var depth = 0
    var activeSpan = SourceSpan.zero
    var dependencies: Set<String> = []

    init(limits: KernelLimits = KernelLimits()) { self.limits = limits }

    /// Bir dosya atomik olarak kontrol edilir. Son bildirim hatalıysa, önceki
    /// bildirimlerin bu çağrıda eklenen kısmı da ortamda bırakılmaz.
    @discardableResult
    func check(_ program: Program) throws -> KernelReport {
        let oldGlobals = globals
        let oldFamilies = families
        let oldContexts = contexts
        resetBudget()
        var names: [String] = []
        var assumptions: Set<String> = []
        do {
            for declaration in program.declarations {
                dependencies = []
                activeSpan = declaration.span
                let name = try checkDeclaration(declaration)
                names.append(name)
                assumptions.formUnion(dependencies)
            }
            return KernelReport(declarations: names, axioms: assumptions.sorted())
        } catch {
            globals = oldGlobals
            families = oldFamilies
            contexts = oldContexts
            throw error
        }
    }

    /// REPL/test için tek bir ifadeyi de mevcut doğrulanmış ortamda sorabiliriz.
    func infer(_ expression: Expression) throws -> CheckedExpression {
        resetBudget()
        return try infer(expression, in: LocalContext())
    }

    func resetBudget() { steps = 0; depth = 0 }

    /// Loader'ın birden çok dosyayı tek işlem olarak kontrol etmesi için.
    /// Bir import başarısızsa yüklenen diğer dosyalar da geri alınır.
    func transaction<T>(_ operation: () throws -> T) throws -> T {
        let oldGlobals = globals
        let oldFamilies = families
        let oldContexts = contexts
        do { return try operation() }
        catch {
            globals = oldGlobals
            families = oldFamilies
            contexts = oldContexts
            throw error
        }
    }

    func freshID() -> Int {
        let result = nextID
        nextID += 1
        return result
    }

    func parameter(_ name: String, _ type: CoreTerm) -> CoreParameter {
        CoreParameter(id: freshID(), name: name, type: type)
    }

    func fail(_ message: String, at span: SourceSpan? = nil) -> KernelError {
        KernelError(message: message, span: span ?? activeSpan)
    }

    // Geçersiz/gereğinden büyük girdiler stack overflow veya sonsuz işlem
    // oluşturmamalı. Bütçenin bitmesi bir ispatı kabul ettirmez: hata döndürür.
    func step() throws {
        steps += 1
        if steps == 1 || steps.isMultiple(of: 256) {
            try Task.checkCancellation()
        }
        if steps > limits.maxSteps { throw fail("Kernel işlem bütçesi aşıldı.") }
    }

    func framed<T>(_ body: () throws -> T) throws -> T {
        try step()
        guard depth < limits.maxDepth else { throw fail("Kernel derinlik sınırı aşıldı.") }
        depth += 1
        defer { depth -= 1 }
        return try body()
    }

    func requireFresh(_ name: String, at span: SourceSpan) throws {
        guard globals[name] == nil, contexts[name] == nil else {
            throw fail("'\(name)' zaten tanımlı.", at: span)
        }
        guard name != "_" else { throw fail("Global bildirim adı '_' olamaz.", at: span) }
    }

    func install(_ name: String, type: CoreTerm, value: CoreTerm?, kind: GlobalKind) {
        globals[name] = GlobalEntry(type: type, value: value, kind: kind, axioms: dependencies)
    }

    func registerFamily(_ family: InductiveInfo) { families[family.name] = family }

    func checkDeclaration(_ declaration: Declaration) throws -> String {
        switch declaration {
        case .theorem(let function): return try checkFunction(function, kind: .theorem)
        case .definition(let function): return try checkFunction(function, kind: .definition)
        case .axiom(let signature):
            try requireFresh(signature.name, at: signature.span)
            let (parameters, result, _) = try elaborateSignature(signature)
            dependencies.insert(signature.name)
            install(signature.name, type: pi(parameters, result), value: nil, kind: .axiom)
            return signature.name
        case .inductive(let declaration):
            try checkInductive(declaration)
            return declaration.name
        case .context(let declaration):
            try requireFresh(declaration.name, at: declaration.span)
            let (_, context) = try bindParameters(declaration.bindings, in: LocalContext())
            // Gamma bir varsayımlar listesidir; bunları sessizce global aksiyom
            // yapmıyoruz. Theorem'ler kendi açık parametrelerini kullanır.
            contexts[declaration.name] = context
            return declaration.name
        case .import:
            throw fail("Import önce RigorLoader ile yüklenmeli; Kernel.check yalnızca bağımsız AST kontrol eder.")
        }
    }

    func checkFunction(_ declaration: FunctionDeclaration, kind: GlobalKind) throws -> String {
        let signature = declaration.signature
        try requireFresh(signature.name, at: signature.span)
        let (parameters, result, context) = try elaborateSignature(signature)
        let body = try elaborateBlock(declaration.body, expected: result, in: context)
        // Adı ancak gövde başarıyla doğrulandıktan sonra ekleriz. Dolayısıyla
        // `def loop() -> A { loop() }` ve ileri referanslar kabul edilmez.
        // Sonlanan recursive hesaplar, otomatik üretilen Ind recursor'u kullanır.
        install(signature.name, type: pi(parameters, result),
                value: lambda(parameters, body.term), kind: kind)
        return signature.name
    }

    func elaborateSignature(_ signature: Signature) throws -> ([CoreParameter], CoreTerm, LocalContext) {
        let (parameters, context) = try bindParameters(
            signature.genericParameters + signature.parameters, in: LocalContext())
        let (result, _) = try elaborateType(signature.returnType, in: context)
        return (parameters, result, context)
    }

    func bindParameters(_ parameters: [Parameter], in initial: LocalContext) throws -> ([CoreParameter], LocalContext) {
        guard parameters.count <= limits.maxBinders else { throw fail("Bir bağlayıcı listesi çok uzun.") }
        var names: Set<String> = []
        var context = initial
        var result: [CoreParameter] = []
        for source in parameters {
            // Aynı listedeki x,x muhtemelen yazım hatasıdır. İçteki başka bir
            // lambda'nın x kullanması ise geçerli shadowing'dir.
            if source.name != "_", !names.insert(source.name).inserted {
                throw fail("Tekrarlanan parametre '\(source.name)'.", at: source.span)
            }
            let (type, _) = try elaborateType(source.type, in: context)
            let binder = parameter(source.name, type)
            result.append(binder)
            context = context.adding(binder)
        }
        return (result, context)
    }

    // Çok argümanlı kaynak yazımı core'da tek argümanlı iç içe Pi/lambda olur.
    // f<A>(x) ve f(A,x) aynı uygulama zincirine indirgenir; implicit argüman yok.
    func pi(_ parameters: [CoreParameter], _ result: CoreTerm) -> CoreTerm {
        parameters.reversed().reduce(result) { .pi($1, $0) }
    }

    func lambda(_ parameters: [CoreParameter], _ body: CoreTerm) -> CoreTerm {
        parameters.reversed().reduce(body) { .lambda($1, $0) }
    }
}
