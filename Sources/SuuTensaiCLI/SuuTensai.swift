import Foundation
import SuuTensai
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct SuuTensai {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--lsp" {
            guard arguments.count == 1 else { fail("--lsp accepts no additional arguments.") }
            do { try await RigorLanguageServer.run() }
            catch { fail("Rigor language server: \(error.localizedDescription)") }
            return
        }
        if arguments.first == "--lint-json" {
            guard arguments.count == 1 else { fail("--lint-json reads a JSON request from stdin; no other arguments are accepted.") }
            struct Request: Decodable {
                let filePath: String
                let source: String
                let overlays: [String: String]?
            }
            do {
                let request = try JSONDecoder().decode(Request.self, from: FileHandle.standardInput.readDataToEndOfFile())
                let report = RigorChecker.lint(source: request.source, fileURL: URL(fileURLWithPath: request.filePath),
                                              overlays: request.overlays ?? [:])
                let output = try JSONEncoder().encode(report)
                FileHandle.standardOutput.write(output + Data([10]))
            } catch { fail("Invalid lint request: \(error.localizedDescription)") }
            return
        }
        if arguments.contains("--help") || arguments.contains("-h") {
            print("Usage: SuuTensai [--ast | --tokens | --parse-only | --check] [file.rigor | -]")
            print("Default: check types/proofs and load imports relative to each file.")
            print("No file: check the built-in example. '-' reads UTF-8 from stdin.")
            print("--ast, --tokens and --parse-only inspect syntax without checking proofs.")
            print("--lint-json reads {filePath, source, overlays?} from stdin and writes editor diagnostics as JSON.")
            print("--lsp runs the persistent language server over stdin/stdout.")
            return
        }
        // Normal çalıştırma: kaynak -> lexer -> parser -> kernel.
        // Sadece sözdizimini görmek isteyen kişi --ast/--tokens/--parse-only
        // seçer. Bayrak verilmemesi ispat kontrolünü atlamamalı.
        var mode = "--check"
        var path: String?
        for argument in arguments {
            if ["--ast", "--tokens", "--parse-only", "--check"].contains(argument) {
                mode = argument
            } else if argument.hasPrefix("-") && argument != "-" {
                fail("Unknown option: \(argument)")
            } else if path == nil {
                path = argument
            } else {
                fail("Expected at most one input file.")
            }
        }

        var source = ""
        let fileName = path ?? "<example>"
        do {
            if mode == "--check", let path, path != "-" {
                // Loader her dosyayı parse eder, import'ları aynı kernel
                // ortamına yükler ve bütün bildirimleri kontrol ettirir.
                let report = try RigorChecker.checkFile(URL(fileURLWithPath: path))
                printReport(report)
                return
            }
            if path == "-" {
                let data = FileHandle.standardInput.readDataToEndOfFile()
                guard let decoded = String(data: data, encoding: .utf8) else { fail("Input is not valid UTF-8.") }
                source = decoded
            } else if let path {
                source = try String(contentsOfFile: path, encoding: .utf8)
            } else {
                source = """
                theorem reflexivity<A: Type>(x: A) -> A {
                    return x
                }
                """
            }
            let tokens = try Lexer(source).tokenize()
            if mode == "--tokens" {
                for token in tokens { print(token) }
                return
            }
            let program = try Parser(tokens: tokens).parse()
            if mode == "--parse-only" {
                print("Parsed \(program.declarations.count) declarations (syntax only).")
            } else if mode == "--check" {
                // Stdin ve yerleşik örnek de AST oluştuktan sonra kernel'den
                // geçer. Bu yolda import için bir dosya tabanı bulunmaz.
                printReport(try RigorChecker.checkProgram(program))
            } else {
                print(program.astDescription)
            }
        } catch let error as FrontendError {
            fail(error.render(source: source, fileName: fileName))
        } catch let error as KernelError {
            fail(error.render(source: source, fileName: fileName))
        } catch let error as RigorLoadError {
            fail(error.description)
        } catch {
            fail("\(fileName): \(error.localizedDescription)")
        }
    }

    static func printReport(_ report: KernelReport) {
        print("Checked \(report.declarations.count) declarations: \(report.declarations.joined(separator: ", ")).")
        if report.axioms.isEmpty { print("Axiom dependencies: none.") }
        else { print("Axiom dependencies: \(report.axioms.joined(separator: ", ")).") }
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}
