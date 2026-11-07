import Foundation
import SuuTensai
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Tek süreç; belge sürümleri actor'da, pahalı kontroller iptal edilebilir görevlerde.
actor RigorLanguageServer {
    private struct Document: Sendable {
        let uri: String
        let source: String
        let version: Int
    }
    private struct Completed {
        let document: Document
        let report: RigorLintReport
        let elapsed: Int
    }
    private var documents: [String: Document] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var results: [String: Completed] = [:]
    private var pending: [String: [Any]] = [:]
    private var published: Set<String> = []
    private var generation = 0
    private var initialized = false
    private var shuttingDown = false
    private var revision = 0
    private var revisionMode = false

    static func run() async throws {
        let server = RigorLanguageServer()
        var reader = RigorRPCReader()
        while let data = try reader.readMessage() {
            if !(await server.receive(data)) { return }
        }
        await server.stop()
    }

    private func stop() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
    }

    private func receive(_ data: Data) -> Bool {
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = message["method"] as? String else {
            send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Invalid JSON-RPC message"]])
            return true
        }
        let id = message["id"]
        let params = message["params"] as? [String: Any] ?? [:]
        func reply(_ result: Any) {
            if let id { send(["jsonrpc": "2.0", "id": id, "result": result]) }
        }
        if method == "exit" { stop(); return false }
        if method == "initialize" {
            initialized = true
            let capabilities = params["capabilities"] as? [String: Any]
            let experimental = capabilities?["experimental"] as? [String: Any]
            revisionMode = experimental?["rigorRevision"] as? Bool == true
            reply(["capabilities": ["positionEncoding": "utf-16",
                "textDocumentSync": ["openClose": true, "change": 1, "save": ["includeText": false]]],
                "serverInfo": ["name": "Rigor", "version": "0.2.0"]])
            return true
        }
        guard initialized, !shuttingDown else {
            if let id { sendError(id, code: -32002, message: "Server is not initialized") }
            return true
        }
        switch method {
        case "initialized": break
        case "shutdown":
            stop()
            shuttingDown = true
            reply(NSNull())
        case "textDocument/didOpen":
            if let value = params["textDocument"] as? [String: Any], let uri = value["uri"] as? String,
               let source = value["text"] as? String, let version = value["version"] as? Int,
               URL(string: uri)?.isFileURL == true {
                documents[uri] = Document(uri: uri, source: source, version: version)
                if !revisionMode { beginChecks() }
            }
        case "textDocument/didChange":
            if let value = params["textDocument"] as? [String: Any], let uri = value["uri"] as? String,
               let version = value["version"] as? Int, let old = documents[uri], version > old.version,
               let changes = params["contentChanges"] as? [[String: Any]],
               let source = changes.last?["text"] as? String,
               changes.allSatisfy({ $0["range"] == nil }) {
                documents[uri] = Document(uri: uri, source: source, version: version)
                if !revisionMode { beginChecks() }
            }
        case "textDocument/didClose":
            if let value = params["textDocument"] as? [String: Any], let uri = value["uri"] as? String {
                documents.removeValue(forKey: uri)
                if !revisionMode { beginChecks() }
            }
        case "textDocument/didSave", "workspace/didChangeWatchedFiles":
            if !revisionMode { beginChecks() }
        case "rigor/sync":
            if let requested = params["revision"] as? Int, requested > revision {
                revision = requested
                beginChecks()
            }
        case "rigor/check":
            guard let value = params["textDocument"] as? [String: Any], let uri = value["uri"] as? String,
                  documents[uri] != nil else {
                if let id { sendError(id, code: -32602, message: "Document is not open") }
                break
            }
            if let result = results[uri] { reply(status(result)) }
            else if let id { pending[uri, default: []].append(id) }
        case "$/cancelRequest":
            if let cancelled = params["id"] {
                for uri in Array(pending.keys) {
                    pending[uri]?.removeAll { String(describing: $0) == String(describing: cancelled) }
                }
            }
        default:
            if let id { sendError(id, code: -32601, message: "Method not found: \(method)") }
        }
        return true
    }

    private func beginChecks() {
        stop()
        generation += 1
        results.removeAll()
        for ids in pending.values {
            for id in ids { sendError(id, code: -32801, message: "Document changed") }
        }
        pending.removeAll()
        publishDiagnostics() // Önce eski sürümün alt çizgilerini kaldır.
        let snapshot = documents
        let overlays = Dictionary(snapshot.values.compactMap { doc -> (String, String)? in
            guard let url = URL(string: doc.uri) else { return nil }
            return (url.path, doc.source)
        }, uniquingKeysWith: { _, last in last })
        let epoch = generation
        for document in snapshot.values {
            notify("rigor/status", ["uri": document.uri, "version": document.version,
                                    "generation": epoch, "revision": revision, "state": "checking"])
            tasks[document.uri] = Task.detached(priority: .userInitiated) { [weak self] in
                guard !Task.isCancelled, let url = URL(string: document.uri) else { return }
                let start = ProcessInfo.processInfo.systemUptime
                let report = RigorChecker.lint(source: document.source, fileURL: url, overlays: overlays)
                guard !Task.isCancelled else { return }
                let elapsed = Int((ProcessInfo.processInfo.systemUptime - start) * 1_000)
                await self?.complete(document, report: report, epoch: epoch, elapsed: elapsed)
            }
        }
    }

    private func complete(_ document: Document, report: RigorLintReport, epoch: Int, elapsed: Int) {
        guard epoch == generation, documents[document.uri]?.version == document.version else { return }
        tasks.removeValue(forKey: document.uri)
        let completed = Completed(document: document, report: report, elapsed: elapsed)
        results[document.uri] = completed
        publishDiagnostics()
        let value = status(completed)
        notify("rigor/status", value)
        for id in pending.removeValue(forKey: document.uri) ?? [] {
            send(["jsonrpc": "2.0", "id": id, "result": value])
        }
    }

    private func status(_ completed: Completed) -> [String: Any] {
        ["uri": completed.document.uri, "version": completed.document.version,
         "generation": generation, "state": completed.report.diagnostics.isEmpty ?
            (completed.report.declarations.isEmpty ? "empty" : "checked") : "error",
         "revision": revision, "elapsedMs": completed.elapsed, "report": object(completed.report)]
    }

    private func canonical(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }

    private func publishDiagnostics() {
        let openURIs = Dictionary(documents.values.compactMap { doc -> (String, String)? in
            guard let url = URL(string: doc.uri) else { return nil }
            return (canonical(url), doc.uri)
        }, uniquingKeysWith: { first, _ in first })
        var grouped: [String: [[String: Any]]] = [:]
        var seen: Set<String> = []
        for completed in results.values {
            for diagnostic in completed.report.diagnostics {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .sortedKeys
                let key = String(decoding: (try? encoder.encode(diagnostic)) ?? Data(), as: UTF8.self)
                guard seen.insert(key).inserted else { continue }
                let url = URL(fileURLWithPath: diagnostic.fileName)
                let uri = openURIs[canonical(url)] ?? url.absoluteString
                grouped[uri, default: []].append(["range": object(diagnostic.range), "severity": 1,
                    "source": "Rigor", "code": diagnostic.phase, "message": diagnostic.message])
            }
        }
        for uri in published.union(grouped.keys).union(documents.keys).sorted() {
            var params: [String: Any] = ["uri": uri, "diagnostics": grouped[uri] ?? [], "rigorRevision": revision]
            if let version = documents[uri]?.version { params["version"] = version }
            notify("textDocument/publishDiagnostics", params)
        }
        published = Set(grouped.keys)
    }

    private func object<T: Encodable>(_ value: T) -> Any {
        guard let data = try? JSONEncoder().encode(value), let object = try? JSONSerialization.jsonObject(with: data) else { return NSNull() }
        return object
    }

    private func notify(_ method: String, _ params: [String: Any]) {
        send(["jsonrpc": "2.0", "method": method, "params": params])
    }

    private func sendError(_ id: Any, code: Int, message: String) {
        send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        let header = Data("Content-Length: \(data.count)\r\n\r\n".utf8)
        try? FileHandle.standardOutput.write(contentsOf: header + data)
    }
}

