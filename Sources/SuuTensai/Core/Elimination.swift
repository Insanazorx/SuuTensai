extension Kernel {
    /// Match'in kritik kuralı: her dal aynı kaynak yazılı türü değil, motive'in
    /// O CONSTRUCTOR'a uygulanmış halini üretir. Örneğin motive P(n) ise
    /// zero dalında P(zero), succ(k) dalında P(succ(k)) beklenir.
    func elaborateMatch(_ match: MatchExpression, expected: CoreTerm?, in context: LocalContext) throws -> CheckedExpression {
        try framed {
            activeSpan = match.span
            let scrutinee = try infer(match.scrutinee, in: context)
            let (head, _) = try whnf(scrutinee.type).spine
            guard case .global(let name) = head, let family = families[name] else {
                throw fail("match hedefinin türü doğrulanmış bir indüktif aile olmalı.", at: match.scrutinee.span)
            }
            let (parameters, actualIndices) = try familyArguments(scrutinee.type, family: family)
            let parameterMap = Dictionary(uniqueKeysWithValues:
                zip(family.parameters, parameters).map { ($0.id, $1) })

            // Motive, mevcut tek bir indeks için değil, bütün indeksler için
            // tanımlanır. Id örneği: (x:A,y:A,p:Id<A>(x,y))->Type.
            let (genericIndices, _) = try instantiate(family.indices, replacing: parameterMap)
            let target = parameter("value", CoreTerm.global(name)
                .applied(to: parameters + genericIndices.map(\.variable)))
            let motiveParameters = genericIndices + [target]
            let motive: CoreTerm
            let outputSort: Universe
            if let source = match.motive {
                let inferred = try infer(source, in: context)
                var type = inferred.type
                for p in motiveParameters {
                    guard case .pi(let q, let result) = try whnf(type) else {
                        throw fail("Motive, indeksleri ve en son match hedefini parametre almalı.", at: source.span)
                    }
                    try demandSame(q.type, p.type, at: source.span)
                    type = try substitute(result, [q.id: p.variable])
                }
                guard case .sort(let sort) = try whnf(type) else {
                    throw fail("Motive'in sonucu bir tip olmalı.", at: source.span)
                }
                motive = inferred.term
                outputSort = sort
            } else if let expected {
                // Basit eliminasyonda sabit motive yeterlidir. Beklenen tür
                // dış bağlamı kullanabilir, fakat constructor eşitliği varsayarak
                // o bağlamı değiştirmeyiz. Gerekirse kullanıcı açık motive yazar.
                motive = lambda(motiveParameters, expected)
                guard case .sort(let sort) = try whnf(inferCore(expected, in: coreContext(context))) else {
                    throw fail("match için beklenen sonuç bir tip değil.")
                }
                outputSort = sort
            } else {
                throw fail("match'in türünü çıkarmak için açık motive veya sonuç türü anotasyonu gerekli.", at: match.span)
            }
            // Prop'tan veri üretmeye genel izin verilmez. Bu sürüm Empty/tek
            // constructor için bile istisna getirmez; daha dar ama güvenli kural.
            if family.sort == .prop, outputSort != .prop {
                throw fail("Prop ailesinden Type'a eliminasyon bu kernel sürümünde desteklenmiyor.", at: match.span)
            }
            let resultType = motive.applied(to: actualIndices + [scrutinee.term])
            if let expected { try demandSame(resultType, expected, at: match.span) }

            var covered: Set<String> = []
            var branches: [CoreBranch] = []
            for (position, branch) in match.cases.enumerated() {
                let selection = try selectConstructor(branch.pattern, family: family)
                let selected: [ConstructorInfo]
                if let name = selection.name {
                    guard let constructor = family.constructors.first(where: { $0.name == name }) else {
                        throw fail("'\(name)' bu ailenin constructor'ı değil.", at: branch.pattern.span)
                    }
                    selected = [constructor]
                } else {
                    guard position == match.cases.count - 1 else {
                        throw fail("Catch-all pattern son dal olmalı.", at: branch.pattern.span)
                    }
                    selected = family.constructors.filter { !covered.contains($0.name) }
                    guard !selected.isEmpty else { throw fail("Bu match dalı ulaşılamaz.", at: branch.span) }
                }
                for constructor in selected {
                    guard covered.insert(constructor.name).inserted else {
                        throw fail("Tekrarlanan match dalı '\(constructor.name)'.", at: branch.span)
                    }
                    let (fields, substitution) = try instantiate(constructor.fields, replacing: parameterMap)
                    var inner = context
                    var boundNames: Set<String> = []
                    if selection.name != nil {
                        guard selection.fields.count == fields.count else {
                            throw fail("'\(constructor.name)' pattern'i \(fields.count) alan almalı.", at: branch.pattern.span)
                        }
                        for (pattern, field) in zip(selection.fields, fields) {
                            switch pattern.kind {
                            case .wildcard: break
                            case .name(let binder):
                                // `cons(zero,tail)` içindeki zero constructor ise
                                // nested matching gerekir; sessizce binder sayma.
                                if case .constructor = globals[binder]?.kind {
                                    throw fail("İç içe constructor pattern'i yerine dal içinde ayrı match yaz.", at: pattern.span)
                                }
                                guard boundNames.insert(binder).inserted else {
                                    throw fail("Pattern'de tekrarlanan değişken '\(binder)'.", at: pattern.span)
                                }
                                inner = inner.adding(name: binder, type: field.type, value: field.variable)
                            case .constructor:
                                throw fail("İç içe constructor pattern'i yerine dal içinde ayrı match yaz.", at: pattern.span)
                            }
                        }
                    }
                    let indices = try constructor.resultIndices.map { try substitute($0, substitution) }
                    let constructed = CoreTerm.global(constructor.name).applied(to: parameters + fields.map(\.variable))
                    if let binder = selection.binder {
                        inner = inner.adding(name: binder,
                            type: CoreTerm.global(name).applied(to: parameters + indices), value: constructed)
                    }
                    let branchType = motive.applied(to: indices + [constructed])
                    let body = try check(branch.body, against: branchType, in: inner)
                    branches.append(CoreBranch(constructor: constructor.name, fields: fields, body: body))
                }
            }
            let missing = family.constructors.filter { !covered.contains($0.name) }.map(\.name)
            guard missing.isEmpty else { throw fail("Eksik match dalları: \(missing.joined(separator: ", ")).", at: match.span) }
            return CheckedExpression(term: .match(CoreMatch(family: name, scrutinee: scrutinee.term,
                                                           motive: motive, branches: branches)), type: resultType)
        }
    }

    /// Çıplak adları mevcut constructor ortamına göre çözüyoruz. Bilinmeyen
    /// çıplak ad catch-all binder'dır; ctor(...) ise mutlaka constructor olmalı.
    func selectConstructor(_ pattern: Pattern, family: InductiveInfo) throws -> (name: String?, fields: [Pattern], binder: String?) {
        switch pattern.kind {
        case .wildcard: return (nil, [], nil)
        case .constructor(let name, let fields): return (name, fields, nil)
        case .name(let name):
            if case .constructor = globals[name]?.kind { return (name, [], nil) }
            return (nil, [], name)
        }
    }
}
