'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { runChecker } = require('../lib/checker');
const root = path.resolve(__dirname, '../../..');
const executable = process.env.RIGOR_CHECKER || path.join(root, '.build/debug/SuuTensai');

test('checks unsaved text through the real CLI and returns Unicode ranges', async () => {
    const source = '/* 🧠 */ theorem bad<A:Type>(x:A)->A { eksik }';
    const report = await runChecker(executable, { filePath: path.join(root, '.build/unsaved space.rigor'), source });
    assert.equal(report.diagnostics.length, 1);
    assert.equal(report.diagnostics[0].phase, 'kernel');
    assert.equal(report.diagnostics[0].range.start.character, source.indexOf('eksik'));
    assert.equal(report.diagnostics[0].range.end.character, source.indexOf('eksik') + 5);
});

test('imports use editor overlays before disk and retain the imported file location', async () => {
    const folder = await fs.mkdtemp(path.join(os.tmpdir(), 'rigor path '));
    try {
        const main = path.join(folder, 'main.rigor');
        const base = path.join(folder, 'Base.rigor');
        await fs.writeFile(base, 'theorem broken(');
        const source = 'import "Base.rigor"; theorem use<A:Type>(x:A)->A { identity<A>(x) }';
        const valid = await runChecker(executable, { filePath: main, source, overlays: { [base]: 'def identity<A:Type>(x:A)->A { x }' } });
        assert.deepEqual(valid.declarations, ['identity', 'use']);
        assert.deepEqual(valid.diagnostics, []);
        const invalid = await runChecker(executable, { filePath: main, source });
        assert.equal(path.basename(invalid.diagnostics[0].fileName), 'Base.rigor');
        assert.equal(invalid.diagnostics[0].phase, 'parser');
    } finally { await fs.rm(folder, { recursive: true, force: true }); }
});

test('a repaired proof clears errors', async () => {
    const report = await runChecker(executable, { filePath: path.join(root, '.build/unsaved.rigor'), source: 'theorem identity<A:Type>(x:A)->A { x }' });
    assert.deepEqual(report.diagnostics, []);
    assert.deepEqual(report.declarations, ['identity']);
});

test('cancels old checks without presenting an error result', async () => {
    const controller = new AbortController();
    controller.abort();
    await assert.rejects(runChecker(executable, { filePath: '/tmp/a.rigor', source: '' }, { signal: controller.signal }), { name: 'AbortError' });
});

test('reports checker launch failures', async () => {
    await assert.rejects(runChecker(path.join(root, '.build/does-not-exist'), { filePath: '/tmp/a.rigor', source: '' }), /ENOENT/);
});
