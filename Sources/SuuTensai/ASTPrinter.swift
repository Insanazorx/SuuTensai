/// Structural AST output. Every child node is rendered recursively, including
/// expressions inside signatures, return values, motives, branches and patterns.
extension Program {
    public var astDescription: String { describeTree { $0.program(self, at: 0) } }
}

extension Declaration {
    public var astDescription: String { describeTree { $0.declaration(self, at: 0) } }
}

extension FunctionDeclaration {
    public var astDescription: String { describeTree { $0.function(self, label: "Function", at: 0) } }
}

extension Signature {
    public var astDescription: String { describeTree { $0.signature(self, at: 0) } }
}

extension Parameter {
    public var astDescription: String { describeTree { $0.parameter(self, at: 0) } }
}

extension ContextDeclaration {
    public var astDescription: String { describeTree { $0.context(self, at: 0) } }
}

extension InductiveDeclaration {
    public var astDescription: String { describeTree { $0.inductive(self, at: 0) } }
}

extension ConstructorDeclaration {
    public var astDescription: String { describeTree { $0.constructor(self, at: 0) } }
}

extension ImportDeclaration {
    public var astDescription: String { describeTree { $0.importDeclaration(self, at: 0) } }
}

extension Block {
    public var astDescription: String { describeTree { $0.block(self, at: 0) } }
}

extension Statement {
    public var astDescription: String { describeTree { $0.statement(self, at: 0) } }
}

extension Expression {
    public var astDescription: String { describeTree { $0.expression(self, at: 0) } }
}

extension MatchExpression {
    public var astDescription: String { describeTree { $0.matchExpression(self, at: 0) } }
}

extension MatchCase {
    public var astDescription: String { describeTree { $0.branch(self, at: 0) } }
}

extension Pattern {
    public var astDescription: String { describeTree { $0.pattern(self, at: 0) } }
}

private func describeTree(_ write: (inout ASTTreePrinter) -> Void) -> String {
    var printer = ASTTreePrinter()
    write(&printer)
    return printer.lines.joined(separator: "\n")
}

private struct ASTTreePrinter {
    var lines: [String] = []

    mutating func line(_ text: String, at depth: Int) {
        lines.append(String(repeating: "  ", count: depth) + text)
    }

    mutating func program(_ value: Program, at depth: Int) {
        line("Program", at: depth)
        for item in value.declarations { declaration(item, at: depth + 1) }
    }

    mutating func declaration(_ value: Declaration, at depth: Int) {
        switch value {
        case .theorem(let value): function(value, label: "Theorem", at: depth)
        case .definition(let value): function(value, label: "Definition", at: depth)
        case .axiom(let value):
            line("Axiom " + value.name, at: depth)
            signature(value, at: depth + 1)
        case .context(let value): context(value, at: depth)
        case .inductive(let value): inductive(value, at: depth)
        case .import(let value): importDeclaration(value, at: depth)
        }
    }

    mutating func function(_ value: FunctionDeclaration, label: String, at depth: Int) {
        line(label + " " + value.signature.name, at: depth)
        signature(value.signature, at: depth + 1)
        line("Body", at: depth + 1)
        block(value.body, at: depth + 2)
    }

    mutating func signature(_ value: Signature, at depth: Int) {
        line("Signature " + value.name, at: depth)
        parameters(value.genericParameters, label: "GenericParameters", at: depth + 1)
        parameters(value.parameters, label: "Parameters", at: depth + 1)
        field("Returns", value.returnType, at: depth + 1)
    }

    mutating func parameters(_ values: [Parameter], label: String, at depth: Int) {
        line(label, at: depth)
        for value in values { parameter(value, at: depth + 1) }
    }

    mutating func parameter(_ value: Parameter, at depth: Int) {
        line("Parameter " + value.name, at: depth)
        field("Type", value.type, at: depth + 1)
    }

    mutating func context(_ value: ContextDeclaration, at depth: Int) {
        line("Context " + value.name, at: depth)
        parameters(value.bindings, label: "Bindings", at: depth + 1)
    }

    mutating func inductive(_ value: InductiveDeclaration, at depth: Int) {
        line("Inductive " + value.name, at: depth)
        parameters(value.parameters, label: "Parameters", at: depth + 1)
        parameters(value.indices, label: "Indices", at: depth + 1)
        field("Sort", value.sort, at: depth + 1)
        line("Constructors", at: depth + 1)
        for item in value.constructors { constructor(item, at: depth + 2) }
    }

