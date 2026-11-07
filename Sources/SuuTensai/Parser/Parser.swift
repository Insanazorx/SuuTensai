/// Recursive descent for declarations; precedence climbing for expressions.
/// Each public call starts with a fresh cursor and consumes the entire input.
public struct Parser {
    private let tokens: [Token]
    private let maxNesting: Int

    /// Debug Swift frames can be large on the 512 KiB worker stacks used by
    /// Swift Testing. Keep a conservative ceiling for every recursive grammar
    /// path, including nested blocks and binder annotations, not just parentheses.
    public init(tokens: [Token], maxNesting: Int = 32) {
        let end = tokens.last?.span.end ?? SourceSpan.zero.end
        let eof = Token(kind: .endOfFile, lexeme: "", span: SourceSpan(start: end, end: end))
        self.tokens = tokens.last?.kind == .endOfFile ? tokens : tokens + [eof]
        self.maxNesting = max(1, min(maxNesting, 32))
    }

    public init(source: String, maxNesting: Int = 32) throws {
        self.init(tokens: try Lexer(source).tokenize(), maxNesting: maxNesting)
    }

    public func parse() throws -> Program {
        var cursor = ParseCursor(tokens: tokens, maxNesting: maxNesting)
        try cursor.validateEndOfFile()
        return try cursor.program()
    }

    /// Useful when testing the frontend or parsing a standalone type/proof term.
    public func parseExpression() throws -> Expression {
        var cursor = ParseCursor(tokens: tokens, maxNesting: maxNesting)
        try cursor.validateEndOfFile()
        let expression = try cursor.expression()
        try cursor.expect(.endOfFile, "end of input")
        return expression
    }
}

private struct ParseCursor {
    let tokens: [Token]
    let maxNesting: Int
    var position = 0
    var recursionDepth = 0

    var current: Token { tokens[position] }
    var previous: Token { tokens[max(0, position - 1)] }

    func validateEndOfFile() throws {
        if let token = tokens.dropLast().first(where: { $0.kind == .endOfFile }) {
            throw failure("Unexpected end-of-file token before the end of the token stream.", at: token.span)
        }
    }

    func failure(_ message: String, at span: SourceSpan? = nil) -> FrontendError {
        FrontendError(phase: .parser, message: message, span: span ?? current.span)
    }

    @discardableResult
    mutating func advance() -> Token {
        let token = current
        if current.kind != .endOfFile { position += 1 }
        return token
    }

    @discardableResult
    mutating func match(_ kind: TokenKind) -> Bool {
        guard current.kind == kind else { return false }
        advance()
        return true
    }

    @discardableResult
    mutating func expect(_ kind: TokenKind, _ label: String) throws -> Token {
        guard current.kind == kind else {
            let found = current.kind == .endOfFile ? "end of input" : current.lexeme.debugDescription
            throw failure("Expected \(label); found \(found).")
        }
        return advance()
    }

    mutating func name(allowWildcard: Bool = false) throws -> String {
        if case .identifier(let value) = current.kind { advance(); return value }
        if allowWildcard, match(.hole) { return "_" }
        throw failure("Expected an identifier; found \(current.lexeme.debugDescription).")
    }

    mutating func program() throws -> Program {
        let start = current.span.start
        var declarations: [Declaration] = []
        while current.kind != .endOfFile {
            declarations.append(try declaration())
        }
        return Program(declarations: declarations, span: SourceSpan(start: start, end: current.span.end))
    }

    mutating func declaration() throws -> Declaration {
        let start = current.span.start
        switch current.kind {
        case .theorem, .definition:
            let isTheorem = advance().kind == .theorem
            let signature = try signature(from: start)
            let body = try block()
            let function = FunctionDeclaration(signature: signature, body: body,
                                               span: SourceSpan(start: start, end: body.span.end))
            match(.semicolon)
            return isTheorem ? .theorem(function) : .definition(function)
        case .axiom:
            advance()
            let signature = try signature(from: start)
            try terminator()
            return .axiom(Signature(name: signature.name, genericParameters: signature.genericParameters,
                                    parameters: signature.parameters, returnType: signature.returnType,
                                    span: SourceSpan(start: start, end: previous.span.end)))
        case .gamma:
            advance()
            let contextName = try name()
            try expect(.leftBrace, "'{' to start the context")
            var bindings: [Parameter] = []
            while current.kind != .rightBrace {
                if current.kind == .endOfFile { throw failure("Expected '}' to close the context.") }
                bindings.append(try parameter())
                try terminator()
            }
            let end = advance().span.end
            match(.semicolon)
            return .context(ContextDeclaration(name: contextName, bindings: bindings,
                                               span: SourceSpan(start: start, end: end)))
        case .inductive:
            return .inductive(try inductiveDeclaration())
        case .import:
            return .import(try importDeclaration())
        default:
            throw failure("Expected a declaration: 'theorem', 'def', 'axiom', 'Gamma', 'inductive', or 'import'.")
        }
    }

