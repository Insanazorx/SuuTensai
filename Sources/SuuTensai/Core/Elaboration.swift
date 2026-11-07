extension Kernel {
    /// Γ ⊢ e : T: kaynaktaki e ifadesinden hem core terimi hem türünü çıkar.
    /// Bütün identifier'lar burada çözülür; parser sadece adlarını saklar.
    func infer(_ expression: Expression, in context: LocalContext) throws -> CheckedExpression {
        try framed {
            activeSpan = expression.span
            switch expression.kind {
            case .identifier(let name):
                if let local = context.lookup(name) {
                    return CheckedExpression(term: local.value, type: local.type)
                }
                guard let global = globals[name] else { throw fail("Tanımsız isim '\(name)'.", at: expression.span) }
                dependencies.formUnion(global.axioms)
                return CheckedExpression(term: .global(name), type: global.type)
            case .universe(let universe):
                return CheckedExpression(term: .sort(universe), type: .sort(try successor(universe)))
            case .arrow(let domain, let codomain):
                let (a, aSort) = try elaborateType(domain, in: context)
                let (b, bSort) = try elaborateType(codomain, in: context)
                return CheckedExpression(term: .pi(parameter("_", a), b),
                                         type: .sort(piSort(aSort, bSort)))
            case .dependentFunction(let parameters, let result):
                let (binders, inner) = try bindParameters(parameters, in: context)
                let (body, _) = try elaborateType(result, in: inner)
                let term = pi(binders, body)
                // Birden fazla Pi'nin evreni içten dışa hesaplanır. Core
                // denetimi, parametrelerin bağımlılıklarını da aynı kuralla alır.
                return CheckedExpression(term: term, type: try inferCore(term, in: coreContext(context)))
            case .lambda(let parameters, let body):
                let (binders, inner) = try bindParameters(parameters, in: context)
                let result = try infer(body, in: inner)
                return CheckedExpression(term: lambda(binders, result.term), type: pi(binders, result.type))
            case .application(let callee, let arguments), .specialization(let callee, let arguments):
                var result = try infer(callee, in: context)
                for argument in arguments {
                    guard case .pi(let p, let body) = try whnf(result.type) else {
                        throw fail("Bu ifade fonksiyon değil; fazladan argüman verildi.", at: argument.span)
                    }
                    let value = try check(argument, against: p.type, in: context)
                    // Bağımlılık burada görünür: f : (x:A)->P(x) ise f(a):P(a).
                    result = try CheckedExpression(term: .app(result.term, value),
                                                   type: substitute(body, [p.id: value]))
                }
                // Sıfır parametreli bildirim core'da sabittir; f() yazımı f olur.
                return result
            case .block(let block): return try elaborateBlock(block, expected: nil, in: context)
            case .match(let match): return try elaborateMatch(match, expected: nil, in: context)
            case .hole:
                throw fail("Çözülmemiş '_' deliği bir ispat olarak kabul edilemez.", at: expression.span)
            case .number, .string, .unary, .binary:
                throw fail("Literal/operatör için henüz kernel anlamı yok; tanımlı fonksiyon ve constructor kullan.", at: expression.span)
            }
        }
    }

    /// Γ ⊢ e ⇐ T: T zaten biliniyorsa e'yi ona göre kontrol et.
    /// Özellikle motive yazılmayan match, beklenen sonuç türünü buradan alır.
    func check(_ expression: Expression, against expected: CoreTerm, in context: LocalContext) throws -> CoreTerm {
        try framed {
            activeSpan = expression.span
            switch expression.kind {
            case .lambda(let parameters, let body):
                let (binders, inner) = try bindParameters(parameters, in: context)
                var target = expected
                for binder in binders {
                    guard case .pi(let p, let result) = try whnf(target) else {
                        throw fail("Lambda için beklenen tür bir Pi/fonksiyon türü olmalı.", at: expression.span)
                    }
                    try demandSame(binder.type, p.type, at: expression.span)
                    target = try substitute(result, [p.id: binder.variable])
                }
                let value = try check(body, against: target, in: inner)
                return lambda(binders, value)
            case .block(let block): return try elaborateBlock(block, expected: expected, in: context).term
            case .match(let match): return try elaborateMatch(match, expected: expected, in: context).term
            default:
                let result = try infer(expression, in: context)
                try demandSame(result.type, expected, at: expression.span)
                return result.term
            }
        }
    }

    func elaborateType(_ expression: Expression, in context: LocalContext) throws -> (CoreTerm, Universe) {
        let result = try infer(expression, in: context)
        guard case .sort(let sort) = try whnf(result.type) else {
            throw fail("Bir tip bekleniyor; bu ifadenin türü bir evren değil.", at: expression.span)
        }
        return (result.term, sort)
    }

    /// Blok imperative bir program değil, yerel adlandırılmış bir ispat terimi.
    /// let'in değeri kapsama eklenir; sonraki kullanımlar onun core değerini alır
    /// (ζ indirgemesi). Yerel adların blok dışına sızması böylece engellenir.
    func elaborateBlock(_ block: Block, expected: CoreTerm?, in initial: LocalContext) throws -> CheckedExpression {
        try framed {
            var context = initial
            for (index, statement) in block.statements.enumerated() {
                activeSpan = statement.span
                switch statement.kind {
                case .binding(let name, let annotation, let value):
                    let checked: CheckedExpression
                    if let annotation {
                        let (type, _) = try elaborateType(annotation, in: context)
                        checked = try CheckedExpression(term: check(value, against: type, in: context), type: type)
                    } else { checked = try infer(value, in: context) }
                    if name != "_" {
                        context = context.adding(name: name, type: checked.type, value: checked.term)
                    }
                case .expression(let value):
                    // Sonuç kullanılmasa da hatalı bir ifade gözden kaçmaz.
                    _ = try infer(value, in: context)
                case .return(let value):
                    guard index == block.statements.count - 1, block.result == nil else {
                        throw fail("return sonrası ulaşılamayan ifade var.", at: statement.span)
                    }
                    return try elaborateResult(value, expected: expected, in: context)
                }
            }
            guard let result = block.result else { throw fail("Blok sonuç üretmiyor.", at: block.span) }
            return try elaborateResult(result, expected: expected, in: context)
        }
    }

    func elaborateResult(_ value: Expression, expected: CoreTerm?, in context: LocalContext) throws -> CheckedExpression {
        if let expected {
            return try CheckedExpression(term: check(value, against: expected, in: context), type: expected)
        }
        return try infer(value, in: context)
    }

    func successor(_ universe: Universe) throws -> Universe {
        switch universe {
        case .prop: return .type(level: 0)
        case .type(let level):
            guard level >= 0, level < Int.max else { throw fail("Evren seviyesi taşması.") }
            return .type(level: level + 1)
        }
    }

    /// Type evrenleri predicative: Pi'nin seviyesi max(domain, codomain).
    /// Prop ise impredicative: sonuç bir önerme ise Pi de önermedir.
    /// Type(0):Type(1); Type(0):Type(0) kesinlikle kabul edilmez.
    func piSort(_ domain: Universe, _ codomain: Universe) -> Universe {
        if codomain == .prop { return .prop }
        let a: Int = if case .type(let n) = domain { n } else { 0 }
        let b: Int = if case .type(let n) = codomain { n } else { 0 }
        return .type(level: max(a, b))
    }

    func coreContext(_ context: LocalContext) -> [Int: CoreTerm] {
        var result: [Int: CoreTerm] = [:]
        for binding in context.bindings {
            if case .variable(let id, _) = binding.value { result[id] = binding.type }
        }
        return result
    }

    /// Ürettiğimiz Pi/recursor imzalarını da doğrulamak için küçük core denetimi.
    /// CoreTerm'i dışarıdan okuyup güvenmek yerine AST yalnızca yukarıdaki
    /// kontrollü kurallardan bu temsile çevrilir.
    func inferCore(_ term: CoreTerm, in context: [Int: CoreTerm]) throws -> CoreTerm {
        try framed {
            switch term {
            case .variable(let id, _):
                guard let type = context[id] else { throw fail("Core içinde kapsam dışı değişken.") }
                return type
            case .global(let name):
                guard let entry = globals[name] else { throw fail("Tanımsız core sabiti '\(name)'.") }
                return entry.type
            case .sort(let sort): return .sort(try successor(sort))
            case .pi(let p, let body):
                guard case .sort(let domain) = try whnf(inferCore(p.type, in: context)) else {
                    throw fail("Pi domain'i bir tip değil.")
                }
                var inner = context
                inner[p.id] = p.type
                guard case .sort(let codomain) = try whnf(inferCore(body, in: inner)) else {
                    throw fail("Pi sonucu bir tip değil.")
                }
                return .sort(piSort(domain, codomain))
            case .lambda(let p, let body):
                guard case .sort = try whnf(inferCore(p.type, in: context)) else {
                    throw fail("Lambda domain'i bir tip değil.")
                }
                var inner = context
                inner[p.id] = p.type
                return try .pi(p, inferCore(body, in: inner))
            case .app(let function, let argument):
                guard case .pi(let p, let body) = try whnf(inferCore(function, in: context)) else {
                    throw fail("Core uygulamasının solu fonksiyon değil.")
                }
                let actual = try inferCore(argument, in: context)
                try demandSame(actual, p.type, at: activeSpan)
                return try substitute(body, [p.id: argument])
            case .match(let match):
                // Dallar elaborateMatch tarafından kontrol edilmiştir. Burada
                // sadece bu doğrulanmış core ifadesinin sonuç tipini okuyoruz.
                guard let family = families[match.family] else { throw fail("Bilinmeyen match ailesi.") }
                let (_, indices) = try familyArguments(inferCore(match.scrutinee, in: context), family: family)
                return match.motive.applied(to: indices + [match.scrutinee])
            }
        }
    }
}
