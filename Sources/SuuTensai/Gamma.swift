struct LocalBinding {
    let name: String
    let type: CoreTerm
    let value: CoreTerm
}

/// Matematikteki Γ: bu noktada kullanılabilen yerel isimler ve tipleri.
/// Struct olduğu için yeni kapsam ebeveynini değiştirmez. Fonksiyondan veya
/// match dalından çıkınca o kapsamı atmak yeterlidir; unbind gerekmez.
struct LocalContext {
    var bindings: [LocalBinding] = []

    // En son bağlanan adı bul: içteki x dıştaki x'i gölgeleyebilir.
    func lookup(_ name: String) -> LocalBinding? { bindings.last { $0.name == name } }

    func adding(_ parameter: CoreParameter) -> LocalContext {
        adding(name: parameter.name, type: parameter.type, value: parameter.variable)
    }

    func adding(name: String, type: CoreTerm, value: CoreTerm) -> LocalContext {
        var copy = self
        copy.bindings.append(LocalBinding(name: name, type: type, value: value))
        return copy
    }
}

typealias Gamma = LocalContext