    private mutating func importDeclaration() throws -> ImportDeclaration {
        let start = advance().span.start
        guard case .string(let path) = current.kind else {
            throw failure("Expected a quoted file path after 'import'.")
        }
        advance()
        try terminator()
        return ImportDeclaration(path: path, span: SourceSpan(start: start, end: previous.span.end))
    }

    private mutating func inductiveDeclaration() throws -> InductiveDeclaration {
        let start = advance().span.start
        let typeName = try name()
        let uniform = current.kind == .leftAngle
            ? try parameters(open: .leftAngle, close: .rightAngle, allowEmpty: false) : []
        let indices = current.kind == .leftParen
            ? try parameters(open: .leftParen, close: .rightParen) : []
        try expect(.colon, "':' before the inductive family's sort")
        let sort = try expression()
        try expect(.leftBrace, "'{' before constructors")
        var constructors: [ConstructorDeclaration] = []
        while current.kind != .rightBrace {
            if current.kind == .endOfFile { throw failure("Expected '}' to close the inductive declaration.") }
            constructors.append(try constructorDeclaration())
        }
        let end = advance().span.end
        match(.semicolon)
        return InductiveDeclaration(name: typeName, parameters: uniform, indices: indices,
                                    sort: sort, constructors: constructors,
                                    span: SourceSpan(start: start, end: end))
    }

    private mutating func constructorDeclaration() throws -> ConstructorDeclaration {
        let start = current.span.start
        let constructorName = try name()
        try expect(.colon, "':' after the constructor name")
        let type = try expression()
        try terminator()
        return ConstructorDeclaration(name: constructorName, type: type,
                                      span: SourceSpan(start: start, end: previous.span.end))
    }

    mutating func signature(from start: SourcePosition) throws -> Signature {
        let functionName = try name()
        let generics = current.kind == .leftAngle
            ? try parameters(open: .leftAngle, close: .rightAngle, allowEmpty: false) : []
        let values = try parameters(open: .leftParen, close: .rightParen)
        try expect(.arrow, "'->' before the return type")
        let result = try expression()
        return Signature(name: functionName, genericParameters: generics, parameters: values,
                         returnType: result, span: SourceSpan(start: start, end: result.span.end))
    }

    mutating func parameter() throws -> Parameter {
        let start = current.span.start
        let parameterName = try name(allowWildcard: true)
        try expect(.colon, "':' after the parameter name")
        let type = try expression()
        return Parameter(name: parameterName, type: type, span: SourceSpan(start: start, end: type.span.end))
    }

    mutating func parameters(
        open: TokenKind, close: TokenKind, allowEmpty: Bool = true
    ) throws -> [Parameter] {
        try expect(open, open == .leftAngle ? "'<'" : "'('")
        var values: [Parameter] = []
        if current.kind == close {
            guard allowEmpty else { throw failure("Expected at least one generic parameter.") }
            advance()
            return values
        }
        while true {
            values.append(try parameter())
            if !match(.comma) { break }
            if current.kind == close { break } // trailing comma
        }
        try expect(close, close == .rightAngle ? "'>' after parameters" : "')' after parameters")
        return values
    }

    /// Newlines separate statements only after an expression has finished.
    /// Operators and postfix calls may continue an expression across newlines.
    mutating func terminator() throws {
        if match(.semicolon) { return }
        if current.kind == .rightBrace || current.kind == .endOfFile || current.isPrecededByLineBreak { return }
        throw failure("Expected ';' or a line break after the statement.")
    }

