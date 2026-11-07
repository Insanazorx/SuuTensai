'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const resources = process.env.VSCODE_RESOURCES || '/Applications/Visual Studio Code.app/Contents/Resources/app';
const textmate = require(path.join(resources, 'node_modules.asar/vscode-textmate'));
const onig = require(path.join(resources, 'node_modules.asar/vscode-oniguruma'));

(async () => {
    const wasm = fs.readFileSync(path.join(resources, 'node_modules.asar.unpacked/vscode-oniguruma/release/onig.wasm'));
    await onig.loadWASM(wasm.buffer.slice(wasm.byteOffset, wasm.byteOffset + wasm.byteLength));
    const registry = new textmate.Registry({
        onigLib: Promise.resolve({ createOnigScanner: patterns => new onig.OnigScanner(patterns), createOnigString: text => new onig.OnigString(text) }),
        loadGrammar: async () => JSON.parse(fs.readFileSync(path.join(__dirname, '../VSCode/rigor/syntaxes/rigor.tmLanguage.json'), 'utf8')),
    });
    const grammar = await registry.loadGrammar('source.rigor');
    let stack = textmate.INITIAL;
    function tokenize(line) {
        const result = grammar.tokenizeLine(line, stack);
        stack = result.ruleStack;
        return result.tokens.map(token => ({ text: line.slice(token.startIndex, token.endIndex), scopes: token.scopes.join(' ') }));
    }
    const declaration = tokenize('theorem özdeşlik<A: Type>(x:A)->A { return _ }');
    assert(declaration.some(token => token.text === 'özdeşlik' && token.scopes.includes('entity.name.function')));
    assert(declaration.some(token => token.text === 'Type' && token.scopes.includes('support.type')));
    assert(declaration.some(token => token.text === 'return' && token.scopes.includes('keyword.control')));
    tokenize('/* outer /* nested */');
    const commentEnd = tokenize('still a comment */ theorem after<A:Type>(x:A)->A { x }');
    assert(commentEnd.some(token => token.text.includes('still a comment') && token.scopes.includes('comment.block')));
    assert(commentEnd.some(token => token.text === 'after' && token.scopes.includes('entity.name.function')));
    tokenize('"unfinished');
    const nextLine = tokenize('theorem next<A:Type>(x:A)->A { x }');
    assert(nextLine.some(token => token.text === 'next' && token.scopes.includes('entity.name.function')));
    const boundaries = tokenize('theoremα Type2 _name');
    assert(!boundaries.some(token => /keyword|constant.language.hole/.test(token.scopes)));
    assert(!boundaries.some(token => token.text === 'Type' && token.scopes.includes('support.type')));
    const calls = tokenize('F() identity<A>(x) özdeşlik(x)');
    for (const name of ['F', 'identity', 'özdeşlik']) {
        assert(calls.some(token => token.text === name && token.scopes.includes('entity.name.function')));
    }
    const arrows = tokenize('F<A>(x)->B; fun(x:A)=>F(x)');
    for (const arrow of ['->', '=>']) {
        assert(arrows.some(token => token.text === arrow && token.scopes.includes('keyword.operator')), `${arrow} must be a single operator token`);
    }
    const language = JSON.parse(fs.readFileSync(path.join(__dirname, '../VSCode/rigor/language-configuration.json')));
    assert(!language.brackets.some(pair => pair.includes('>')), 'Arrow tails must not be recolored as brackets');
    registry.dispose();
    console.log('VS Code TextMate grammar passed: complete arrows, Swift-like calls/types, Unicode, nested comments and incomplete code.');
})().catch(error => { console.error(error); process.exitCode = 1; });
