'use strict';
const vscode = require('vscode');
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { RigorLanguageClient } = require('./lib/lsp');
const { RigorInfoView } = require('./lib/infoview');

function activate(context) {
    const output = vscode.window.createOutputChannel('Rigor');
    const status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
    let trackedDocument;
    let sourceColumn = vscode.ViewColumn.One;
    const infoPanel = new RigorInfoView(vscode, diagnostic => {
        const range = new vscode.Range(diagnostic.range.start.line, diagnostic.range.start.character,
            diagnostic.range.end.line, diagnostic.range.end.character);
        void vscode.window.showTextDocument(vscode.Uri.file(diagnostic.fileName), { viewColumn: sourceColumn, selection: range });
    });
    const states = new Map();
    const builds = new Map();
    const buildProcesses = new Set();
    status.command = 'rigor.showInfo';
    context.subscriptions.push(output, status, infoPanel);
    const config = folder => vscode.workspace.getConfiguration('rigor', folder.uri);
    const isRigor = document => document?.languageId === 'rigor' && document.uri.scheme === 'file';
    const folderFor = document => document?.uri.scheme === 'file' ? vscode.workspace.getWorkspaceFolder(document.uri) : undefined;
    const documentsFor = folder => vscode.workspace.textDocuments.filter(document => isRigor(document) &&
        folderFor(document)?.uri.toString() === folder.uri.toString());

    function stateFor(folder) {
        const key = folder.uri.toString();
        if (!states.has(key)) {
            const diagnostics = vscode.languages.createDiagnosticCollection(`rigor-${folder.name}`);
            context.subscriptions.push(diagnostics);
            states.set(key, { folder, diagnostics, sequence: 0, serverEpoch: 0, reports: new Map(), sent: new Map(), restarts: [] });
        }
        return states.get(key);
    }

    function current() {
        const document = vscode.window.activeTextEditor?.document || trackedDocument;
        if (!isRigor(document) || document.isClosed) return {};
        const folder = folderFor(document);
        const state = folder && stateFor(folder);
        return { document, state, info: state?.reports.get(document.uri.toString()) };
    }

    function refresh() {
        const { document, state, info } = current();
        if (!document) status.hide();
        else {
            const names = { checking: '$(sync~spin) Rigor', checked: '$(check) Rigor', error: '$(error) Rigor', empty: '$(pencil) Rigor' };
            status.text = state?.failure ? '$(warning) Rigor' : !vscode.workspace.isTrusted || !state || !config(state.folder).get('lint.enabled', true)
                ? '$(circle-slash) Rigor' : names[info?.state || 'checking'];
            status.tooltip = state?.failure || (info?.report?.axioms?.length ?
                `Axiom dependencies: ${info.report.axioms.join(', ')}` : 'Rigor: live type/proof checking. Click for details.');
            status.show();
        }
        infoPanel.update(infoSnapshot());
    }

    function infoSnapshot() {
        const { document, state, info } = current();
        const base = { fileName: document ? path.basename(document.uri.fsPath) : '', uri: document?.uri.toString(),
            version: document?.version, dirty: document?.isDirty, diagnostics: [], declarations: [], axioms: [] };
        if (!document) return { ...base, state: 'noDocument' };
        if (state?.failure) return { ...base, state: 'failure', message: state.failure };
        if (!state || !vscode.workspace.isTrusted || !config(state.folder).get('lint.enabled', true)) return { ...base, state: 'disabled' };
        return { ...base, state: info?.state || 'checking', elapsedMs: info?.elapsedMs,
            diagnostics: info?.report?.diagnostics || [], declarations: info?.report?.declarations || [], axioms: info?.report?.axioms || [] };
    }

    function trackEditor(editor) {
        if (editor) {
            trackedDocument = isRigor(editor.document) ? editor.document : undefined;
            if (trackedDocument) {
                sourceColumn = editor.viewColumn || vscode.ViewColumn.One;
                const folder = folderFor(trackedDocument);
                if (folder && config(folder).get('info.autoOpen', true)) infoPanel.show({ automatic: true });
            }
        }
        refresh();
    }

    function defaultExecutable(folder) {
        return path.join(folder.uri.fsPath, '.build', 'debug', process.platform === 'win32' ? 'SuuTensai.exe' : 'SuuTensai');
    }

    async function buildChecker(folder) {
        const key = folder.uri.toString();
        if (builds.has(key)) return builds.get(key);
        if (!vscode.workspace.isTrusted) throw new Error('Trust this workspace before running the Rigor checker.');
        const root = folder.uri.fsPath;
        const cache = path.join(root, '.build');
        const env = { ...process.env, CLANG_MODULE_CACHE_PATH: path.join(cache, 'ModuleCache'), SWIFTPM_MODULECACHE_OVERRIDE: path.join(cache, 'ModuleCache') };
        if (process.platform === 'darwin' && !env.DEVELOPER_DIR && fs.existsSync('/Applications/Xcode.app/Contents/Developer')) env.DEVELOPER_DIR = '/Applications/Xcode.app/Contents/Developer';
        const promise = new Promise((resolve, reject) => {
            const args = ['build', '--product', 'SuuTensai', '--configuration', 'debug', '--disable-sandbox',
                '--cache-path', path.join(cache, 'cache'), '--config-path', path.join(cache, 'config'), '--security-path', path.join(cache, 'security')];
            output.appendLine(`Building Rigor in ${root}`);
            const child = spawn(config(folder).get('swiftPath', 'swift'), args, { cwd: root, env, windowsHide: true });
            buildProcesses.add(child);
            child.stdout.on('data', data => output.append(data.toString()));
            child.stderr.on('data', data => output.append(data.toString()));
            const timeout = setTimeout(() => child.kill('SIGKILL'), 120000);
            child.on('error', error => { clearTimeout(timeout); buildProcesses.delete(child); reject(error); });
            child.on('close', code => {
                clearTimeout(timeout);
                buildProcesses.delete(child);
                if (code === 0 && fs.existsSync(defaultExecutable(folder))) resolve(defaultExecutable(folder));
                else reject(new Error('Checker build failed. Run “Rigor: Show Checker Output”.'));
            });
        });
        builds.set(key, promise);
        try { return await promise; } finally { builds.delete(key); }
    }

    async function executableFor(folder) {
        const configured = config(folder).get('checkerPath', '').replaceAll('${workspaceFolder}', folder.uri.fsPath);
        if (configured) {
            const executable = path.isAbsolute(configured) ? configured : path.join(folder.uri.fsPath, configured);
            if (!fs.existsSync(executable)) throw new Error(`Checker not found: ${executable}`);
            return executable;
        }
        if (builds.has(folder.uri.toString())) return builds.get(folder.uri.toString());
        if (fs.existsSync(defaultExecutable(folder))) return defaultExecutable(folder);
        if (config(folder).get('autoBuild', true)) return buildChecker(folder);
        throw new Error('Build the checker with “Rigor: Build Checker” or set rigor.checkerPath.');
    }

    function acceptNotification(state, client, method, params) {
        if (state.client !== client || state.disposed) return;
        if (method === 'textDocument/publishDiagnostics') {
            if (params.rigorRevision !== state.sequence) return;
            const uri = vscode.Uri.parse(params.uri);
            const document = vscode.workspace.textDocuments.find(doc => doc.uri.toString() === params.uri);
            if (document && params.version !== undefined && document.version !== params.version) return;
            state.diagnostics.set(uri, params.diagnostics.map(item => {
                let range = new vscode.Range(item.range.start.line, item.range.start.character, item.range.end.line, item.range.end.character);
                if (range.isEmpty) range = new vscode.Range(range.start, range.end.translate(0, 1));
                const diagnostic = new vscode.Diagnostic(range, item.message, vscode.DiagnosticSeverity.Error);
                diagnostic.source = item.source;
                diagnostic.code = item.code;
                return diagnostic;
            }));
        } else if (method === 'rigor/status') {
            if (params.revision !== state.sequence) return;
            const document = vscode.workspace.textDocuments.find(doc => doc.uri.toString() === params.uri);
            if (!document || document.version !== params.version) return;
            state.reports.set(params.uri, { ...params, pid: client.pid });
            refresh();
        }
    }

    async function connection(state) {
        if (state.connecting) return state.connecting;
        if (state.client && !state.client.closed && !state.client.failed) return state.client;
        const epoch = state.serverEpoch;
        const promise = (async () => {
            const executable = await executableFor(state.folder);
            if (state.disposed || state.serverEpoch !== epoch) throw new Error('Server startup cancelled.');
            const client = new RigorLanguageClient(executable, { cwd: state.folder.uri.fsPath, log: data => output.append(data) });
            state.client = client;
            state.sent.clear();
            client.on('notification', (method, params) => acceptNotification(state, client, method, params));
            client.on('failure', error => {
                if (state.client !== client || state.disposed || client.disposed) return;
                state.failure = `${error.message} Try “Rigor: Build Checker”.`;
                output.appendLine(state.failure);
                state.diagnostics.clear();
                state.reports.clear();
                state.restarts = state.restarts.filter(time => Date.now() - time < 60000);
                if (state.restarts.length < 3) {
                    state.restarts.push(Date.now());
                    state.restartTimer = setTimeout(() => schedule(state.folder), 500);
                }
                refresh();
            });
            try { await client.initialize(state.folder.uri.toString()); }
            catch (error) {
                await client.dispose();
                if (state.client === client) state.client = undefined;
                throw error;
            }
            if (state.disposed || state.serverEpoch !== epoch) { await client.dispose(); throw new Error('Server startup cancelled.'); }
            state.failure = undefined;
            return client;
        })();
        state.connecting = promise;
        try { return await promise; } finally { if (state.connecting === promise) state.connecting = undefined; }
    }

    async function stopServer(state) {
        state.serverEpoch += 1;
        clearTimeout(state.timer);
        clearTimeout(state.restartTimer);
        const client = state.client;
        state.client = undefined;
        state.connecting = undefined;
        state.sent.clear();
        state.reports.clear();
        state.diagnostics.clear();
        if (client) await client.dispose();
    }

    function schedule(folder, immediate = false) {
        if (!folder) return;
        const state = stateFor(folder);
        state.sequence += 1;
        clearTimeout(state.timer);
        state.diagnostics.clear();
        state.reports.clear();
        if (!vscode.workspace.isTrusted || !config(folder).get('lint.enabled', true)) { void stopServer(state); refresh(); return; }
        refresh();
        const sequence = state.sequence;
        if (immediate) return synchronize(state, sequence, true);
        const delay = config(folder).get('lint.delay', 0);
        if (delay > 0) state.timer = setTimeout(() => synchronize(state, sequence), delay);
        else queueMicrotask(() => synchronize(state, sequence));
    }

    async function synchronize(state, sequence, explicit = false) {
        try {
            if (sequence !== state.sequence || state.disposed) return;
            const documents = documentsFor(state.folder);
            if (!documents.length && !state.client) return;
            const client = await connection(state);
            if (sequence !== state.sequence || state.disposed) return;
            const open = new Set(documents.map(doc => doc.uri.toString()));
            for (const uri of state.sent.keys()) {
                if (!open.has(uri)) { client.notify('textDocument/didClose', { textDocument: { uri } }); state.sent.delete(uri); }
            }
            for (const document of documents) {
                const uri = document.uri.toString();
                const version = state.sent.get(uri);
                if (version === undefined) client.notify('textDocument/didOpen', { textDocument: { uri, languageId: 'rigor', version: document.version, text: document.getText() } });
                else if (version !== document.version) client.notify('textDocument/didChange', { textDocument: { uri, version: document.version }, contentChanges: [{ text: document.getText() }] });
                state.sent.set(uri, document.version);
            }
            client.notify('rigor/sync', { revision: sequence });
            if (explicit) {
                const document = current().document;
                if (isRigor(document) && folderFor(document)?.uri.toString() === state.folder.uri.toString()) return await client.request('rigor/check', { textDocument: { uri: document.uri.toString() } });
            }
        } catch (error) {
            if (sequence !== state.sequence || state.disposed || error.code === -32801) return;
            state.failure = error.message;
            output.appendLine(error.message);
            refresh();
        }
    }

    function scheduleDocument(document) { if (isRigor(document)) schedule(folderFor(document)); }
    function scheduleAll() { for (const folder of vscode.workspace.workspaceFolders || []) schedule(folder); }
    context.subscriptions.push(
        vscode.workspace.onDidOpenTextDocument(scheduleDocument),
        vscode.workspace.onDidChangeTextDocument(event => { if (event.contentChanges.length) scheduleDocument(event.document); }),
        vscode.workspace.onDidSaveTextDocument(scheduleDocument),
        vscode.workspace.onDidCloseTextDocument(scheduleDocument),
        vscode.workspace.onDidChangeConfiguration(async event => {
            if (!event.affectsConfiguration('rigor')) return;
            await Promise.all([...states.values()].map(stopServer));
            scheduleAll();
        }),
        vscode.workspace.onDidChangeWorkspaceFolders(event => {
            for (const folder of event.removed) {
                const state = states.get(folder.uri.toString());
                if (state) { state.disposed = true; void stopServer(state); states.delete(folder.uri.toString()); }
            }
            scheduleAll();
        }),
        vscode.workspace.onDidGrantWorkspaceTrust(scheduleAll),
        vscode.window.onDidChangeActiveTextEditor(trackEditor),
        vscode.commands.registerCommand('rigor.showOutput', () => output.show()),
        vscode.commands.registerCommand('rigor.showInfo', () => { infoPanel.show(); refresh(); }),
        vscode.commands.registerCommand('rigor.check', () => schedule(folderFor(current().document), true)),
        vscode.commands.registerCommand('rigor.restartServer', async () => {
            const folder = folderFor(current().document) || vscode.workspace.workspaceFolders?.[0];
            if (folder) { await stopServer(stateFor(folder)); return schedule(folder, true); }
        }),
        vscode.commands.registerCommand('rigor.buildChecker', async () => {
            const folder = folderFor(current().document) || vscode.workspace.workspaceFolders?.[0];
            if (!folder) return;
            try { await stopServer(stateFor(folder)); await buildChecker(folder); return schedule(folder, true); }
            catch (error) { output.appendLine(error.message); output.show(); }
        }),
        { dispose() { for (const state of states.values()) { state.disposed = true; void stopServer(state); } for (const child of buildProcesses) child.kill('SIGKILL'); } }
    );
    const watcher = vscode.workspace.createFileSystemWatcher('**/*.rigor');
    context.subscriptions.push(watcher, watcher.onDidChange(uri => schedule(vscode.workspace.getWorkspaceFolder(uri))),
        watcher.onDidCreate(uri => schedule(vscode.workspace.getWorkspaceFolder(uri))),
        watcher.onDidDelete(uri => schedule(vscode.workspace.getWorkspaceFolder(uri))));
    trackEditor(vscode.window.activeTextEditor);
    scheduleAll();
    return { getInfoViewState() { return infoPanel.getState(); }, getDocumentState(uri) {
        const document = vscode.workspace.textDocuments.find(doc => doc.uri.toString() === uri);
        const folder = folderFor(document);
        return folder && stateFor(folder).reports.get(uri);
    } };
}

module.exports = { activate };
