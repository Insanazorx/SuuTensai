import Foundation
import SuuTensai

/// Aynı EditorModel kaynağını UI'dan bağımsız çalıştıran entegrasyon kontrolü.
@main
struct EditorSmoke {
    @MainActor
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let scratch = root.appendingPathComponent(".build/editor-smoke-draft", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let draft = scratch.appendingPathComponent(UUID().uuidString + ".rigor")
        defer { try? FileManager.default.removeItem(at: draft) }
        let fundamentals = try String(contentsOf: root.appendingPathComponent("Fundamentals.rigor"), encoding: .utf8)
        let imports = ["Fundamentals.rigor": fundamentals]
        let model = EditorModel(draftURL: draft, imports: imports)
        try await waitForResult(model)
        precondition(model.result?.status == .valid, "Başlangıç örneği doğrulanmalı")

        model.source = "// 🧠\ntheorem bad<A:Type>(x:A)->A { eksik }"
        precondition(model.result == nil, "Yeni metinde eski başarı sonucu temizlenmeli")
        try await waitForResult(model)
        precondition(model.result?.diagnostic?.phase == .kernel)
        model.goToDiagnostic()
        precondition(model.navigationRequest?.span.start.line == 2)

        // Hızlı yazmada iptal edilen kontrol yeni sonucu değiştirmemeli.
        for index in 0..<30 {
            model.source = "theorem draft\(index)<A:Type>(x:A)->A { x }"
            model.checkNow()
        }
        try await waitForResult(model)
        precondition(model.result?.declarations == ["draft29"])
        try await Task.sleep(for: .milliseconds(550))
        let saved = try String(contentsOf: draft, encoding: .utf8)
        precondition(saved == model.source,
                     "Taslak otomatik kaydedilmeli")
        let restored = EditorModel(draftURL: draft, imports: imports)
        precondition(restored.source == model.source, "Yeniden açılış taslağı geri yüklemeli")

        let unreadableDraft = scratch.appendingPathComponent(UUID().uuidString + ".rigor")
        defer { try? FileManager.default.removeItem(at: unreadableDraft) }
        let invalidUTF8 = Data([0xFF, 0xFE])
        try invalidUTF8.write(to: unreadableDraft)
        let unreadable = EditorModel(draftURL: unreadableDraft, imports: imports)
        precondition(unreadable.storageError != nil)
        unreadable.saveNow()
        let preserved = try Data(contentsOf: unreadableDraft)
        precondition(preserved == invalidUTF8, "Okunamayan taslak otomatik kayıtta ezilmemeli")

        for example in EditorModel.examples {
            model.source = example.source
            model.checkNow()
            try await waitForResult(model)
            precondition(model.result?.status == .valid, "Yerleşik örnek doğrulanmalı: \(example.name)")
        }
        model.source = "// boş taslak"
        model.checkNow()
        try await waitForResult(model)
        precondition(model.result?.status == .empty, "Boş kaynak ispat gibi sunulmamalı")
        model.saveNow()
        print("Editör entegrasyonu geçti: canlı kontrol, hata konumu, hızlı düzenleme, otomatik kayıt, geri yükleme ve 3 örnek.")
    }

    @MainActor
    private static func waitForResult(_ model: EditorModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while model.result == nil {
            guard ContinuousClock.now < deadline else { throw Timeout() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private struct Timeout: Error {}
}
