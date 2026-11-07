extension Kernel {
    /// Eşzamanlı, capture-avoiding yerine koyma.
    ///
    /// Örnek: (func (x: A) => func (y: A) => x)(y) sonucundaki iç y,
    /// dışarıdan gelen y'yi yakalamamalı. Kaynak adlarını değiştirmek yetmez.
    /// Bu yüzden geçtiğimiz her bağlayıcıya yeni kimlik verip onun gövdesini
    /// de aynı haritayla yeniden adlandırıyoruz. Haritadan alınan bir değeri
    /// tekrar haritadan geçirmiyoruz: bu eşzamanlı substitution'dır.
    func substitute(_ term: CoreTerm, _ replacements: [Int: CoreTerm]) throws -> CoreTerm {
        try framed {
            switch term {
            case .variable(let id, _): return replacements[id] ?? term
            case .global, .sort: return term
            case .app(let f, let x):
                return try .app(substitute(f, replacements), substitute(x, replacements))
            case .pi(let p, let body), .lambda(let p, let body):
                let new = try parameter(p.name, substitute(p.type, replacements))
                var inner = replacements
                inner[p.id] = new.variable
                let result = try substitute(body, inner)
                if case .pi = term { return .pi(new, result) }
                return .lambda(new, result)
            case .match(let match):
                let branches = try match.branches.map { branch in
                    var inner = replacements
                    var fields: [CoreParameter] = []
                    for field in branch.fields {
                        let new = try parameter(field.name, substitute(field.type, inner))
                        inner[field.id] = new.variable
                        fields.append(new)
                    }
                    return try CoreBranch(constructor: branch.constructor, fields: fields,
                                          body: substitute(branch.body, inner))
                }
                return try .match(CoreMatch(family: match.family,
                    scrutinee: substitute(match.scrutinee, replacements),
                    motive: substitute(match.motive, replacements), branches: branches))
            }
        }
    }

    /// Weak head normal form: sadece dıştaki işlemi açarız. Bir ifadenin
    /// fonksiyon mu, evren mi veya constructor mı olduğunu görmek için tüm
    /// alt ağacı normalleştirmek gereksiz ve pahalıdır.
    func whnf(_ input: CoreTerm) throws -> CoreTerm {
        try framed {
            var term = input
            while true {
                try step()
                switch term {
                case .global(let name):
                    // δ: doğrulanmış def/theorem gövdesini aç. Aksiyomların
                    // gövdesi yoktur; onlara bir hesaplama kuralı uydurmayız.
                    if let value = globals[name]?.value { term = value; continue }
                    return term
                case .app:
                    let (head, arguments) = term.spine
                    let reduced = try whnf(head)
                    if case .lambda(let p, let body) = reduced, let first = arguments.first {
                        // β: (λx. body) arg → body[x := arg].
                        term = try substitute(body, [p.id: first])
                            .applied(to: Array(arguments.dropFirst()))
                        continue
                    }
                    if case .global(let name) = reduced,
                       case .recursor(let familyName) = globals[name]?.kind,
                       let family = families[familyName],
                       let result = try reduceRecursor(family, arguments: arguments) {
                        term = result
                        continue
                    }
                    return reduced.applied(to: arguments)
                case .match(let match):
                    let value = try whnf(match.scrutinee)
                    let (head, arguments) = value.spine
                    if case .global(let name) = head,
                       let family = families[match.family],
                       let branch = match.branches.first(where: { $0.constructor == name }),
                       arguments.count == family.parameters.count + branch.fields.count {
                        // ι: match (constructor alanlar) ilgili dala iner.
                        // Ailenin generic parametreleri pattern alanı değildir.
                        let fields = arguments.dropFirst(family.parameters.count)
                        let replacement = Dictionary(uniqueKeysWithValues:
                            zip(branch.fields, fields).map { ($0.id, $1) })
                        term = try substitute(branch.body, replacement)
                        continue
                    }
                    return .match(CoreMatch(family: match.family, scrutinee: value,
                                            motive: match.motive, branches: match.branches))
                default: return term
                }
            }
        }
    }

    /// NatInd(P, z, s, succ(k)) → s(k, NatInd(P, z, s, k)).
    /// Aynı kod List, ağaçlar ve indeksli aileler için de çalışır. Hangi alanın
    /// recursive olduğu, indüktif bildirimin kontrolünde kaydedilmiştir.
    func reduceRecursor(_ family: InductiveInfo, arguments: [CoreTerm]) throws -> CoreTerm? {
        let prefixCount = family.parameters.count + 1 + family.constructors.count
        let total = prefixCount + family.indices.count + 1
        guard arguments.count >= total else { return nil }
        let target = try whnf(arguments[total - 1])
        let (head, values) = target.spine
        guard case .global(let name) = head,
              let position = family.constructors.firstIndex(where: { $0.name == name }) else { return nil }
        let constructor = family.constructors[position]
        guard values.count == family.parameters.count + constructor.fields.count else { return nil }

        let prefix = Array(arguments.prefix(prefixCount))
        let fields = Array(values.dropFirst(family.parameters.count))
        var substitution = Dictionary(uniqueKeysWithValues:
            zip(family.parameters, arguments).map { ($0.id, $1) })
        for (field, value) in zip(constructor.fields, fields) { substitution[field.id] = value }
        var methodArguments: [CoreTerm] = []
        for (position, field) in constructor.fields.enumerated() {
            methodArguments.append(fields[position])
            if constructor.recursiveFields.contains(position) {
                let type = try substitute(field.type, substitution)
                let (_, indices) = try familyArguments(type, family: family)
                let ih = CoreTerm.global(family.recursorName)
                    .applied(to: prefix + indices + [fields[position]])
                methodArguments.append(ih)
            }
        }
        let method = arguments[family.parameters.count + 1 + position]
        return method.applied(to: methodArguments)
            .applied(to: Array(arguments.dropFirst(total)))
    }

    /// Tam normal biçim teşhis/test ve positivity kontrolü içindir. Tür
    /// eşitliğinin kendisi aşağıda ihtiyaç oldukça WHNF'e bakar.
    func normalForm(_ input: CoreTerm) throws -> CoreTerm {
        try framed {
            let term = try whnf(input)
            switch term {
            case .pi(let p, let body):
                return try .pi(CoreParameter(id: p.id, name: p.name, type: normalForm(p.type)), normalForm(body))
            case .lambda(let p, let body):
                return try .lambda(CoreParameter(id: p.id, name: p.name, type: normalForm(p.type)), normalForm(body))
            case .app(let f, let x): return try .app(normalForm(f), normalForm(x))
            case .match(let match):
                return try .match(CoreMatch(family: match.family, scrutinee: normalForm(match.scrutinee),
                    motive: normalForm(match.motive), branches: match.branches.map { branch in
                        try CoreBranch(constructor: branch.constructor,
                            fields: branch.fields.map { p in
                                try CoreParameter(id: p.id, name: p.name, type: normalForm(p.type))
                            }, body: normalForm(branch.body))
                    }))
            default: return term
            }
        }
    }

    /// Definitional equality: α (bağlayıcı adları) + β + δ + ι.
    /// Burada Id(a,b) kanıtı aranmıyor. `same(a,b)` hesabın iki ifadeyi aynı
    /// kabul etmesi; Id ise kullanıcı dilinde ayrıca tanımlanmış bir tiptir.
    /// Bu sürüm eta veya proof-irrelevance eşitliğini varsaymaz.
    func same(_ left: CoreTerm, _ right: CoreTerm) throws -> Bool {
        try framed {
            let a = try whnf(left)
            let b = try whnf(right)
            switch (a, b) {
            case (.variable(let x, _), .variable(let y, _)): return x == y
            case (.global(let x), .global(let y)): return x == y
            case (.sort(let x), .sort(let y)): return x == y
            case (.app(let f, let x), .app(let g, let y)):
                return try same(f, g) && same(x, y)
            case (.pi(let p, let x), .pi(let q, let y)),
                 (.lambda(let p, let x), .lambda(let q, let y)):
                guard try same(p.type, q.type) else { return false }
                // İki gövdeyi de aynı taze değişkenle aç: λx.x = λy.y.
                let fresh = parameter(p.name, p.type).variable
                return try same(substitute(x, [p.id: fresh]), substitute(y, [q.id: fresh]))
            case (.match(let x), .match(let y)):
                guard x.family == y.family, x.branches.count == y.branches.count,
                      try same(x.scrutinee, y.scrutinee), try same(x.motive, y.motive) else { return false }
                for branch in x.branches {
                    guard let other = y.branches.first(where: { $0.constructor == branch.constructor }),
                          other.fields.count == branch.fields.count else { return false }
                    var xs: [Int: CoreTerm] = [:]
                    var ys: [Int: CoreTerm] = [:]
                    for (p, q) in zip(branch.fields, other.fields) {
                        let pt = try substitute(p.type, xs)
                        let qt = try substitute(q.type, ys)
                        guard try same(pt, qt) else { return false }
                        let fresh = parameter(p.name, pt).variable
                        xs[p.id] = fresh
                        ys[q.id] = fresh
                    }
                    guard try same(substitute(branch.body, xs), substitute(other.body, ys)) else { return false }
                }
                return true
            default: return false
            }
        }
    }

    func demandSame(_ actual: CoreTerm, _ expected: CoreTerm, at span: SourceSpan) throws {
        guard try same(actual, expected) else {
            throw fail("Tür uyuşmazlığı: beklenen \(expected.description), bulunan \(actual.description).", at: span)
        }
    }

    /// İndüktif ailesinin tam uygulanmış türünü ayırır: I(params..., indices...).
    func familyArguments(_ type: CoreTerm, family: InductiveInfo) throws -> ([CoreTerm], [CoreTerm]) {
        let (head, arguments) = try whnf(type).spine
        guard case .global(let name) = head, name == family.name,
              arguments.count == family.parameters.count + family.indices.count else {
            throw fail("'\(family.name)' ailesine tam uygulanmış bir tip bekleniyor.")
        }
        return (Array(arguments.prefix(family.parameters.count)),
                Array(arguments.dropFirst(family.parameters.count)))
    }
}
