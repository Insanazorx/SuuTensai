/// Offsets are UTF-8 bytes; lines and Unicode-scalar columns are one-based.
public struct SourcePosition: Equatable, Sendable {
    public let utf8Offset: Int
    public let line: Int
    public let column: Int
}

/// Half-open range: start is included, end is excluded.
public struct SourceSpan: Equatable, Sendable {
    public let start: SourcePosition
    public let end: SourcePosition

    public static let zero = SourceSpan(
        start: SourcePosition(utf8Offset: 0, line: 1, column: 1),
        end: SourcePosition(utf8Offset: 0, line: 1, column: 1)
    )
}

public enum BinaryOperation: String, Equatable, Sendable {
    case equal = "==", notEqual = "!="
    case logicalAnd = "&&", logicalOr = "||"
    case plus = "+", minus = "-", multiply = "*", divide = "/"
    case remainder = "%", power = "^"

    /// Larger numbers bind more tightly. The function arrow has precedence 1.
    var precedence: Int {
        switch self {
        case .logicalOr: 2
        case .logicalAnd: 3
        case .equal, .notEqual: 4
        case .plus, .minus: 5
        case .multiply, .divide, .remainder: 6
        case .power: 8
        }
    }
}

public enum UnaryOperation: String, Equatable, Sendable {
    case not = "!", negate = "-", positive = "+"
}

public enum TokenKind: Equatable, Sendable {
    case identifier(String)
    /// Preserve digits exactly: the frontend does not choose a numeric domain.
    case number(String)
    /// Decoded contents, without quotes. Token.lexeme retains the source text.
    case string(String)
    case theorem, definition, axiom, gamma
    case inductive, match, `import`
    case `return`, `let`, fun, type, prop, hole
    case binaryOp(BinaryOperation)
    case bang, assign, arrow, fatArrow
    case leftAngle, rightAngle
    case leftParen, rightParen, leftBrace, rightBrace
    case semicolon, colon, comma
    case endOfFile
}

public struct Token: Equatable, Sendable, CustomStringConvertible {
    public let kind: TokenKind
    public let lexeme: String
    public let span: SourceSpan
    public let isPrecededByLineBreak: Bool

    public init(
        kind: TokenKind, lexeme: String, span: SourceSpan = .zero,
        isPrecededByLineBreak: Bool = false
    ) {
        self.kind = kind
        self.lexeme = lexeme
        self.span = span
        self.isPrecededByLineBreak = isPrecededByLineBreak
    }

    public var description: String {
        "\(span.start.line):\(span.start.column) \(kind) \(lexeme.debugDescription)"
    }
}

/// All source errors are values; malformed input must never call fatalError.
public struct FrontendError: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Phase: String, Sendable { case lexer, parser }
    public let phase: Phase
    public let message: String
    public let span: SourceSpan

    public var description: String {
        "\(span.start.line):\(span.start.column): \(phase.rawValue): \(message)"
    }

    public func render(source: String, fileName: String = "<input>") -> String {
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let index = span.start.line - 1
        guard lines.indices.contains(index) else { return "\(fileName):\(description)" }
        let line = String(lines[index])
        let indent = line.unicodeScalars.prefix(span.start.column - 1)
            .map { $0 == "\t" ? "\t" : " " }.joined()
        return "\(fileName):\(description)\n\(line)\n\(indent)^"
    }
}
