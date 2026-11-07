'use strict';
const assert = require('node:assert/strict');
const vscode = require('vscode');

async function waitFor(check, label) {
    const deadline = Date.now() + 20000;
    while (Date.now() < deadline) {
        if (check()) return;
        await new Promise(resolve => setTimeout(resolve, 50));
    }
    throw new Error(`Timed out: ${label}`);
}

exports.run = async function () {
    const folder = vscode.workspace.workspaceFolders[0].uri;
    const base = await vscode.workspace.openTextDocument(vscode.Uri.joinPath(folder, 'Base.rigor'));
    const document = await vscode.workspace.openTextDocument(vscode.Uri.joinPath(folder, 'main.rigor'));
    await vscode.window.showTextDocument(document, { viewColumn: vscode.ViewColumn.One });
    assert.equal(document.languageId, 'rigor');
    const extension = vscode.extensions.getExtension('suutensai.rigor-language');
    const api = await extension.activate();
    await waitFor(() => api.getInfoViewState().visible && api.getInfoViewState().viewColumn === vscode.ViewColumn.Two,
        'right infoview opens automatically beside the source');
    async function replace(target, source) {
        const edit = new vscode.WorkspaceEdit();
        edit.replace(target.uri, new vscode.Range(target.positionAt(0), target.positionAt(target.getText().length)), source);
        assert(await vscode.workspace.applyEdit(edit));
    }
    const errors = uri => vscode.languages.getDiagnostics(uri).filter(item => item.source === 'Rigor');
    await replace(document, '/* 🧠 */ theorem bad<A:Type>(x:A)->A { eksik }');
    await waitFor(() => errors(document.uri).length === 1, 'live unsaved diagnostics');
    assert.equal(errors(document.uri)[0].range.start.character, document.getText().indexOf('eksik'));
    await replace(document, 'theorem good<A:Type>(x:A)->A { x }');
    const checked = await vscode.commands.executeCommand('rigor.check');
    assert.equal(checked.state, 'checked');
    await waitFor(() => api.getInfoViewState().rendered?.version === document.version &&
        api.getInfoViewState().rendered?.state === 'checked', 'right infoview renders successful check');
    const serverPid = api.getDocumentState(document.uri.toString()).pid;
    await waitFor(() => errors(document.uri).length === 0, 'repaired diagnostics clear');
    await replace(base, 'def identity<A:Type>(x:A)->A { x }');
    await replace(document, 'import "Base.rigor"; theorem use<A:Type>(x:A)->A { identity<A>(x) }');
    await vscode.commands.executeCommand('rigor.check');
    // Force another known error then repair to ensure a completed check, not only cleared old diagnostics.
    await replace(base, 'def identity<A:Type>(x:A)->A { missing }');
    await waitFor(() => errors(base.uri).length === 1, 'unsaved import diagnostic');
    await replace(base, 'def identity<A:Type>(x:A)->A { x }');
    await vscode.commands.executeCommand('rigor.check');
    await waitFor(() => errors(base.uri).length === 0, 'unsaved import repair');
    for (let index = 0; index < 8; index++) {
        await replace(document, `theorem draft${index}<A:Type>(x:A)->A { ${index === 7 ? 'missing' : 'x'} }`);
    }
    await waitFor(() => errors(document.uri).length === 1, 'latest edit wins');
    assert.equal(errors(document.uri)[0].code, 'kernel');
    assert.equal(api.getDocumentState(document.uri.toString()).pid, serverPid, 'Edits must reuse the persistent server');
    assert.equal(api.getDocumentState(document.uri.toString()).version, document.version);
    await waitFor(() => api.getInfoViewState().rendered?.version === document.version &&
        api.getInfoViewState().rendered?.state === 'error', 'right infoview renders current error');
    await vscode.commands.executeCommand('rigor.showInfo');
    const artifact = vscode.Uri.joinPath(folder, 'extension-test-passed.txt');
    await vscode.workspace.fs.writeFile(artifact, Buffer.from('VS Code extension host passed: live right infoview, actual webview rendering, persistent LSP process, versioned diagnostics, unsaved imports, repairs and rapid edits.\n'));
    console.log('Rigor VS Code extension host integration passed.');
};