    mutating func block() throws -> Block {
        let start = try expect(.leftBrace, "'{' to start the body").span.start
        var statements: [Statement] = []
        var result: Expression?
        while current.kind != .rightBrace {
            if current.kind == .endOfFile { throw failure("Expected '}' to close the body.") }
            if match(.semicolon) { continue }
            let statementStart = current.span.start
            let kind: StatementKind
            if match(.let) {
                let bindingName = try name(allowWildcard: true)
                let annotation = match(.colon) ? try expression() : nil
                try expect(.assign, "'=' in the let binding")
                let value = try expression()
                kind = .binding(name: bindingName, annotation: annotation, value: value)
                try terminator()
            } else if match(.return) {
                kind = .return(try expression())
                try terminator()
            } else {
                let value = try expression()
                if current.kind == .rightBrace {
                    result = value
                    break
                }
                kind = .expression(value)
                try terminator()
            }
            statements.append(Statement(kind: kind, span: SourceSpan(start: statementStart, end: previous.span.end)))
        }
        let end = try expect(.rightBrace, "'}' to close the body").span.end
        return Block(statements: statements, result: result, span: SourceSpan(start: start, end: end))
    }

    mutating func make(_ kind: ExpressionKind, from start: SourcePosition, to end: SourcePosition) throws -> Expression {
        let span = SourceSpan(start: start, end: end)
        let result = Expression(kind: kind, span: span)
        guard result.treeDepth <= maxNesting else {
            throw failure("Expression tree exceeds the depth limit (\(maxNesting)).", at: span)
        }
        return result
    }

    mutating func expression(minPrecedence: Int = 0) throws -> Expression {
        guard recursionDepth < maxNesting else {
            throw failure("Expression nesting exceeds the depth limit (\(maxNesting)).")
        }
        recursionDepth += 1
        defer { recursionDepth -= 1 }
        var left = try postfix()
        while let operation = infixOperation, operation.precedence >= minPrecedence {
            advance()
            left = try infix(left, operation: operation)
        }
        return left
    }

    private enum Infix {
        case arrow
        case binary(BinaryOperation)

        var precedence: Int {
            switch self { case .arrow: 1; case .binary(let value): value.precedence }
        }

        var rightPrecedence: Int {
            switch self {
            case .arrow: 1
            case .binary(let value): value.precedence + (value == .power ? 0 : 1)
            }
        }
    }

    private var infixOperation: Infix? {
        switch current.kind {
        case .arrow: .arrow
        case .binaryOp(let value): .binary(value)
        default: nil
        }
    }

    private mutating func infix(_ left: Expression, operation: Infix) throws -> Expression {
        let right = try expression(minPrecedence: operation.rightPrecedence)
        let kind: ExpressionKind
        switch operation {
        case .arrow: kind = .arrow(domain: left, codomain: right)
        case .binary(let value): kind = .binary(value, left: left, right: right)
        }
        return try make(kind, from: left.span.start, to: right.span.end)
    }

    private mutating func postfix() throws -> Expression {
        var value = try prefix()
        while current.kind == .leftParen || current.kind == .leftAngle {
            value = try application(value)
        }
        return value
    }

    private mutating func application(_ callee: Expression) throws -> Expression {
        let isGeneric = current.kind == .leftAngle
        let values = try arguments(open: isGeneric ? .leftAngle : .leftParen,
                                   close: isGeneric ? .rightAngle : .rightParen, allowEmpty: !isGeneric)
        let kind: ExpressionKind = isGeneric ? .specialization(callee: callee, arguments: values)
            : .application(callee: callee, arguments: values)
        return try make(kind, from: callee.span.start, to: previous.span.end)
    }

    mutating func arguments(open: TokenKind, close: TokenKind, allowEmpty: Bool) throws -> [Expression] {
        try expect(open, open == .leftParen ? "'('" : "'<'")
        var values: [Expression] = []
        if current.kind == close {
            guard allowEmpty else { throw failure("Expected at least one type argument.") }
            advance()
            return values
        }
        while true {
            values.append(try expression())
            if !match(.comma) { break }
            if current.kind == close { break }
        }
        try expect(close, close == .rightParen ? "')' after arguments" : "'>' after type arguments")
        return values
    }

    mutating func prefix() throws -> Expression {
        let token = current
        let kind: ExpressionKind
        switch token.kind {
        case .identifier(let name): advance(); kind = .identifier(name)
        case .type: return try typeUniverse()
        case .prop: advance(); kind = .universe(.prop)
        case .hole: advance(); kind = .hole
        case .number(let digits): advance(); kind = .number(digits)
        case .string(let value): advance(); kind = .string(value)
        case .bang, .binaryOp(.minus), .binaryOp(.plus):
            return try unary()
        case .leftParen:
            return try parenthesized()
        case .fun:
            return try lambda()
        case .leftBrace:
            return try blockExpression()
        case .match:
            return try matchExpression()
        default:
            let found = token.kind == .endOfFile ? "end of input" : token.lexeme.debugDescription
            throw failure("Expected an expression; found \(found).")
        }
        return try make(kind, from: token.span.start, to: token.span.end)
    }

