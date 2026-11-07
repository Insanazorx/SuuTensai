'use strict';
const { randomBytes } = require('node:crypto');

/** An editor beside the source, updated without moving the caret or focus. */
class RigorInfoView {
    constructor(vscode, navigate) {
        this.vscode = vscode;
        this.navigate = navigate;
        this.snapshot = { state: 'empty', fileName: '', diagnostics: [], declarations: [], axioms: [] };
        this.closedByUser = false;
    }

    show({ automatic = false } = {}) {
        if (automatic && this.closedByUser) return;
        if (this.panel) {
            if (!automatic) this.panel.reveal(this.panel.viewColumn, true);
            return;
        }
        this.closedByUser = false;
        const panel = this.vscode.window.createWebviewPanel('rigor.infoview', 'Rigor — Canlı Kontrol',
            { viewColumn: this.vscode.ViewColumn.Beside, preserveFocus: true },
            { enableScripts: true, retainContextWhenHidden: true, localResourceRoots: [] });
        this.panel = panel;
        panel.webview.html = html();
        panel.webview.onDidReceiveMessage(message => {
            if (message?.type === 'ready') this.update(this.snapshot);
            if (message?.type === 'rendered') this.rendered = { version: message.version, state: message.state };
            if (message?.type === 'goTo' && Number.isInteger(message.index)) {
                const diagnostic = this.snapshot.diagnostics[message.index];
                if (diagnostic) this.navigate(diagnostic);
            }
        });
        panel.onDidDispose(() => { this.panel = undefined; this.closedByUser = true; this.rendered = undefined; });
        this.update(this.snapshot);
    }

    update(snapshot) {
        this.snapshot = snapshot;
        if (this.panel) void this.panel.webview.postMessage({ type: 'update', snapshot });
    }

    getState() {
        return { visible: !!this.panel?.visible, viewColumn: this.panel?.viewColumn,
            snapshot: this.snapshot, rendered: this.rendered };
    }

    dispose() { this.panel?.dispose(); }
}

function html() {
    const nonce = randomBytes(16).toString('hex');
    return `<!DOCTYPE html><html lang="tr"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}';">
<style nonce="${nonce}">
body{font:var(--vscode-font-size)/1.6 var(--vscode-font-family);color:var(--vscode-foreground);padding:22px;max-width:900px;margin:0 auto}
header{border-bottom:1px solid var(--vscode-panel-border);padding-bottom:18px;margin-bottom:20px}
h1{font-size:17px;margin:0 0 8px}h2{font-size:12px;text-transform:uppercase;letter-spacing:.07em;color:var(--vscode-descriptionForeground);margin:24px 0 9px}
p{margin:8px 0}.file,code{font-family:var(--vscode-editor-font-family);overflow-wrap:anywhere}.file,.meta{font-size:12px;color:var(--vscode-descriptionForeground)}
.status{display:flex;align-items:center;gap:8px;font-weight:600}.dot{width:8px;height:8px;border-radius:50%;background:var(--vscode-descriptionForeground)}
body[data-state="checked"] .dot{background:var(--vscode-testing-iconPassed)}body[data-state="error"] .dot{background:var(--vscode-errorForeground)}
body[data-state="checking"] .dot{background:var(--vscode-progressBar-background);animation:pulse 1s infinite}
@keyframes pulse{50%{opacity:.25}}.error{padding:12px 14px;border-left:3px solid var(--vscode-errorForeground);background:var(--vscode-textBlockQuote-background);margin:12px 0;white-space:pre-wrap;overflow-wrap:anywhere}
button{color:var(--vscode-textLink-foreground);border:0;background:none;padding:4px 0;font:inherit;cursor:pointer;text-align:left}button:hover{text-decoration:underline}button:focus-visible{outline:1px solid var(--vscode-focusBorder)}
ul{list-style:none;padding:0;margin:0}li{padding:5px 0;border-bottom:1px solid var(--vscode-panel-border)}.none{color:var(--vscode-descriptionForeground)}[hidden]{display:none!important}
</style></head><body data-state="empty"><header><h1>Rigor</h1><div class="file" id="file"></div></header>
<div class="status"><span class="dot"></span><span id="status">Bir Rigor dosyası aç</span></div>
<p class="meta" id="meta"></p><div id="message"></div><section id="errors"></section>
<section id="verified" hidden><h2>Doğrulanan bildirimler</h2><ul id="declarations"></ul></section>
<section id="assumptions" hidden><h2>Aksiyom bağımlılıkları</h2><ul id="axioms"></ul></section>
<script nonce="${nonce}">
const vscode=acquireVsCodeApi();const byId=id=>document.getElementById(id);
function list(id,values){byId(id).replaceChildren(...values.map(value=>{const li=document.createElement('li');const code=document.createElement('code');code.textContent=value;li.append(code);return li;}));}
function render(data){document.body.dataset.state=data.state;byId('file').textContent=data.fileName||'';
const labels={checking:'Kontrol ediliyor…',checked:'Doğrulandı',error:'Düzeltme gerekiyor',empty:'Bir bildirim yaz',disabled:'Canlı kontrol kapalı',failure:'Checker başlatılamadı',noDocument:'Bir Rigor dosyası aç'};
byId('status').textContent=labels[data.state]||data.state;byId('meta').textContent=data.version===undefined?'':('Sürüm '+data.version+(data.dirty?' · Kaydedilmemiş metin':'')+(data.elapsedMs===undefined?'':' · '+data.elapsedMs+' ms'));
byId('message').textContent=data.message||'';byId('errors').replaceChildren();
data.diagnostics.forEach((error,index)=>{const box=document.createElement('div');box.className='error';const text=document.createElement('div');text.textContent=error.message;const button=document.createElement('button');button.textContent=(error.fileName.split(/[\\/]/).pop())+' · '+(error.range.start.line+1)+':'+(error.range.start.character+1);button.onclick=()=>vscode.postMessage({type:'goTo',index});box.append(text,button);byId('errors').append(box);});
byId('verified').hidden=!data.declarations.length;list('declarations',data.declarations);byId('assumptions').hidden=data.state!=='checked';list('axioms',data.axioms.length?data.axioms:['Yok']);
vscode.postMessage({type:'rendered',version:data.version,state:data.state});}
window.addEventListener('message',event=>{if(event.data.type==='update')render(event.data.snapshot);});vscode.postMessage({type:'ready'});
</script></body></html>`;
}

module.exports = { RigorInfoView, html };
