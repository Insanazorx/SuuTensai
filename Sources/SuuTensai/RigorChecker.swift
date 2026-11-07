import Foundation

/// UI'ya yalnızca değerler döner; her kontrol kendi kernel ortamını kurar.
public struct RigorDiagnostic: Equatable, Sendable {
    public enum Phase: String, Sendable { case lexer, parser, kernel, loader, input }
    public let phase: Phase
    public let message: String
    public let span: SourceSpan
    public let fileName: String
}

public struct RigorCheckResult: Sendable {
    public enum Status: Sendable { case valid, invalid, empty, cancelled }
    public let status: Status
    public let declarations: [String]
    public let axioms: [String]
    public let diagnostic: RigorDiagnostic?
}

public enum RigorChecker {
    /// Telefon editörü için sınırlandırılmış, dosya sisteminden bağımsız API.
    /// Import'lar yalnızca çağıranın açıkça sağladığı kaynaklardan yüklenir.
    public static let maximumSourceBytes = 256 * 1_024

    public static func check(
        _ source: String,
        fileName: String = "Taslak.rigor",
        imports: [String: String] = [:]
    ) -> RigorCheckResult {
        let kernel = Kernel()
        var loaded: Set<String> = []
        var active: Set<String> = []
        var names: [String] = []
        var axioms: Set<String> = []
        var totalBytes = 0

        func reject(_ message: String, phase: RigorDiagnostic.Phase,
                    span: SourceSpan = .zero, file: String) -> RigorDiagnostic {
            RigorDiagnostic(phase: phase, message: message, span: span, fileName: file)
        }

        func visit(_ text: String, name: String) throws -> RigorDiagnostic? {
            try Task.checkCancellation()
            totalBytes += text.utf8.count
            guard text.utf8.count <= maximumSourceBytes, totalBytes <= maximumSourceBytes * 4 else {
                return reject("Kaynak boyutu sınırı aşıldı (dosya başına 256 KB).", phase: .input, file: name)
            }
            active.insert(name)
            defer { active.remove(name) }
            do {
                let program = try Parser(source: text).parse()
                for declaration in program.declarations {
                    try Task.checkCancellation()
                    if case .import(let imported) = declaration {
                        if active.contains(imported.path) {
                            return reject("Import döngüsü: \(imported.path)", phase: .loader,
                                          span: imported.span, file: name)
                        }
                        if loaded.contains(imported.path) { continue }
                        guard active.count < 32, loaded.count < 256 else {
                            return reject("Import derinlik/dosya sayısı sınırı aşıldı.", phase: .loader,
                                          span: imported.span, file: name)
                        }
                        guard let dependency = imports[imported.path] else {
                            return reject("'\(imported.path)' bulunamadı. Bu editörde yalnızca yerleşik dosyalar kullanılabilir.",
                                          phase: .loader, span: imported.span, file: name)
                        }
                        if let diagnostic = try visit(dependency, name: imported.path) { return diagnostic }
                    } else {
                        let report = try kernel.check(Program(declarations: [declaration], span: declaration.span))
                        names.append(contentsOf: report.declarations)
                        axioms.formUnion(report.axioms)
                    }
                }
                loaded.insert(name)
            } catch let error as FrontendError {
                return reject(error.message, phase: error.phase == .lexer ? .lexer : .parser,
                              span: error.span, file: name)
            } catch let error as KernelError {
                return reject(error.message, phase: .kernel, span: error.span, file: name)
            }
            return nil
        }

        do {
            if let diagnostic = try visit(source, name: fileName) {
                return RigorCheckResult(status: .invalid, declarations: [], axioms: [], diagnostic: diagnostic)
            }
            return RigorCheckResult(status: names.isEmpty ? .empty : .valid,
                                    declarations: names, axioms: axioms.sorted(), diagnostic: nil)
        } catch is CancellationError {
            return RigorCheckResult(status: .cancelled, declarations: [], axioms: [], diagnostic: nil)
        } catch {
            return RigorCheckResult(status: .invalid, declarations: [], axioms: [],
                                    diagnostic: reject(error.localizedDescription, phase: .input, file: fileName))
        }
    }

    /// CLI'nin mevcut dosya/import ve sınırsız kaynak davranışını korur.
    public static func checkFile(_ url: URL) throws -> KernelReport {
        try RigorLoader(kernel: Kernel()).checkFile(url)
    }

    public static func checkProgram(_ program: Program) throws -> KernelReport {
        try Kernel().check(program)
    }
}
