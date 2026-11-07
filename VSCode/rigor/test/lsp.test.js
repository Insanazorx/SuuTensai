'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { RigorLanguageClient } = require('../lib/lsp');
const root = path.resolve(__dirname, '../../..');
const executable = process.env.RIGOR_CHECKER || path.join(root, '.build/debug/SuuTensai');
const uriFor = name => pathToFileURL(path.join(root, '.build/lsp test', name)).href;

async function server(t, standard = false) {
    const client = new RigorLanguageClient(executable, { cwd: root });
    client.on('failure', () => {});
    t.after(async () => { await client.dispose(); });
    const initialized = standard ? await client.request('initialize', { capabilities: {} }) : await client.initialize(pathToFileURL(root).href);
    assert.equal(initialized.capabilities.textDocumentSync.change, 1);
    return client;
}
function open(client, uri, text, version = 1) {
    client.notify('textDocument/didOpen', { textDocument: { uri, languageId: 'rigor', text, version } });
}
function change(client, uri, text, version, revision) {
    client.notify('textDocument/didChange', { textDocument: { uri, version }, contentChanges: [{ text }] });
    client.notify('rigor/sync', { revision });
}
const check = (client, uri) => client.request('rigor/check', { textDocument: { uri } });

test('one persistent LSP process checks edits and repairs with UTF-16 diagnostics', async t => {
    const client = await server(t);
    const pid = client.pid;
    const uri = uriFor('özdeşlik.rigor');
    const notifications = [];
    client.on('notification', (method, params) => notifications.push({ method, params }));
    const invalid = '/* 🧠 */ theorem bad<A:Type>(x:A)->A { eksik }';
    open(client, uri, invalid);
    client.notify('rigor/sync', { revision: 1 });
    const first = await check(client, uri);
    assert.equal(first.state, 'error');
    assert.equal(first.version, 1);
    assert.equal(first.report.diagnostics[0].range.start.character, invalid.indexOf('eksik'));
    change(client, uri, 'theorem repaired<A:Type>(x:A)->A { x }', 2, 2);
    const repaired = await check(client, uri);
    assert.equal(repaired.state, 'checked');
    assert.deepEqual(repaired.report.declarations, ['repaired']);
    assert.equal(client.pid, pid);
    assert(notifications.some(item => item.method === 'textDocument/publishDiagnostics' && item.params.version === 2 && item.params.diagnostics.length === 0));
    assert(notifications.some(item => item.method === 'rigor/status' && item.params.state === 'checking'));
});

test('rapid edits cancel old work and keep the latest version', async t => {
    const client = await server(t);
    const uri = uriFor('rapid.rigor');
    const statuses = [];
    client.on('notification', (method, params) => { if (method === 'rigor/status') statuses.push(params); });
    open(client, uri, Array.from({ length: 2000 }, (_, i) => `def slow${i}<A:Type>(x:A)->A { x }`).join('\n'));
    client.notify('rigor/sync', { revision: 1 });
    for (let version = 2; version <= 30; version++) {
        change(client, uri, `theorem current${version}<A:Type>(x:A)->A { x }`, version, version);
    }
    const latest = await check(client, uri);
    assert.equal(latest.version, 30);
    assert.equal(latest.revision, 30);
    assert.deepEqual(latest.report.declarations, ['current30']);
    await new Promise(resolve => setTimeout(resolve, 50));
    assert.equal(statuses.at(-1).version, 30);
    assert.equal(statuses.at(-1).state, 'checked');
    // A delayed old didChange must not replace the newer source.
    change(client, uri, 'theorem obsolete(', 3, 31);
    assert.equal((await check(client, uri)).version, 30);
});

test('unsaved imports invalidate dependants and closing them restores disk resolution', async t => {
    const client = await server(t);
    const main = uriFor('main.rigor');
    const base = uriFor('Base.rigor');
    open(client, base, 'def identity<A:Type>(x:A)->A { x }');
    open(client, main, 'import "Base.rigor"; theorem use<A:Type>(x:A)->A { identity<A>(x) }');
    client.notify('rigor/sync', { revision: 1 });
    assert.equal((await check(client, main)).state, 'checked');
    change(client, base, 'def identity<A:Type>(x:A)->A { missing }', 2, 2);
    const broken = await check(client, main);
    assert.equal(broken.state, 'error');
    assert.equal(path.basename(broken.report.diagnostics[0].fileName), 'Base.rigor');
    change(client, base, 'def identity<A:Type>(x:A)->A { x }', 3, 3);
    assert.equal((await check(client, main)).state, 'checked');
    client.notify('textDocument/didClose', { textDocument: { uri: base } });
    client.notify('rigor/sync', { revision: 4 });
    assert.equal((await check(client, main)).report.diagnostics[0].phase, 'loader');
});

test('standard LSP didOpen works without the optional revision extension', async t => {
    const client = await server(t, true);
    const uri = uriFor('standard.rigor');
    open(client, uri, 'theorem standard<A:Type>(x:A)->A { x }');
    assert.equal((await check(client, uri)).state, 'checked');
    await assert.rejects(client.request('unsupported/method', {}), error => error.code === -32601);
});

test('server accepts fragmented UTF-8 JSON-RPC frames', async t => {
    const client = await server(t);
    const uri = uriFor('fragment.rigor');
    const body = Buffer.from(JSON.stringify({ jsonrpc: '2.0', method: 'textDocument/didOpen', params: {
        textDocument: { uri, version: 1, text: '// 🧠\ntheorem özdeşlik<A:Type>(x:A)->A { x }', languageId: 'rigor' },
    } }));
    const frame = Buffer.concat([Buffer.from(`Content-Length: ${body.length}\r\n\r\n`), body]);
    for (let index = 0; index < frame.length; index += 7) client.child.stdin.write(frame.subarray(index, index + 7));
    client.notify('rigor/sync', { revision: 1 });
    assert.deepEqual((await check(client, uri)).report.declarations, ['özdeşlik']);
});
