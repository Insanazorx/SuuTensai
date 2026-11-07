/// İki yönlü kontrol: infer türü üretir, check verilen türü doğrular.
/// Hataları nil/false ile gizlemeyiz; kaynak konumlu KernelError fırlatırız.
protocol TypeChecker {
    func infer(_ expression: Expression, in context: LocalContext) throws -> CheckedExpression
    func check(_ expression: Expression, against expected: CoreTerm, in context: LocalContext) throws -> CoreTerm
}
