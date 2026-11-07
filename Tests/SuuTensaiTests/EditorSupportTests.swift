import Foundation
import Testing
@testable import SuuTensai

@Suite struct EditorSupportTests {
    @Test func highlighterHandlesIncompleteCodeNestedCommentsAndEscapes() {
        let source = """
        /* outer /* theorem */ still comment */
        theorem özdeşlik<A: Type>(x: A) -> A {
            // return \"hi\"
            let s = "a\\\"b"
            return _
        }
        "unfinished
        """
        let tokens = RigorHighlighter.highlights(in: source)
        func texts(_ kind: RigorHighlight.Kind) -> [String] {
            tokens.filter { $0.kind == kind }.map { (source as NSString).substring(with: $0.range) }
        }
        #expect(texts(.comment) == ["/* outer /* theorem */ still comment */", "// return \"hi\""])
        #expect(texts(.keyword) == ["theorem", "let", "return"])
        #expect(texts(.function) == ["özdeşlik"])
        #expect(texts(.type) == ["Type"])
        #expect(texts(.hole) == ["_"])
        #expect(texts(.string) == ["\"a\\\"b\"", "\"unfinished"])
    }

    @Test func highlighterPreservesUnicodeBoundariesAndUTF16Ranges() {
        let source = "// 🧠\ninductive Doğal: Type { zero: Doğal; }\nlet Type2 = 123; let theoremα = _name;"
        let tokens = RigorHighlighter.highlights(in: source)
        let substrings = tokens.map { (source as NSString).substring(with: $0.range) }
        #expect(substrings.contains("Doğal"))
        #expect(!substrings.contains("theorem"))
        #expect(!substrings.contains("_"))
        #expect(substrings.filter { $0 == "Type" }.count == 1)
        #expect(tokens.first?.range.length == 5) // // + space + surrogate pair + no newline
        #expect(tokens.allSatisfy { NSMaxRange($0.range) <= (source as NSString).length })
    }

    @Test func desktopLintUsesUnsavedRootAndRelativeImportOverlays() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rigor-editor-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = folder.appendingPathComponent("main.rigor")
        let dependency = folder.appendingPathComponent("Base.rigor")
        try "theorem broken(".write(to: root, atomically: true, encoding: .utf8)
        try "theorem broken(".write(to: dependency, atomically: true, encoding: .utf8)
        let source = "import \"Base.rigor\"; theorem use<A:Type>(x:A)->A { identity<A>(x) }"
        let valid = RigorChecker.lint(source: source, fileURL: root,
            overlays: [dependency.path: "def identity<A:Type>(x:A)->A { x }"])
        #expect(valid.diagnostics.isEmpty)
        #expect(valid.declarations == ["identity", "use"])
        let invalid = RigorChecker.lint(source: source, fileURL: root)
        #expect(invalid.diagnostics.first?.fileName == dependency.resolvingSymlinksInPath().path)
        #expect(invalid.diagnostics.first?.phase == "parser")
        let missing = RigorChecker.lint(source: "import \"Missing.rigor\";", fileURL: root)
        #expect(missing.diagnostics.first?.fileName == root.resolvingSymlinksInPath().path)
        #expect(missing.diagnostics.first?.phase == "loader")
    }

    @Test func lintRangesUseUTF16AndEditorLineEndings() {
        let source = "/* 🧠 */ theorem bad<A:Type>(x:A)->A { eksik }"
        let report = RigorChecker.lint(source: source, fileURL: URL(fileURLWithPath: "/tmp/unsaved.rigor"))
        let expected = (source as NSString).range(of: "eksik")
        #expect(report.diagnostics.first?.range.start.line == 0)
        #expect(report.diagnostics.first?.range.start.character == expected.location)
        #expect(report.diagnostics.first?.range.end.character == NSMaxRange(expected))
        let crlf = RigorChecker.lint(source: "// 🧠\r\ntheorem bad(", fileURL: URL(fileURLWithPath: "/tmp/unsaved.rigor"))
        #expect(crlf.diagnostics.first?.range.start.line == 1)
        #expect(crlf.diagnostics.first?.range.start.character == 12)
    }

    @Test func lintJSONRoundTripsWithNoHumanOutput() throws {
        let report = RigorChecker.lint(source: "theorem identity<A:Type>(x:A)->A { x }", fileURL: URL(fileURLWithPath: "/tmp/unsaved.rigor"))
        let decoded = try JSONDecoder().decode(RigorLintReport.self, from: JSONEncoder().encode(report))
        #expect(decoded.diagnostics.isEmpty)
        #expect(decoded.declarations == ["identity"])
    }
}
