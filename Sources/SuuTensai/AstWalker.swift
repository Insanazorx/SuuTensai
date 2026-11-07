/// İsteğe bağlı sözdizimsel ziyaretçi arayüzü; kernel bu protokole dayanmaz.
/// Tür kontrolünde sadece "düğümleri gezmek" yetmez: örneğin bir return'ün
/// beklenen türünü ve bir match dalının Γ bağlamını taşımak gerekir. Bu bilgi
/// Kernel.infer/check fonksiyonlarında açık parametre olarak aktarılır.
/// Bu arayüz AST araçları yazmak için korunmuştur, doğrulama API'si değildir.
protocol AstWalker {
    // Program and declarations.
    func handleProgram(_ program: Program) throws
    func handleDeclaration(_ declaration: Declaration) throws
    func handleTheorem(_ theorem: FunctionDeclaration) throws
    func handleDefinition(_ definition: FunctionDeclaration) throws
    func handleAxiom(_ signature: Signature) throws
    func handleContext(_ context: ContextDeclaration) throws
    func handleInductive(_ declaration: InductiveDeclaration) throws
    func handleConstructor(_ constructor: ConstructorDeclaration) throws
    func handleImport(_ declaration: ImportDeclaration) throws
    func handleFunctionDeclaration(_ function: FunctionDeclaration) throws
    func handleSignature(_ signature: Signature) throws
    func handleParameter(_ parameter: Parameter) throws

    // Blocks and every StatementKind case.
    func handleBlock(_ block: Block) throws
    func handleStatement(_ statement: Statement) throws
    func handleBinding(name: String, annotation: Expression?, value: Expression, span: SourceSpan) throws
    func handleReturn(_ value: Expression, span: SourceSpan) throws
    func handleExpressionStatement(_ expression: Expression, span: SourceSpan) throws

    // Expressions and every ExpressionKind case. Decomposed cases retain the
    // enclosing expression's span so future diagnostics can point to the source.
    func handleExpression(_ expression: Expression) throws
    func handleIdentifier(_ name: String, span: SourceSpan) throws
    func handleUniverse(_ universe: Universe, span: SourceSpan) throws
    func handleNumber(_ digits: String, span: SourceSpan) throws
    func handleString(_ value: String, span: SourceSpan) throws
    func handleHole(span: SourceSpan) throws
    func handleApplication(callee: Expression, arguments: [Expression], span: SourceSpan) throws
    func handleSpecialization(callee: Expression, arguments: [Expression], span: SourceSpan) throws
    func handleUnary(_ operation: UnaryOperation, operand: Expression, span: SourceSpan) throws
    func handleBinary(_ operation: BinaryOperation, left: Expression, right: Expression, span: SourceSpan) throws
    func handleArrow(domain: Expression, codomain: Expression, span: SourceSpan) throws
    func handleDependentFunction(parameters: [Parameter], result: Expression, span: SourceSpan) throws
    func handleLambda(parameters: [Parameter], body: Expression, span: SourceSpan) throws
    func handleBlockExpression(_ block: Block, span: SourceSpan) throws
    func handleMatchExpression(_ match: MatchExpression) throws
    func handleMatchCase(_ branch: MatchCase) throws
    func handlePattern(_ pattern: Pattern) throws
    func handleNamePattern(_ name: String, span: SourceSpan) throws
    func handleConstructorPattern(name: String, arguments: [Pattern], span: SourceSpan) throws
    func handleWildcardPattern(span: SourceSpan) throws
}

