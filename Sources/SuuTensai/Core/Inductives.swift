extension Kernel {
    /// İndüktif bildirim, isimleri ortama koymaktan daha güçlü bir işlemdir:
    /// yeni bir tip, constructor'lar ve hesaplama yapan bir induction ilkesi
    /// ekler. Hatalı bir bildirim mantığı tutarsızlaştırabilir; bu yüzden bu
    /// ilk sürüm sadece doğrudan recursive alanları kabul eder.
    func checkInductive(_ declaration: InductiveDeclaration) throws {
        try requireFresh(declaration.name, at: declaration.span)
        try requireFresh(declaration.name + "Ind", at: declaration.span)
        guard declaration.constructors.count <= limits.maxBinders else {
            throw fail("Bu kernel sürümünde constructor sayısı sınırı aşıldı.")
        }
        let allNames = (declaration.parameters + declaration.indices).map(\.name).filter { $0 != "_" }
        guard Set(allNames).count == allNames.count else { throw fail("Parametre/indeks adları tekrarlanıyor.") }
        let (parameters, parameterContext) = try bindParameters(declaration.parameters, in: LocalContext())
        let (indices, fullContext) = try bindParameters(declaration.indices, in: parameterContext)
        let sortExpression = try infer(declaration.sort, in: fullContext)
        guard case .sort(let sort) = try whnf(sortExpression.term) else {
            throw fail("İndüktif bildirimin sort'u Type(n) veya Prop olmalı.", at: declaration.sort.span)
        }

        // Ailenin kendisi constructor tipleri içinde kullanılabilsin. Bu kayıt
        // geçicidir; Kernel.check hatada tüm dosyayı geri alır.
        install(declaration.name, type: pi(parameters + indices, .sort(sort)), value: nil, kind: .family)
        var constructorNames: Set<String> = [declaration.name, declaration.name + "Ind"]
        var constructors: [ConstructorInfo] = []
        var constructorTypes: [CoreTerm] = []
        let provisional = InductiveInfo(name: declaration.name, parameters: parameters,
                                       indices: indices, sort: sort, constructors: [])
        let coreParameters = Dictionary(uniqueKeysWithValues: parameters.map { ($0.id, $0.type) })

        for source in declaration.constructors {
            activeSpan = source.span
            try requireFresh(source.name, at: source.span)
            guard constructorNames.insert(source.name).inserted else { throw fail("Tekrarlanan constructor adı.") }
            // Değişen indeksler burada otomatik bağlanmaz. Constructor hangi
            // indeksle sonuç vereceğini kendi tipinde açıkça belirtir.
            let (type, _) = try elaborateType(source.type, in: parameterContext)
            let (fields, result) = try telescope(type)
            let (uniform, resultIndices) = try familyArguments(result, family: provisional)
            for (actual, expected) in zip(uniform, parameters) {
                try demandSame(actual, expected.variable, at: source.span)
            }

            var context = coreParameters
            var recursive: Set<Int> = []
            for (position, field) in fields.enumerated() {
                guard case .sort(let fieldSort) = try whnf(inferCore(field.type, in: context)) else {
                    throw fail("Constructor alanının türü geçersiz.")
                }
                // Örn. Bad:Type { make:Type->Bad } kabul edilmez: Type'ın
                // kendisi Type(1)'dedir. Generic A:Type bir ALAN değildir;
                // parametre olarak geçtiği için Either<A,B>:Type geçerlidir.
                if case .type(let targetLevel) = sort,
                   case .type(let fieldLevel) = fieldSort, fieldLevel > targetLevel {
                    throw fail("Constructor alanı ailenin evreninden daha büyük.", at: source.span)
                }
                let normalized = try normalForm(field.type)
                if try containsFamily(normalized, name: declaration.name) {
                    // Güvenli alt küme: sadece `tail: List<A>` gibi doğrudan
                    // alan. `(Bad->A)->Bad` negatif; `List<Bad>` nested;
                    // `A->Bad` pozitif olsa da bu sürümde henüz desteklenmiyor.
                    let (head, _) = normalized.spine
                    guard case .global(let recursiveName) = head, recursiveName == declaration.name else {
                        throw fail("Positivity kuralı: recursive alan doğrudan '\(declaration.name)' olmalı; negatif/nested/fonksiyonel recursion desteklenmiyor.", at: source.span)
                    }
                    let (args, recIndices) = try familyArguments(normalized, family: provisional)
                    for (arg, param) in zip(args, parameters) {
                        try demandSame(arg, param.variable, at: source.span)
                    }
                    for index in recIndices {
                        guard try !containsFamily(index, name: declaration.name) else {
                            throw fail("Recursive alanın indeksinde aile tekrar kullanılamaz.")
                        }
                    }
                    recursive.insert(position)
                }
                context[field.id] = field.type
            }
            for index in resultIndices {
                guard try !containsFamily(normalForm(index), name: declaration.name) else {
                    throw fail("Constructor sonuç indeksinde recursive aile kullanımı desteklenmiyor.")
                }
            }
            constructors.append(ConstructorInfo(name: source.name, fields: fields,
                                                resultIndices: resultIndices, recursiveFields: recursive))
            constructorTypes.append(pi(parameters, type))
        }

        let family = InductiveInfo(name: declaration.name, parameters: parameters,
                                   indices: indices, sort: sort, constructors: constructors)
        registerFamily(family)
        // Constructor tiplerinin kullandığı aksiyomları ailede de sakla;
        // sonradan match kullanan theorem bu bağımlılıkları kaybetmemeli.
        install(declaration.name, type: pi(parameters + indices, .sort(sort)), value: nil, kind: .family)
        for (constructor, type) in zip(constructors, constructorTypes) {
            install(constructor.name, type: type, value: nil, kind: .constructor)
        }
        let recursorType = try makeRecursorType(family)
        // Üretilmiş imzaya da güvenmeyip tip olup olmadığını denetliyoruz.
        guard case .sort = try whnf(inferCore(recursorType, in: [:])) else {
            throw fail("Üretilen recursor imzası bir tip değil.")
        }
        install(family.recursorName, type: recursorType, value: nil, kind: .recursor(family.name))
    }

    func telescope(_ input: CoreTerm) throws -> ([CoreParameter], CoreTerm) {
        var result: [CoreParameter] = []
        var remaining = input
        while case .pi(let p, let body) = try whnf(remaining) {
            guard result.count < limits.maxBinders else { throw fail("Core bağlayıcı listesi çok uzun.") }
            result.append(p)
            remaining = body
        }
        return (result, try whnf(remaining))
    }

    func containsFamily(_ term: CoreTerm, name: String) throws -> Bool {
        try framed {
            switch term {
            case .global(let candidate): return candidate == name
            case .variable, .sort: return false
            case .app(let a, let b): return try containsFamily(a, name: name) || containsFamily(b, name: name)
            case .pi(let p, let body), .lambda(let p, let body):
                return try containsFamily(p.type, name: name) || containsFamily(body, name: name)
            case .match(let match):
                if try containsFamily(match.scrutinee, name: name) || containsFamily(match.motive, name: name) { return true }
                for branch in match.branches {
                    for field in branch.fields where try containsFamily(field.type, name: name) { return true }
                    if try containsFamily(branch.body, name: name) { return true }
                }
                return false
            }
        }
    }

    /// Bir template teleskobunu taze kimliklerle örnekle. Önceki alanlar sonraki
    /// alanların tipinde geçebilir: Sigma'da proof:B(value) buna bir örnektir.
    func instantiate(_ fields: [CoreParameter], replacing initial: [Int: CoreTerm]) throws -> ([CoreParameter], [Int: CoreTerm]) {
        var substitution = initial
        var result: [CoreParameter] = []
        for field in fields {
            let new = try parameter(field.name, substitute(field.type, substitution))
            substitution[field.id] = new.variable
            result.append(new)
        }
        return (result, substitution)
    }

    /// Genel recursor'un düzeni:
    /// IInd(params..., motive, methodCtor1, ..., indices..., target)
    /// Her recursive alanın hemen arkasından o alanın induction hypothesis'i
    /// gelir. Nat step'i (k:Nat, ih:P(k))->P(succ(k)) bu kuraldan üretilir.
    func makeRecursorType(_ family: InductiveInfo) throws -> CoreTerm {
        let parameterValues = family.parameters.map(\.variable)
        let targetType = CoreTerm.global(family.name).applied(to: parameterValues + family.indices.map(\.variable))
        let target = parameter("target", targetType)
        // Kaynak dilinde evren parametresi henüz yok: Type ailesinin Ind'i
        // Type(0)'a, Prop ailesinin Ind'i Prop'a elimine eder. Açık match daha
        // yüksek Type evrenlerine de gidebilir; Prop->Type ise yasaktır.
        let output: Universe = family.sort == .prop ? .prop : .type(level: 0)
        let motive = parameter("motive", pi(family.indices + [target], .sort(output)))
        var methods: [CoreParameter] = []
        for constructor in family.constructors {
            let initial = Dictionary(uniqueKeysWithValues: zip(family.parameters, parameterValues).map { ($0.id, $1) })
            let (fields, substitution) = try instantiate(constructor.fields, replacing: initial)
            var methodParameters: [CoreParameter] = []
            for (position, field) in fields.enumerated() {
                methodParameters.append(field)
                if constructor.recursiveFields.contains(position) {
                    let (_, indices) = try familyArguments(field.type, family: family)
                    let hypothesis = motive.variable.applied(to: indices + [field.variable])
                    methodParameters.append(parameter("ih_\(position)", hypothesis))
                }
            }
            let indices = try constructor.resultIndices.map { try substitute($0, substitution) }
            let constructed = CoreTerm.global(constructor.name).applied(to: parameterValues + fields.map(\.variable))
            let result = motive.variable.applied(to: indices + [constructed])
            guard methodParameters.count <= limits.maxBinders else { throw fail("Induction metodu çok uzun.") }
            methods.append(parameter("case_" + constructor.name, pi(methodParameters, result)))
        }
        let result = motive.variable.applied(to: family.indices.map(\.variable) + [target.variable])
        let binders = family.parameters + [motive] + methods + family.indices + [target]
        guard binders.count <= limits.maxBinders else { throw fail("Recursor imzası çok uzun.") }
        return pi(binders, result)
    }
}
