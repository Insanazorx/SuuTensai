/// Compact source-like descriptions for precedence inspection.
/// astDescription renders the full tree; these are not serialization.
extension Expression {
    public var sourceDescription: String {
        switch kind {
        case .identifier(let name): return name
        case .universe(.type(let level)): return level == 0 ? "Type" : "Type(\(level))"
        case .universe(.prop): return "Prop"
        case .number(let digits): return digits
        case .string(let value): return value.debugDescription
        case .hole: return "_"
        case .application(let callee, let arguments):
            return "\(callee.sourceDescription)(\(arguments.map(\.sourceDescription).joined(separator: ", ")))"
        case .specialization(let callee, let arguments):
            return "\(callee.sourceDescription)<\(arguments.map(\.sourceDescription).joined(separator: ", "))>"
        case .unary(let operation, let operand):
            return "(\(operation.rawValue)\(operand.sourceDescription))"
        case .binary(let operation, let left, let right):
            return "(\(left.sourceDescription) \(operation.rawValue) \(right.sourceDescription))"
        case .arrow(let domain, let codomain):
            return "(\(domain.sourceDescription) -> \(codomain.sourceDescription))"
        case .dependentFunction(let parameters, let result):
            return "((\(parameters.map(\.sourceDescription).joined(separator: ", "))) -> \(result.sourceDescription))"
        case .lambda(let parameters, let body):
            return "(fun (\(parameters.map(\.sourceDescription).joined(separator: ", "))) => \(body.sourceDescription))"
        case .block(let block): return block.sourceDescription
        case .match(let value): return value.sourceDescription
        }
    }
}

extension Pattern {
    public var sourceDescription: String {
        switch kind {
        case .name(let name): return name
        case .constructor(let name, let arguments):
            return name + "(" + arguments.map(\.sourceDescription).joined(separator: ", ") + ")"
        case .wildcard: return "_"
        }
    }
}

extension MatchExpression {
    public var sourceDescription: String {
        let motive = motive.map { " return " + $0.sourceDescription } ?? ""
        let branches = cases.map { $0.pattern.sourceDescription + " => " + $0.body.sourceDescription }
        return "match " + scrutinee.sourceDescription + motive + " { " + branches.joined(separator: "; ") + " }"
    }
}

extension Parameter {
    public var sourceDescription: String { "\(name): \(type.sourceDescription)" }
}

extension Statement {
    public var sourceDescription: String {
        switch kind {
        case .binding(let name, let annotation, let value):
            return "Let \(name)\(annotation.map { ": " + $0.sourceDescription } ?? "") = \(value.sourceDescription)"
        case .return(let value): return "Return \(value.sourceDescription)"
        case .expression(let value): return "Expression \(value.sourceDescription)"
        }
    }
}

extension Block {
    public var sourceDescription: String {
        let statements = statements.map(\.sourceDescription)
        let result = result.map { ["Result " + $0.sourceDescription] } ?? []
        return "{ " + (statements + result).joined(separator: "; ") + " }"
    }
}