private struct RigorRPCReader {
    private var buffer = Data()
    private let limit = 16 * 1_024 * 1_024

    mutating func readMessage() throws -> Data? {
        while true {
            if let separator = buffer.range(of: Data([13, 10, 13, 10])) {
                let header = String(decoding: buffer[..<separator.lowerBound], as: UTF8.self)
                let length = header.components(separatedBy: "\r\n").compactMap { line -> Int? in
                    let parts = line.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2, parts[0].lowercased() == "content-length" else { return nil }
                    return Int(parts[1].trimmingCharacters(in: .whitespaces))
                }.first
                guard let length, length >= 0, length <= limit else { throw ProtocolError() }
                let start = separator.upperBound
                if buffer.count >= start + length {
                    let result = Data(buffer[start..<(start + length)])
                    buffer = Data(buffer[(start + length)...])
                    return result
                }
            } else if buffer.count > 8_192 { throw ProtocolError() }
            var bytes = [UInt8](repeating: 0, count: 65_536)
            let count = bytes.withUnsafeMutableBytes { raw in
                read(STDIN_FILENO, raw.baseAddress, raw.count)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw ProtocolError()
            }
            guard count > 0 else {
                if !buffer.isEmpty { throw ProtocolError() }
                return nil
            }
            buffer.append(contentsOf: bytes.prefix(count))
        }
    }

    private struct ProtocolError: Error {}
}
