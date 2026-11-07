/// Değişkenin kimliği kaynak adı değil, benzersiz id'dir. name sadece hata
/// mesajında insana okunabilir ad göstermek içindir.
struct CoreParameter: Equatable {
    let id: Int
    let name: String
    let type: CoreTerm

    var variable: CoreTerm { .variable(id, name) }
}

indirect enum CoreTerm: Equatable {
    // Yerel değişken Γ'da kimliğiyle bulunur. Global ise doğrulanmış ortamda
    // kendi adıyla bulunur; ikisini ayırmak shadowing'i güvenli hale getirir.
    case variable(Int, String)
    case global(String)
    // Sort hem Type(n) hem Prop olabilir: tiplerin de bir tipi vardır.
    case sort(Universe)
    // Pi bir TİP: (x:A)->B(x). Lambda bir DEĞER: func(x:A)=>body.
    case pi(CoreParameter, CoreTerm)
    case lambda(CoreParameter, CoreTerm)
    // Core uygulaması tek argümanlıdır. f(a,b) = app(app(f,a),b).
    case app(CoreTerm, CoreTerm)
    case match(CoreMatch)

    func applied(to arguments: [CoreTerm]) -> CoreTerm {
        arguments.reduce(self) { .app($0, $1) }
    }

    var spine: (head: CoreTerm, arguments: [CoreTerm]) {
        var head = self
        var arguments: [CoreTerm] = []
        while case .app(let function, let argument) = head {
            arguments.append(argument)
            head = function
        }
        return (head, arguments.reversed())
    }

    var description: String {
        var budget = 120
        return pretty(depth: 12, budget: &budget)
    }

    /// Bir hata mesajı da saldırgan girdiyi yazarken stack'i taşırmamalı.
    /// Uzun hesapların/isimlerin sadece okunabilir bir önizlemesini gösteririz.
    private func pretty(depth: Int, budget: inout Int) -> String {
        guard depth > 0, budget > 0 else { return "…" }
        budget -= 1
        switch self {
        case .variable(_, let name), .global(let name): return String(name.prefix(80))
        case .sort(.prop): return "Prop"
        case .sort(.type(let level)): return "Type(\(level))"
        case .pi(let p, let body):
            return "((\(p.name.prefix(80)): \(p.type.pretty(depth: depth - 1, budget: &budget))) -> \(body.pretty(depth: depth - 1, budget: &budget)))"
        case .lambda(let p, let body):
            return "(func (\(p.name.prefix(80)): \(p.type.pretty(depth: depth - 1, budget: &budget))) => \(body.pretty(depth: depth - 1, budget: &budget)))"
        case .app:
            let (head, arguments) = spine
            let values = arguments.prefix(8).map { $0.pretty(depth: depth - 1, budget: &budget) }.joined(separator: ", ")
            return "\(head.pretty(depth: depth - 1, budget: &budget))(\(values)\(arguments.count > 8 ? ", …" : ""))"
        case .match(let match): return "match \(match.scrutinee.pretty(depth: depth - 1, budget: &budget)) { … }"
        }
    }
}

struct CoreMatch: Equatable {
    let family: String
    let scrutinee: CoreTerm
    let motive: CoreTerm
    let branches: [CoreBranch]
}

struct CoreBranch: Equatable {
    let constructor: String
    let fields: [CoreParameter]
    let body: CoreTerm
}

enum GlobalKind {
    case axiom, definition, theorem, family, constructor, recursor(String)
}

struct GlobalEntry {
    // Aksiyom, aile, constructor ve recursor'un gövdesi nil olabilir;
    // buna rağmen hepsinin kontrol edilmiş bir tipi bulunur.
    let type: CoreTerm
    let value: CoreTerm?
    let kind: GlobalKind
    let axioms: Set<String>
}

struct ConstructorInfo {
    let name: String
    /// Ailenin uniform parametreleri bu alan listesine dahil değildir.
    let fields: [CoreParameter]
    let resultIndices: [CoreTerm]
    // Bu pozisyonlar için recursor bir induction hypothesis üretecek.
    let recursiveFields: Set<Int>
}

struct InductiveInfo {
    let name: String
    let parameters: [CoreParameter]
    let indices: [CoreParameter]
    let sort: Universe
    let constructors: [ConstructorInfo]
    var recursorName: String { name + "Ind" }
}

struct CheckedExpression {
    let term: CoreTerm
    let type: CoreTerm
}