    mutating func constructor(_ value: ConstructorDeclaration, at depth: Int) {
        line("Constructor " + value.name, at: depth)
        field("Type", value.type, at: depth + 1)
    }

    mutating func importDeclaration(_ value: ImportDeclaration, at depth: Int) {
        line("Import " + value.path.debugDescription, at: depth)
    }

    mutating func block(_ value: Block, at depth: Int) {
        line("Block", at: depth)
        line("Statements", at: depth + 1)
        for item in value.statements { statement(item, at: depth + 2) }
        if let result = value.result { field("Result", result, at: depth + 1) }
    }

    mutating func statement(_ value: Statement, at depth: Int) {
        switch value.kind {
        case .binding(let name, let annotation, let initializer):
            line("Binding " + name, at: depth)
            if let annotation { field("Annotation", annotation, at: depth + 1) }
            field("Value", initializer, at: depth + 1)
        case .return(let value):
            line("Return", at: depth)
            expression(value, at: depth + 1)
        case .expression(let value):
            line("ExpressionStatement", at: depth)
            expression(value, at: depth + 1)
        }
    }

    mutating func field(_ label: String, _ value: Expression, at depth: Int) {
        line(label, at: depth)
        expression(value, at: depth + 1)
    }

    mutating func expressions(_ values: [Expression], label: String, at depth: Int) {
        line(label, at: depth)
        for value in values { expression(value, at: depth + 1) }
    }

    mutating func expression(_ value: Expression, at depth: Int) {
        switch value.kind {
        case .identifier(let name): line("Identifier " + name, at: depth)
        case .universe(.type(let level)): line("Universe Type(\(level))", at: depth)
        case .universe(.prop): line("Universe Prop", at: depth)
        case .number(let digits): line("Number " + digits, at: depth)
        case .string(let value): line("String " + value.debugDescription, at: depth)
        case .hole: line("Hole", at: depth)
        case .application(let callee, let arguments):
            line("Application", at: depth)
            field("Callee", callee, at: depth + 1)
            expressions(arguments, label: "Arguments", at: depth + 1)
        case .specialization(let callee, let arguments):
            line("Specialization", at: depth)
            field("Callee", callee, at: depth + 1)
            expressions(arguments, label: "Arguments", at: depth + 1)
        case .unary(let operation, let operand):
            line("Unary " + operation.rawValue, at: depth)
            field("Operand", operand, at: depth + 1)
        case .binary(let operation, let left, let right):
            line("Binary " + operation.rawValue, at: depth)
            field("Left", left, at: depth + 1)
            field("Right", right, at: depth + 1)
        case .arrow(let domain, let codomain):
            line("Arrow", at: depth)
            field("Domain", domain, at: depth + 1)
            field("Codomain", codomain, at: depth + 1)
        case .dependentFunction(let values, let result):
            line("DependentFunction", at: depth)
            parameters(values, label: "Parameters", at: depth + 1)
            field("Result", result, at: depth + 1)
        case .lambda(let values, let body):
            line("Lambda", at: depth)
            parameters(values, label: "Parameters", at: depth + 1)
            field("Body", body, at: depth + 1)
        case .block(let value): block(value, at: depth)
        case .match(let value): matchExpression(value, at: depth)
        }
    }

    mutating func matchExpression(_ value: MatchExpression, at depth: Int) {
        line("Match", at: depth)
        field("Scrutinee", value.scrutinee, at: depth + 1)
        if let motive = value.motive { field("Motive", motive, at: depth + 1) }
        line("Cases", at: depth + 1)
        for item in value.cases { branch(item, at: depth + 2) }
    }

    mutating func branch(_ value: MatchCase, at depth: Int) {
        line("Case", at: depth)
        line("Pattern", at: depth + 1)
        pattern(value.pattern, at: depth + 2)
        field("Body", value.body, at: depth + 1)
    }

    mutating func pattern(_ value: Pattern, at depth: Int) {
        switch value.kind {
        case .name(let name): line("NamePattern " + name, at: depth)
        case .wildcard: line("WildcardPattern", at: depth)
        case .constructor(let name, let arguments):
            line("ConstructorPattern " + name, at: depth)
            line("Arguments", at: depth + 1)
            for item in arguments { pattern(item, at: depth + 2) }
        }
    }
}
