'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./load');

test('datasRenovacao: emissão e pagamento', () => {
  const c = load();
  assert.strictEqual(c.datasRenovacao({ emitido_em: '2026-03-01', pago_em: '2026-03-05' }), 'Emitido em 01/03/2026 • Pago em 05/03/2026');
});
test('datasRenovacao: só emissão', () => {
  const c = load();
  assert.strictEqual(c.datasRenovacao({ emitido_em: '2026-03-01', pago_em: null }), 'Emitido em 01/03/2026');
});
test('datasRenovacao: sem emissão', () => {
  const c = load();
  assert.strictEqual(c.datasRenovacao({ emitido_em: null }), '');
});
