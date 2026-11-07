/// Surface syntax only. Parsing never resolves names, constructs Gamma, infers
/// types, inserts implicit arguments, or decides whether a proof is valid.
public struct Program: Equatable, Sendable {
    public let declarations: [Declaration]
    public let span: SourceSpan
}

public enum Declaration: Equatable, Sendable {
    case theorem(FunctionDeclaration)
    case definition(FunctionDeclaration)
    case axiom(Signature)
    case context(ContextDeclaration)
    case inductive(InductiveDeclaration)
    case `import`(ImportDeclaration)

    public var span: SourceSpan {
        switch self {
        case .theorem(let value), .definition(let value): value.span
        case .axiom(let value): value.span
        case .context(let value): value.span
        case .inductive(let value): value.span
        case .import(let value): value.span
        }
    }
}

/// Generic and value binders remain separate and retain their written order.
public struct Signature: Equatable, Sendable {
    public let name: String
    public let genericParameters: [Parameter]
    public let parameters: [Parameter]
    public let returnType: Expression
    public let span: SourceSpan
}

public struct FunctionDeclaration: Equatable, Sendable {
    public let signature: Signature
    public let body: Block
    public let span: SourceSpan
}

public struct Parameter: Equatable, Sendable {
    public let name: String
    public let type: Expression
    public let span: SourceSpan
}

/// A declared context is syntax, not the kernel's mutable runtime environment.
public struct ContextDeclaration: Equatable, Sendable {
    public let name: String
    public let bindings: [Parameter]
    public let span: SourceSpan
}

/// Uniform parameters go in <...>; varying indices go in (...).
/// Example: inductive Id<A: Type>(x: A, y: A): Type { ... }
public struct InductiveDeclaration: Equatable, Sendable {
    public let name: String
    public let parameters: [Parameter]
    public let indices: [Parameter]
    public let sort: Expression
    public let constructors: [ConstructorDeclaration]
    public let span: SourceSpan
}

/// Constructor types use the same arrow/Pi syntax as any other type.
/// The kernel will validate their return family, universes, and positivity.
public struct ConstructorDeclaration: Equatable, Sendable {
    public let name: String
    public let type: Expression
    public let span: SourceSpan
}

/// Syntax only: parsing an import never opens or executes another file.
public struct ImportDeclaration: Equatable, Sendable {
    public let path: String
    public let span: SourceSpan
}

public struct Block: Equatable, Sendable {
    public let statements: [Statement]
    /// The final expression without a semicolon, e.g. { let y = x; y }.
    public let result: Expression?
    public let span: SourceSpan
}

public struct Statement: Equatable, Sendable {
    public let kind: StatementKind
    public let span: SourceSpan
}

public enum StatementKind: Equatable, Sendable {
    case binding(name: String, annotation: Expression?, value: Expression)
    case `return`(Expression)
    case expression(Expression)
}

/// Types are expressions too: A, F<A>, and A -> B use the same tree as
/// proof terms. Whether an expression is a type is a question for your kernel.
public struct Expression: Equatable, Sendable {
    public let kind: ExpressionKind
    public let span: SourceSpan

    // Cached height lets the parser bound long left-associative/postfix trees
    // without repeatedly walking them (which would make parsing quadratic).
    let treeDepth: Int

    init(kind: ExpressionKind, span: SourceSpan) {
        self.kind = kind
        self.span = span
        self.treeDepth = kind.childDepth + 1
    }
}

public indirect enum ExpressionKind: Equatable, Sendable {
    case identifier(String)
    case universe(Universe)
    case number(String)
    case string(String)
    case hole
    case application(callee: Expression, arguments: [Expression])
    case specialization(callee: Expression, arguments: [Expression])
    case unary(UnaryOperation, Expression)
    case binary(BinaryOperation, left: Expression, right: Expression)
    /// Nondependent arrow, right-associative: A -> B -> C.
    case arrow(domain: Expression, codomain: Expression)
    /// Dependent function type: (x: A, y: B) -> P(x, y).
    case dependentFunction(parameters: [Parameter], result: Expression)
    case lambda(parameters: [Parameter], body: Expression)
    case block(Block)
    case match(MatchExpression)

    var childDepth: Int {
        switch self {
        case .identifier, .universe, .number, .string, .hole: return 0
        case .application(let callee, let arguments), .specialization(let callee, let arguments):
            return max(callee.treeDepth, arguments.map(\.treeDepth).max() ?? 0)
        case .unary(_, let operand): return operand.treeDepth
        case .binary(_, let left, let right), .arrow(let left, let right):
            return max(left.treeDepth, right.treeDepth)
        case .dependentFunction(let parameters, let result), .lambda(let parameters, let result):
            return max(parameters.map { $0.type.treeDepth }.max() ?? 0, result.treeDepth)
        case .block(let block):
            return max(block.result?.treeDepth ?? 0, block.statements.map { statement in
                switch statement.kind {
                case .binding(_, let annotation, let value): max(annotation?.treeDepth ?? 0, value.treeDepth)
                case .return(let expression), .expression(let expression): expression.treeDepth
                }
            }.max() ?? 0)
        case .match(let match):
            let branches = match.cases.map { max($0.pattern.treeDepth, $0.body.treeDepth) }.max() ?? 0
            return max(max(match.scrutinee.treeDepth, match.motive?.treeDepth ?? 0), branches)
        }
    }
}

/// Type is shorthand for Type(0). Universe validation belongs to the kernel.
public enum Universe: Equatable, Sendable { case type(level: Int), prop }

public struct MatchExpression: Equatable, Sendable {
    public let scrutinee: Expression
    /// Optional explicit type family, written as "return fun (...) => ...".
    /// It may bind indices as well as the scrutinee for indexed elimination.
    public let motive: Expression?
    public let cases: [MatchCase]
    public let span: SourceSpan
}

public struct MatchCase: Equatable, Sendable {
    public let pattern: Pattern
    public let body: Expression
    public let span: SourceSpan
}

public struct Pattern: Equatable, Sendable {
    public let kind: PatternKind
    public let span: SourceSpan
    let treeDepth: Int

    init(kind: PatternKind, span: SourceSpan) {
        self.kind = kind
        self.span = span
        switch kind {
        case .name, .wildcard: self.treeDepth = 1
        case .constructor(_, let arguments):
            self.treeDepth = 1 + (arguments.map(\.treeDepth).max() ?? 0)
        }
    }
}

public indirect enum PatternKind: Equatable, Sendable {
    /// Unresolved bare name: symbol resolution decides constructor vs binder.
    case name(String)
    /// Parentheses explicitly select constructor syntax, even with no fields.
    case constructor(name: String, arguments: [Pattern])
    case wildcard
}
