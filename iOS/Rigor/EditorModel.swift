import Foundation
import Combine
import SuuTensai

private actor CheckerWorker {
    func check(_ source: String, imports: [String: String]) -> RigorCheckResult {
        RigorChecker.check(source, imports: imports)
    }
}

@MainActor
final class EditorModel: ObservableObject {
    enum Phase { case waiting, checking, finished }
    static let starter = """
    // İlk ispatın: verilen x'i geri döndür.
    theorem identity<A: Type>(x: A) -> A {
        return x
    }
    """
    static let examples: [(name: String, source: String)] = [
        ("Özdeşlik", starter),
        ("Modus ponens", """
        theorem modusPonens<P: Prop, Q: Prop>(
            p: P, implication: P -> Q
        ) -> Q {
            return implication(p)
        }
        """),
        ("Eşitlik", """
        import "Fundamentals.rigor";

        theorem reflexivity<A: Type>(x: A) -> Id<A>(x, x) {
            return refl<A>(x)
        }
        """),
    ]

    @Published var source: String {
        didSet {
            guard source != oldValue else { return }
            canWriteDraft = true
            saveMessage = "Kaydediliyor…"
            scheduleSave()
            scheduleCheck()
        }
    }
    @Published private(set) var result: RigorCheckResult?
    @Published private(set) var phase = Phase.waiting
    @Published private(set) var saveMessage = "Taslak kaydedildi"
    @Published var storageError: String?
    @Published private(set) var elapsedMilliseconds = 0
    @Published var navigationRequest: EditorNavigation?

    private let worker = CheckerWorker()
    private let draftURL: URL
    private let imports: [String: String]
    private var revision = 0
    private var canWriteDraft = true
    private var checkTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    init(draftURL: URL? = nil, imports: [String: String]? = nil) {
        var resolvedDraftURL = draftURL ?? URL.applicationSupportDirectory
            .appendingPathComponent("Rigor", isDirectory: true)
            .appendingPathComponent("Taslak.rigor")
        #if DEBUG
        let testing = draftURL == nil && ProcessInfo.processInfo.arguments.contains("--ui-testing")
        if testing {
            resolvedDraftURL = FileManager.default.temporaryDirectory.appendingPathComponent("RigorUITest-\(UUID().uuidString).rigor")
        }
        #endif
        self.draftURL = resolvedDraftURL
        var initial = Self.starter
        #if DEBUG
        if testing { initial = ProcessInfo.processInfo.environment["RIGOR_TEST_SOURCE"] ?? Self.starter }
        #endif
        var loadError: String?
        if FileManager.default.fileExists(atPath: self.draftURL.path) {
            do { initial = try String(contentsOf: self.draftURL, encoding: .utf8) }
            catch { loadError = "Taslak açılamadı: \(error.localizedDescription)" }
        }
        source = initial
        if let imports {
            self.imports = imports
        } else if let url = Bundle.main.url(forResource: "Fundamentals", withExtension: "rigor"),
           let fundamentals = try? String(contentsOf: url, encoding: .utf8) {
            self.imports = ["Fundamentals.rigor": fundamentals]
        } else {
            self.imports = [:]
        }
        storageError = loadError
        canWriteDraft = loadError == nil
        if loadError != nil { saveMessage = "Taslak açılamadı" }
        scheduleCheck()
    }

    func checkNow() { scheduleCheck(delay: 0) }

    func goToDiagnostic() {
        guard let diagnostic = result?.diagnostic, diagnostic.fileName == "Taslak.rigor" else { return }
        navigationRequest = EditorNavigation(span: diagnostic.span)
    }

    func saveNow() {
        saveTask?.cancel()
        // Okunamayan mevcut dosyayı yalnızca uygulama pasifleşti diye ezme.
        guard canWriteDraft else { return }
        do {
            try FileManager.default.createDirectory(at: draftURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try source.write(to: draftURL, atomically: true, encoding: .utf8)
            saveMessage = "Taslak kaydedildi"
            storageError = nil
        } catch {
            saveMessage = "Kaydedilemedi"
            storageError = "Taslak kaydedilemedi: \(error.localizedDescription)"
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            self?.saveNow()
        }
    }

    private func scheduleCheck(delay: Int = 450) {
        revision += 1
        let requestedRevision = revision
        let snapshot = source
        let dependencies = imports
        checkTask?.cancel()
        result = nil // Eski metnin yeşil sonucu yeni metinde gösterilmez.
        phase = .waiting
        checkTask = Task { [weak self, worker] in
            do { try await Task.sleep(for: .milliseconds(delay)) }
            catch { return }
            guard let self, !Task.isCancelled else { return }
            self.phase = .checking
            let start = ContinuousClock.now
            let checked = await worker.check(snapshot, imports: dependencies)
            guard !Task.isCancelled, requestedRevision == self.revision,
                  checked.status != .cancelled else { return }
            let duration = start.duration(to: .now).components
            self.elapsedMilliseconds = Int(duration.seconds * 1_000 + duration.attoseconds / 1_000_000_000_000_000)
            self.result = checked
            self.phase = .finished
        }
    }
}

struct EditorNavigation: Equatable {
    let id = UUID()
    let span: SourceSpan
}
