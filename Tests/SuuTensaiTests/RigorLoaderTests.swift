import Foundation
import Testing
@testable import SuuTensai

@Suite struct RigorLoaderTests {
    // Her test kendi dizinini kullanır; paralel testler birbirine dokunmaz.
    private func inTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rigor-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    private func write(_ source: String, _ file: String, in folder: URL) throws {
        try source.write(to: folder.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }

    @Test func diamondImportsLoadEachFileOnce() throws {
        try inTemporaryDirectory { folder in
            try write("inductive Unit:Type {unit:Unit;}", "base.rigor", in: folder)
            try write("import \"base.rigor\"; def a()->Unit {unit}", "a.rigor", in: folder)
            try write("import \"base.rigor\"; def b()->Unit {unit}", "b.rigor", in: folder)
            try write("import \"a.rigor\"; import \"b.rigor\"; theorem t()->Unit {a()}", "main.rigor", in: folder)
            let kernel = Kernel()
            let report = try RigorLoader(kernel: kernel).checkFile(folder.appendingPathComponent("main.rigor"))
            #expect(report.declarations == ["Unit", "a", "b", "t"])
            #expect(report.axioms.isEmpty)
        }
    }

    @Test func cyclesMissingImportsAndInvalidImportedProofsRollBack() throws {
        try inTemporaryDirectory { folder in
            try write("import \"b.rigor\";", "a.rigor", in: folder)
            try write("import \"a.rigor\";", "b.rigor", in: folder)
            let kernel = Kernel()
            #expect(throws: RigorLoadError.self) { try RigorLoader(kernel: kernel).checkFile(folder.appendingPathComponent("a.rigor")) }
            #expect(kernel.globals.isEmpty)
            try write("inductive Unit:Type {unit:Unit;} import \"missing.rigor\";", "a.rigor", in: folder)
            #expect(throws: RigorLoadError.self) { try RigorLoader(kernel: kernel).checkFile(folder.appendingPathComponent("a.rigor")) }
            #expect(kernel.globals.isEmpty)
            try write("theorem bad()->Type {unknown}", "bad.rigor", in: folder)
            try write("inductive Unit:Type {unit:Unit;} import \"bad.rigor\";", "a.rigor", in: folder)
            do {
                try RigorLoader(kernel: kernel).checkFile(folder.appendingPathComponent("a.rigor"))
                Issue.record("Expected invalid imported proof")
            } catch let error as RigorLoadError {
                #expect(error.description.contains("bad.rigor:1:"))
                #expect(error.description.contains("kernel:"))
                #expect(error.description.contains("^"))
            }
            #expect(kernel.globals.isEmpty)
            #expect(kernel.families.isEmpty)
        }
    }
}
