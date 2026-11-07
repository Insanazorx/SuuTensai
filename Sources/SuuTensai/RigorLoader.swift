import Foundation

/// Dosya yükleme mantıksal çekirdeğin dışında. Kernel bir dosya yoluna güvenip
/// onu doğrulanmış kabul etmez; loader her dosyayı parse edip kernel'e verir.
public struct RigorLoadError: Error, CustomStringConvertible {
    public let description: String
    let diagnostic: RigorDiagnostic?
    let source: String?

    init(description: String, diagnostic: RigorDiagnostic? = nil, source: String? = nil) {
        self.description = description
        self.diagnostic = diagnostic
        self.source = source
    }
}

final class RigorLoader {
    let kernel: Kernel
    init(kernel: Kernel) { self.kernel = kernel }

    @discardableResult
    func checkFile(_ url: URL, sourceOverrides: [URL: String] = [:]) throws -> KernelReport {
        let sources = Dictionary(sourceOverrides.map {
            ($0.key.standardizedFileURL.resolvingSymlinksInPath(), $0.value)
        }, uniquingKeysWith: { _, last in last })
        var loaded: Set<URL> = []
        var active: Set<URL> = []
        var names: [String] = []
        var axioms: Set<String> = []

        func visit(_ input: URL) throws {
            try Task.checkCancellation()
            let file = input.standardizedFileURL.resolvingSymlinksInPath()
            if active.contains(file) {
                throw RigorLoadError(description: "Import döngüsü: \(file.path)")
            }
            if loaded.contains(file) { return } // Diamond import aynı dosyayı bir kez yükler.
            guard active.count < 32, loaded.count < 256 else {
                throw RigorLoadError(description: "Import derinlik/dosya sayısı sınırı aşıldı.")
            }
            let source: String
            do { source = try sources[file] ?? String(contentsOf: file, encoding: .utf8) }
            catch { throw RigorLoadError(description: "\(file.path): dosya okunamadı: \(error.localizedDescription)") }
            active.insert(file)
            defer { active.remove(file) }
            do {
                let program = try Parser(source: source).parse()
                for declaration in program.declarations {
                    try Task.checkCancellation()
                    if case .import(let imported) = declaration {
                        let target = file.deletingLastPathComponent().appendingPathComponent(imported.path)
                        do { try visit(target) }
                        catch let error as RigorLoadError {
                            let diagnostic = error.diagnostic ?? RigorDiagnostic(
                                phase: .loader, message: error.description, span: imported.span, fileName: file.path)
                            throw RigorLoadError(description: "\(file.path):\(imported.span.start.line): import \(imported.path):\n\(error)",
                                                 diagnostic: diagnostic, source: error.source ?? source)
                        }
                    } else {
                        let report = try kernel.check(Program(declarations: [declaration], span: declaration.span))
                        names.append(contentsOf: report.declarations)
                        axioms.formUnion(report.axioms)
                    }
                }
            } catch let error as FrontendError {
                throw RigorLoadError(description: error.render(source: source, fileName: file.path),
                                     diagnostic: RigorDiagnostic(phase: error.phase == .lexer ? .lexer : .parser,
                                         message: error.message, span: error.span, fileName: file.path), source: source)
            } catch let error as KernelError {
                throw RigorLoadError(description: error.render(source: source, fileName: file.path),
                                     diagnostic: RigorDiagnostic(phase: .kernel, message: error.message,
                                         span: error.span, fileName: file.path), source: source)
            }
            loaded.insert(file)
        }

        return try kernel.transaction {
            try visit(url)
            return KernelReport(declarations: names, axioms: axioms.sorted())
        }
    }
}
