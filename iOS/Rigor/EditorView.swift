import SwiftUI
import UniformTypeIdentifiers
import SuuTensai

private struct RigorDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct EditorView: View {
    @StateObject private var model = EditorModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showingDetails = false
    @State private var exporting = false
    @State private var pendingExample: String?
    @State private var exportError: String?
    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var statusColor: Color {
        guard let result = model.result else { return .secondary }
        switch result.status {
        case .valid: return result.axioms.isEmpty ? .teal : .orange
        case .invalid: return .red
        case .empty, .cancelled: return .secondary
        }
    }

    private var statusTitle: String {
        guard let result = model.result else {
            return model.phase == .checking ? "Kontrol ediliyor…" : "Yazman bekleniyor…"
        }
        switch result.status {
        case .valid: return result.axioms.isEmpty ? "Doğrulandı" : "Aksiyomlarla doğrulandı"
        case .invalid: return "Düzeltme gerekiyor"
        case .empty: return "Bir bildirim yaz"
        case .cancelled: return "Kontrol bekleniyor"
        }
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                editorContent
                if isLandscape {
                    Divider()
                    ScrollView { resultPanel }
                        .frame(width: 230)
                        .background(.regularMaterial)
                        .accessibilityIdentifier("rigor.landscapeResult")
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Rigor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Label("Çevrimdışı", systemImage: "iphone")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    editorOptions
                }
            }
            .toolbar(isLandscape ? .hidden : .visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { if !isLandscape { resultPanel } }
            .sheet(isPresented: $showingDetails) { details }
            .confirmationDialog("Örneği açmak mevcut taslağın yerini alır.", isPresented: Binding(
                get: { pendingExample != nil },
                set: { if !$0 { pendingExample = nil } }
            ), titleVisibility: .visible) {
                Button("Örneği aç", role: .destructive) {
                    if let example = pendingExample { model.source = example }
                    pendingExample = nil
                }
                Button("Vazgeç", role: .cancel) { pendingExample = nil }
            }
            .fileExporter(isPresented: $exporting, document: RigorDocument(text: model.source),
                          contentType: .plainText, defaultFilename: "Taslak.rigor") { result in
                if case .failure(let error) = result { exportError = error.localizedDescription }
            }
            .alert("Dışa aktarılamadı", isPresented: Binding(
                get: { exportError != nil }, set: { if !$0 { exportError = nil } }
            )) { Button("Tamam") { exportError = nil } }
            message: { Text(exportError ?? "") }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { model.saveNow() }
            }
        }
        .tint(.teal)
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.plaintext")
                Text("Taslak.rigor").fontWeight(.medium)
                Spacer()
                Text("\(model.source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count) satır")
                if isLandscape { editorOptions }
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, isLandscape ? 3 : 12)
            .background(Color(uiColor: .secondarySystemBackground))

            CodeEditor(text: $model.source, diagnostic: model.result?.diagnostic,
                       navigation: model.navigationRequest)
                .accessibilityHint("Rigor kodunu yaz. Yazmayı bıraktığında otomatik kontrol edilir.")

            if let storageError = model.storageError {
                Text(storageError).font(.caption).foregroundStyle(.red)
                    .padding(.horizontal).accessibilityIdentifier("rigor.saveError")
            }
        }
    }

    private var editorOptions: some View {
        Menu {
            Button("Şimdi kontrol et", systemImage: "checkmark.circle") { model.checkNow() }
            Menu("Örnekler", systemImage: "text.book.closed") {
                ForEach(EditorModel.examples, id: \.name) { example in
                    Button(example.name) { pendingExample = example.source }
                }
            }
            Button("Dosya olarak dışa aktar", systemImage: "square.and.arrow.up") { exporting = true }
        } label: {
            Image(systemName: "ellipsis.circle").frame(minWidth: 32, minHeight: 32)
        }
        .accessibilityLabel("Editör seçenekleri")
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if model.result == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: model.result?.status == .invalid ? "exclamationmark.circle.fill" :
                            model.result?.status == .empty ? "pencil.line" : "checkmark.circle.fill")
                        .foregroundStyle(statusColor)
                }
                Text(statusTitle).font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("rigor.status")
                Spacer()
                if let result = model.result, result.status == .valid {
                    Button { showingDetails = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("Kontrol ayrıntıları")
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            if let diagnostic = model.result?.diagnostic {
                Text(diagnostic.message)
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    .lineLimit(4).accessibilityIdentifier("rigor.diagnostic")
                if diagnostic.fileName == "Taslak.rigor" {
                    Button(action: model.goToDiagnostic) {
                        Label("Satır \(diagnostic.span.start.line), sütun \(diagnostic.span.start.column)",
                              systemImage: "arrow.up.left")
                            .font(.caption.monospaced())
                    }
                    .frame(minHeight: 30)
                } else {
                    Text("\(diagnostic.fileName) · \(diagnostic.span.start.line):\(diagnostic.span.start.column)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            } else if let result = model.result, result.status == .valid {
                Text("\(result.declarations.count) bildirim · \(result.axioms.isEmpty ? "Aksiyom bağımlılığı yok" : "\(result.axioms.count) aksiyom bağımlılığı")")
                    .font(.caption).foregroundStyle(.secondary)
            } else if model.result?.status == .empty {
                Text("Bir theorem veya def yazabilir, menüden örnek açabilirsin.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(model.saveMessage)
                Spacer()
                Text("Otomatik kontrol açık")
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var details: some View {
        NavigationStack {
            List {
                if let result = model.result {
                    Section("Doğrulanan bildirimler") {
                        ForEach(result.declarations, id: \.self) { name in
                            Label(name, systemImage: "checkmark").font(.body.monospaced())
                        }
                    }
                    Section("Aksiyom bağımlılıkları") {
                        if result.axioms.isEmpty {
                            Text("Yok. Bu kaynak aksiyom kullanmadan doğrulandı.")
                        } else {
                            ForEach(result.axioms, id: \.self) { Text($0).font(.body.monospaced()) }
                        }
                    }
                    Section {
                        Text("Kontrol bu iPhone üzerinde çalışır. İlk hata gösterilir; düzelttiğinde kontrol yeniden yapılır.")
                        Text("Yerleşik import: Fundamentals.rigor. Diğer dosyaları içe aktarma bu sürümde desteklenmez.")
                        Text("Kontrol süresi: \(model.elapsedMilliseconds) ms")
                    }
                    .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Kontrol ayrıntıları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { showingDetails = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}
