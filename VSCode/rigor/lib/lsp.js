'use strict';
const { spawn } = require('node:child_process');
const { EventEmitter } = require('node:events');

/** Persistent JSON-RPC/LSP connection. stdout contains framed protocol only. */
class RigorLanguageClient extends EventEmitter {
    constructor(executable, { cwd, log = () => {} } = {}) {
        super();
        this.nextId = 1;
        this.pending = new Map();
        this.buffer = Buffer.alloc(0);
        this.disposed = false;
        this.closed = false;
        this.child = spawn(executable, ['--lsp'], { cwd, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
        this.pid = this.child.pid;
        this.child.stderr.setEncoding('utf8');
        this.child.stderr.on('data', log);
        this.child.stdin.on('error', () => {});
        this.child.stdout.on('data', data => {
            try { this.accept(data); }
            catch (error) { this.fail(error); this.child.kill('SIGKILL'); }
        });
        this.child.on('error', error => this.fail(error));
        this.child.on('close', (code, signal) => {
            this.closed = true;
            this.fail(new Error(`Rigor language server stopped (${signal || code}).`));
            this.emit('close');
        });
    }

    async initialize(rootUri) {
        const result = await this.request('initialize', {
            processId: process.pid, rootUri,
            capabilities: { general: { positionEncodings: ['utf-16'] }, experimental: { rigorRevision: true } },
        });
        this.notify('initialized', {});
        return result;
    }

    send(message) {
        if (this.closed) throw new Error('Rigor language server is not running.');
        const body = Buffer.from(JSON.stringify({ jsonrpc: '2.0', ...message }));
        this.child.stdin.write(Buffer.concat([Buffer.from(`Content-Length: ${body.length}\r\n\r\n`), body]));
    }

    notify(method, params) { this.send({ method, params }); }

    request(method, params = null, timeoutMs = 15000) {
        const id = this.nextId++;
        return new Promise((resolve, reject) => {
            const timer = setTimeout(() => {
                this.pending.delete(id);
                if (!this.closed) this.notify('$/cancelRequest', { id });
                reject(new Error(`Rigor request timed out: ${method}`));
            }, timeoutMs);
            this.pending.set(id, { resolve, reject, timer });
            try { this.send({ id, method, params }); }
            catch (error) { clearTimeout(timer); this.pending.delete(id); reject(error); }
        });
    }

    accept(chunk) {
        this.buffer = Buffer.concat([this.buffer, chunk]);
        while (true) {
            const separator = this.buffer.indexOf('\r\n\r\n');
            if (separator < 0) {
                if (this.buffer.length > 8192) throw new Error('Invalid Rigor LSP header.');
                return;
            }
            const match = /^content-length:\s*(\d+)\s*$/im.exec(this.buffer.subarray(0, separator).toString('ascii'));
            if (!match || Number(match[1]) > 16 * 1024 * 1024) throw new Error('Invalid Rigor LSP message length.');
            const length = Number(match[1]);
            const start = separator + 4;
            if (this.buffer.length < start + length) return;
            const message = JSON.parse(this.buffer.subarray(start, start + length).toString('utf8'));
            this.buffer = this.buffer.subarray(start + length);
            if (message.id !== undefined && !message.method) {
                const pending = this.pending.get(message.id);
                if (!pending) continue;
                this.pending.delete(message.id);
                clearTimeout(pending.timer);
                if (message.error) {
                    const error = new Error(message.error.message);
                    error.code = message.error.code;
                    pending.reject(error);
                } else pending.resolve(message.result);
            } else if (message.method) this.emit('notification', message.method, message.params);
        }
    }

    fail(error) {
        for (const pending of this.pending.values()) { clearTimeout(pending.timer); pending.reject(error); }
        this.pending.clear();
        if (!this.disposed && !this.failed) { this.failed = true; this.emit('failure', error); }
    }

    async dispose() {
        if (this.disposed) return;
        this.disposed = true;
        if (!this.closed) {
            try { await this.request('shutdown', null, 500); this.notify('exit'); } catch {}
            this.child.stdin.end();
            if (!this.closed) {
                const timer = setTimeout(() => { if (!this.closed) this.child.kill('SIGKILL'); }, 500);
                timer.unref();
            }
        }
    }
}

module.exports = { RigorLanguageClient };
