/// A single forward scan. No regex compilation or copying the remaining input
/// per token, so large files and long comments stay linear in source length.
public struct Lexer {
    private let input: String

    public init(_ input: String) { self.input = input }

    /// A fresh scanner makes repeated calls deterministic, including after errors.
    public func tokenize() throws -> [Token] {
        var scanner = Scanner(input)
        return try scanner.scan()
    }
}

private struct Scanner {
    let scalars: [Unicode.Scalar]
    var index = 0
    var offset = 0
    var line = 1
    var column = 1
    var previousWasCR = false
    var lineBreakSeen = false

    init(_ input: String) { scalars = Array(input.unicodeScalars) }

    var position: SourcePosition {
        SourcePosition(utf8Offset: offset, line: line, column: column)
    }

    func peek(_ distance: Int = 0) -> Unicode.Scalar? {
        let next = index + distance
        return next < scalars.count ? scalars[next] : nil
    }

    func isNewline(_ scalar: Unicode.Scalar) -> Bool {
        // Keep this consistent with Character.isNewline used by diagnostics.
        switch scalar.value {
        case 0x0A...0x0D, 0x85, 0x2028, 0x2029: true
        default: false
        }
    }

    @discardableResult
    mutating func advance() -> Unicode.Scalar? {
        guard let scalar = peek() else { return nil }
        index += 1
        offset += scalar.utf8.count
        if isNewline(scalar) {
            if scalar != "\n" || !previousWasCR { line += 1 }
            column = 1
            lineBreakSeen = true
        } else {
            column += 1
        }
        previousWasCR = scalar == "\r"
        return scalar
    }

    func text(from start: Int) -> String {
        String(String.UnicodeScalarView(scalars[start..<index]))
    }

    func error(_ message: String, from start: SourcePosition) -> FrontendError {
        FrontendError(phase: .lexer, message: message, span: SourceSpan(start: start, end: position))
    }

    func isDigit(_ scalar: Unicode.Scalar) -> Bool { scalar >= "0" && scalar <= "9" }
    func isIdentifierStart(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || scalar.properties.isXIDStart
    }

    mutating func skipTrivia() throws {
        while let scalar = peek() {
            if scalar.properties.isWhitespace {
                advance()
            } else if scalar == "/", peek(1) == "/" {
                advance(); advance()
                while let next = peek(), !isNewline(next) { advance() }
            } else if scalar == "/", peek(1) == "*" {
                let start = position
                advance(); advance()
                var depth = 1
                while depth > 0 {
                    guard peek() != nil else { throw error("Unterminated block comment; expected '*/'.", from: start) }
                    if peek() == "/", peek(1) == "*" {
                        advance(); advance(); depth += 1
                    } else if peek() == "*", peek(1) == "/" {
                        advance(); advance(); depth -= 1
                    } else {
                        advance()
                    }
                }
            } else {
                break
            }
        }
    }

    mutating func scan() throws -> [Token] {
        var tokens: [Token] = []
        while true {
            if tokens.count.isMultiple(of: 256) { try Task.checkCancellation() }
            try skipTrivia()
            let start = position
            let startIndex = index
            let precededByLineBreak = lineBreakSeen
            lineBreakSeen = false
            guard let scalar = peek() else {
                tokens.append(Token(kind: .endOfFile, lexeme: "", span: SourceSpan(start: start, end: start),
                                    isPrecededByLineBreak: precededByLineBreak))
                return tokens
            }

            let kind: TokenKind
            if isIdentifierStart(scalar) {
                advance()
                while let next = peek(), next.properties.isXIDContinue { advance() }
                let name = text(from: startIndex)
                kind = keyword(name) ?? .identifier(name)
            } else if isDigit(scalar) {
                while let next = peek(), isDigit(next) { advance() }
                if let next = peek(), isIdentifierStart(next) {
                    throw error("Expected a separator after the number.", from: start)
                }
                kind = .number(text(from: startIndex))
            } else if scalar == "\"" {
                kind = .string(try scanString())
            } else {
                advance()
                switch scalar {
                case "(": kind = .leftParen
                case ")": kind = .rightParen
                case "{": kind = .leftBrace
                case "}": kind = .rightBrace
                case "<": kind = .leftAngle
                case ">": kind = .rightAngle
                case ":": kind = .colon
                case ",": kind = .comma
                case ";": kind = .semicolon
                case "+": kind = .binaryOp(.plus)
                case "-":
                    if peek() == ">" { advance(); kind = .arrow }
                    else { kind = .binaryOp(.minus) }
                case "*": kind = .binaryOp(.multiply)
                case "/": kind = .binaryOp(.divide)
                case "%": kind = .binaryOp(.remainder)
                case "^": kind = .binaryOp(.power)
                case "=":
                    if peek() == "=" { advance(); kind = .binaryOp(.equal) }
                    else if peek() == ">" { advance(); kind = .fatArrow }
                    else { kind = .assign }
                case "!":
                    if peek() == "=" { advance(); kind = .binaryOp(.notEqual) }
                    else { kind = .bang }
                case "&" where peek() == "&": advance(); kind = .binaryOp(.logicalAnd)
                case "|" where peek() == "|": advance(); kind = .binaryOp(.logicalOr)
                default: throw error("Unexpected character '\(scalar)'.", from: start)
                }
            }
            tokens.append(Token(kind: kind, lexeme: text(from: startIndex),
                                span: SourceSpan(start: start, end: position),
                                isPrecededByLineBreak: precededByLineBreak))
        }
    }

    func keyword(_ name: String) -> TokenKind? {
        switch name {
        case "theorem": .theorem
        case "def": .definition
        case "axiom": .axiom
        case "Gamma": .gamma
        case "inductive": .inductive
        case "match": .match
        case "import": .import
        case "let": .let
        case "return": .return
        case "fun", "func": .fun
        case "Type": .type
        case "Prop": .prop
        case "_": .hole
        default: nil
        }
    }

    mutating func scanString() throws -> String {
        let start = position
        advance() // opening quote
        var value = String.UnicodeScalarView()
        while let scalar = peek() {
            if scalar == "\"" { advance(); return String(value) }
            if isNewline(scalar) { throw error("Unescaped newline in string literal.", from: start) }
            advance()
            if scalar != "\\" { value.append(scalar); continue }
            guard let escape = peek() else { throw error("Unterminated string escape.", from: start) }
            advance()
            switch escape {
            case "\"": value.append("\"")
            case "\\": value.append("\\")
            case "n": value.append("\n")
            case "r": value.append("\r")
            case "t": value.append("\t")
            case "0": value.append("\0")
            case "u":
                guard peek() == "{" else { throw error("Expected '{' after '\\u'.", from: start) }
                advance()
                var codePoint: UInt32 = 0
                var digits = 0
                while let next = peek(), next != "}" {
                    let digit: UInt32
                    switch next.value {
                    case 48...57: digit = next.value - 48
                    case 65...70: digit = next.value - 65 + 10
                    case 97...102: digit = next.value - 97 + 10
                    default: throw error("Invalid hexadecimal digit in Unicode escape.", from: start)
                    }
                    guard digits < 6 else { throw error("Unicode escape has more than six digits.", from: start) }
                    codePoint = codePoint * 16 + digit
                    digits += 1
                    advance()
                }
                guard peek() == "}", digits > 0, let decoded = Unicode.Scalar(codePoint) else {
                    throw error("Invalid or unterminated Unicode escape.", from: start)
                }
                advance()
                value.append(decoded)
            default: throw error("Unknown string escape '\\\(escape)'.", from: start)
            }
        }
        throw error("Unterminated string literal; expected '\"'.", from: start)
    }
}
