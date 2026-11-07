import Foundation

public extension SourceSpan {
    /// Kaynak UTF-8 ofsetlerini UIKit/VS Code'un UTF-16 ofsetlerine çevirir.
    func utf16Range(in source: String) -> NSRange {
        var byteOffset = 0
        var utf16Offset = 0
        var lower = 0
        var upper = 0
        for scalar in source.unicodeScalars {
            if byteOffset <= start.utf8Offset { lower = utf16Offset }
            if byteOffset <= end.utf8Offset { upper = utf16Offset }
            byteOffset += scalar.utf8.count
            utf16Offset += scalar.utf16.count
        }
        if byteOffset <= start.utf8Offset { lower = utf16Offset }
        if byteOffset <= end.utf8Offset { upper = utf16Offset }
        return NSRange(location: lower, length: max(0, upper - lower))
    }
}

public struct RigorHighlight: Equatable, Sendable {
    public enum Kind: String, Sendable { case keyword, type, function, number, string, comment, `operator`, hole }
    public let kind: Kind
    public let range: NSRange
}

/// Eksik/hatalı kodu da renklendirir; ispat doğrulaması yapmaz.
public enum RigorHighlighter {
    public static func highlights(in source: String) -> [RigorHighlight] {
        let scalars = Array(source.unicodeScalars)
        var index = 0
        var offset = 0
        var result: [RigorHighlight] = []
        var declarationName: RigorHighlight.Kind?
        let keywords: Set<String> = ["theorem", "def", "axiom", "Gamma", "inductive", "match", "import", "let", "return", "fun", "func"]

        func peek(_ distance: Int = 0) -> Unicode.Scalar? {
            let target = index + distance
            return target < scalars.count ? scalars[target] : nil
        }
        func isNewline(_ value: Unicode.Scalar) -> Bool {
            (0x0A...0x0D).contains(value.value) || [0x85, 0x2028, 0x2029].contains(value.value)
        }
        func isDigit(_ value: Unicode.Scalar) -> Bool { (48...57).contains(value.value) }
        func advance() {
            offset += scalars[index].utf16.count
            index += 1
        }
        func emit(_ kind: RigorHighlight.Kind, from start: Int) {
            result.append(RigorHighlight(kind: kind, range: NSRange(location: start, length: offset - start)))
        }

        while let scalar = peek() {
            if scalar.properties.isWhitespace { advance(); continue }
            let start = offset
            if scalar == "/", peek(1) == "/" {
                while let value = peek(), !isNewline(value) { advance() }
                emit(.comment, from: start)
            } else if scalar == "/", peek(1) == "*" {
                advance(); advance()
                var depth = 1
                while peek() != nil, depth > 0 {
                    if peek() == "/", peek(1) == "*" { advance(); advance(); depth += 1 }
                    else if peek() == "*", peek(1) == "/" { advance(); advance(); depth -= 1 }
                    else { advance() }
                }
                emit(.comment, from: start)
            } else if scalar == "\"" {
                advance()
                while let value = peek(), !isNewline(value) {
                    advance()
                    if value == "\"" { break }
                    if value == "\\", let escaped = peek(), !isNewline(escaped) { advance() }
                }
                emit(.string, from: start)
                declarationName = nil
            } else if scalar == "_" || scalar.properties.isXIDStart {
                let first = index
                advance()
                while let value = peek(), value.properties.isXIDContinue { advance() }
                let name = String(String.UnicodeScalarView(scalars[first..<index]))
                if keywords.contains(name) {
                    emit(.keyword, from: start)
                    switch name {
                    case "theorem", "def", "axiom": declarationName = .function
                    case "inductive", "Gamma": declarationName = .type
                    default: declarationName = nil
                    }
                } else if name == "Type" || name == "Prop" {
                    emit(.type, from: start)
                    declarationName = nil
                } else if name == "_" {
                    emit(.hole, from: start)
                    declarationName = nil
                } else if let kind = declarationName {
                    emit(kind, from: start)
                    declarationName = nil
                }
            } else if isDigit(scalar) {
                while let value = peek(), isDigit(value) { advance() }
                emit(.number, from: start)
                declarationName = nil
            } else {
                advance()
                if "+-*/%^=!&|".unicodeScalars.contains(scalar) {
                    if let next = peek(), ["->", "=>", "==", "!=", "&&", "||"].contains(String(scalar) + String(next)) { advance() }
                    emit(.operator, from: start)
                }
                declarationName = nil
            }
        }
        return result
    }
}

public struct RigorLintPosition: Codable, Equatable, Sendable {
    public let line: Int
    public let character: Int

    init(utf16Offset: Int, source: String) {
        var line = 0
        var character = 0
        var wasCR = false
        // VS Code ayırıcı olarak CR, LF ve CRLF kullanır; scalar sütunu değildir.
        for unit in source.utf16.prefix(utf16Offset) {
            if unit == 13 { line += 1; character = 0 }
            else if unit == 10 { if !wasCR { line += 1 }; character = 0 }
            else { character += 1 }
            wasCR = unit == 13
        }
        self.line = line
        self.character = character
    }
}

public struct RigorLintRange: Codable, Equatable, Sendable {
    public let start: RigorLintPosition
    public let end: RigorLintPosition
}

public struct RigorLintDiagnostic: Codable, Sendable {
    public let fileName: String
    public let phase: String
    public let message: String
    public let range: RigorLintRange

    init(_ diagnostic: RigorDiagnostic, source: String) {
        fileName = diagnostic.fileName
        phase = diagnostic.phase.rawValue
        message = diagnostic.message
        let span = diagnostic.span.utf16Range(in: source)
        range = RigorLintRange(start: RigorLintPosition(utf16Offset: span.location, source: source),
                              end: RigorLintPosition(utf16Offset: NSMaxRange(span), source: source))
    }
}

public struct RigorLintReport: Codable, Sendable {
    public let diagnostics: [RigorLintDiagnostic]
    public let declarations: [String]
    public let axioms: [String]
}

public extension RigorChecker {
    /// Kaydedilmemiş ana dosyayı ve açık import taslaklarını disk dosyalarıyla birleştirir.
    static func lint(source: String, fileURL: URL, overlays: [String: String] = [:]) -> RigorLintReport {
        var sources = Dictionary(overlays.map { (URL(fileURLWithPath: $0.key), $0.value) }, uniquingKeysWith: { _, last in last })
        sources[fileURL] = source
        do {
            let report = try RigorLoader(kernel: Kernel()).checkFile(fileURL, sourceOverrides: sources)
            return RigorLintReport(diagnostics: [], declarations: report.declarations, axioms: report.axioms)
        } catch let error as RigorLoadError {
            let diagnostic = error.diagnostic ?? RigorDiagnostic(phase: .loader, message: error.description,
                                                                 span: .zero, fileName: fileURL.path)
            return RigorLintReport(diagnostics: [RigorLintDiagnostic(diagnostic, source: error.source ?? source)],
                                   declarations: [], axioms: [])
        } catch {
            let diagnostic = RigorDiagnostic(phase: .input, message: error.localizedDescription, span: .zero, fileName: fileURL.path)
            return RigorLintReport(diagnostics: [RigorLintDiagnostic(diagnostic, source: source)], declarations: [], axioms: [])
        }
    }
}