    private mutating func unary() throws -> Expression {
        let token = advance()
        let operation: UnaryOperation = token.kind == .bang ? .not : (token.kind == .binaryOp(.minus) ? .negate : .positive)
        let operand = try expression(minPrecedence: 7)
        return try make(.unary(operation, operand), from: token.span.start, to: operand.span.end)
    }

    private mutating func parenthesized() throws -> Expression {
        let next = tokens[position + 1].kind
        switch next {
        case .identifier, .hole:
            if position + 2 < tokens.count, tokens[position + 2].kind == .colon {
                return try dependentFunction()
            }
        default: break
        }
        let start = advance().span.start
        let inner = try expression()
        let end = try expect(.rightParen, "')' after the expression").span.end
        return try make(inner.kind, from: start, to: end)
    }

    private mutating func dependentFunction() throws -> Expression {
        let start = current.span.start
        let binders = try parameters(open: .leftParen, close: .rightParen, allowEmpty: false)
        try expect(.arrow, "'->' after dependent function parameters")
        let result = try expression()
        return try make(.dependentFunction(parameters: binders, result: result), from: start, to: result.span.end)
    }

    private mutating func lambda() throws -> Expression {
        let start = advance().span.start
        let binders = try parameters(open: .leftParen, close: .rightParen)
        try expect(.fatArrow, "'=>' before the lambda body")
        let body = try expression()
        return try make(.lambda(parameters: binders, body: body), from: start, to: body.span.end)
    }

    private mutating func blockExpression() throws -> Expression {
        let value = try block()
        return try make(.block(value), from: value.span.start, to: value.span.end)
    }

    private mutating func typeUniverse() throws -> Expression {
        let token = advance()
        var level = 0
        if match(.leftParen) {
            guard case .number(let digits) = current.kind, let value = Int(digits), value >= 0 else {
                throw failure("Expected a nonnegative integer universe level representable by Int.")
            }
            level = value
            advance()
            try expect(.rightParen, "')' after the universe level")
        }
        return try make(.universe(.type(level: level)), from: token.span.start, to: previous.span.end)
    }

    private mutating func matchExpression() throws -> Expression {
        let start = advance().span.start
        let scrutinee = try expression()
        let motive = match(.return) ? try expression() : nil
        try expect(.leftBrace, "'{' before match branches")
        var cases: [MatchCase] = []
        while current.kind != .rightBrace {
            if current.kind == .endOfFile { throw failure("Expected '}' to close the match.") }
            cases.append(try matchCase())
        }
        let end = advance().span.end
        let span = SourceSpan(start: start, end: end)
        return try make(.match(MatchExpression(scrutinee: scrutinee, motive: motive,
                                               cases: cases, span: span)), from: start, to: end)
    }

    private mutating func matchCase() throws -> MatchCase {
        let pattern = try pattern()
        try expect(.fatArrow, "'=>' after the pattern")
        let body = try expression()
        if !match(.comma) { try terminator() }
        return MatchCase(pattern: pattern, body: body,
                         span: SourceSpan(start: pattern.span.start, end: previous.span.end))
    }

    private mutating func pattern(depth: Int = 1) throws -> Pattern {
        // Share the stack budget with enclosing expressions: a deeply nested
        // match plus a deep constructor pattern must not bypass the guard.
        guard recursionDepth + depth <= maxNesting else {
            throw failure("Pattern nesting exceeds the depth limit (\(maxNesting)).")
        }
        let token = current
        if match(.hole) { return Pattern(kind: .wildcard, span: token.span) }
        guard case .identifier(let constructorName) = token.kind else {
            throw failure("Expected a pattern: a name, constructor application, or '_'.")
        }
        advance()
        if !match(.leftParen) { return Pattern(kind: .name(constructorName), span: token.span) }
        let arguments = try patternArguments(depth: depth + 1)
        return Pattern(kind: .constructor(name: constructorName, arguments: arguments),
                       span: SourceSpan(start: token.span.start, end: previous.span.end))
    }

    private mutating func patternArguments(depth: Int) throws -> [Pattern] {
        var arguments: [Pattern] = []
        if match(.rightParen) { return arguments }
        while true {
            arguments.append(try pattern(depth: depth))
            if !match(.comma) { break }
            if current.kind == .rightParen { break }
        }
        try expect(.rightParen, "')' after constructor patterns")
        return arguments
    }
}
