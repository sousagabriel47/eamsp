'use strict';
// Executa app.js (script de navegador ES5) num contexto vm com stubs e
// devolve o contexto; declarações function/var de topo viram propriedades dele.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function load() {
  const src = fs.readFileSync(path.join(__dirname, '..', '..', 'app.js'), 'utf8');
  const el = () => ({ innerHTML: '', hidden: false, addEventListener() {} });
  const ctx = {
    document: { querySelector: el, addEventListener() {} },
    location: { hash: '', pathname: '/', search: '' },
    crypto: { randomUUID: () => '00000000-0000-4000-8000-000000000000' },
    alert() {}, prompt() { return null; }, confirm() { return false; },
    setTimeout, clearTimeout, console,
  };
  ctx.window = ctx;
  Object.defineProperty(ctx, 'localStorage', {
    get() { throw new Error('localStorage indisponível'); },
  });
  vm.runInNewContext(src, ctx, { filename: 'app.js' });
  return ctx;
}

module.exports = { load };
