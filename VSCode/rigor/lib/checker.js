'use strict';
const { spawn } = require('node:child_process');

function runChecker(executable, request, { cwd, signal, timeoutMs = 15000 } = {}) {
    return new Promise((resolve, reject) => {
        if (signal?.aborted) return reject(aborted());
        const child = spawn(executable, ['--lint-json'], { cwd, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
        child.stdout.setEncoding('utf8');
        child.stderr.setEncoding('utf8');
        let stdout = '';
        let stderr = '';
        let failure;
        const timeout = setTimeout(() => {
            failure = new Error('Rigor check timed out after 15 seconds.');
            child.kill('SIGKILL');
        }, timeoutMs);
        const cancel = () => { failure = aborted(); child.kill('SIGKILL'); };
        signal?.addEventListener('abort', cancel, { once: true });
        child.stdin.on('error', () => {}); // Early process exit is reported by close/error.
        child.stdout.on('data', chunk => {
            stdout += chunk;
            if (stdout.length > 1024 * 1024) {
                failure = new Error('Rigor checker output is too large.');
                child.kill('SIGKILL');
            }
        });
        child.stderr.on('data', chunk => { stderr = (stderr + chunk).slice(-8192); });
        const cleanup = () => { clearTimeout(timeout); signal?.removeEventListener('abort', cancel); };
        child.on('error', error => { cleanup(); reject(error); });
        child.on('close', code => {
            cleanup();
            if (failure) return reject(failure);
            if (code !== 0) return reject(new Error(stderr.trim() || `Rigor checker exited with code ${code}.`));
            try {
                const report = JSON.parse(stdout);
                if (!Array.isArray(report.diagnostics) || !Array.isArray(report.declarations)) throw new Error('Unexpected JSON shape');
                resolve(report);
            } catch (error) { reject(new Error(`Invalid checker response: ${error.message}`)); }
        });
        child.stdin.end(JSON.stringify(request));
    });
}

function aborted() { const error = new Error('Rigor check cancelled'); error.name = 'AbortError'; return error; }
module.exports = { runChecker };
