'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./load');

const rs = [
  { id: 'a', valor: 100, status: 'aprovado', atleta_id: 'x' },
  { id: 'b', valor: 50, status: 'aprovado', atleta_id: 'x' },
  { id: 'c', valor: 10, status: 'aprovado', atleta_id: 'eu' },
  { id: 'd', valor: 5, status: 'pendente', atleta_id: 'x' },
  { id: 'e', valor: 7, status: 'pago', atleta_id: 'x' },
];
test('lotePodeSelecionar: só aprovado de outro atleta', () => {
  const c = load();
  assert.strictEqual(c.lotePodeSelecionar(rs[0], 'eu'), true);
  assert.strictEqual(c.lotePodeSelecionar(rs[2], 'eu'), false);
  assert.strictEqual(c.lotePodeSelecionar(rs[3], 'eu'), false);
  assert.strictEqual(c.lotePodeSelecionar(rs[4], 'eu'), false);
});
test('loteResumo: soma só elegíveis e devolve ids', () => {
  const c = load();
  const r = c.loteResumo({ a: true, b: true, c: true, d: true, e: true, zz: true }, rs, 'eu');
  assert.strictEqual(r.n, 2); assert.strictEqual(r.total, 150);
  assert.deepStrictEqual(Array.from(r.ids), ['a', 'b']);
  const v = c.loteResumo({}, rs, 'eu');
  assert.strictEqual(v.n, 0); assert.strictEqual(v.total, 0); assert.strictEqual(v.ids.length, 0);
});
test('loteBarraHtml: resumo, data e escape; vazia com n = 0', () => {
  const c = load();
  const h = c.loteBarraHtml({ n: 2, total: 150, ids: ['a', 'b'] }, '2026-10-30');
  assert.ok(h.includes('2 selecionados')); assert.ok(h.includes(c.money(150)));
  assert.ok(h.includes('id="lotedata"')); assert.ok(h.includes('value="2026-10-30"'));
  assert.ok(h.includes('data-lote="1"')); assert.ok(h.includes('data-lotelimpa="1"'));
  assert.ok(!h.includes('<script'));
  assert.ok(c.loteBarraHtml({ n: 1, total: 5, ids: ['a'] }, '"><script>').indexOf('<script') < 0);
  assert.strictEqual(c.loteBarraHtml({ n: 0, total: 0, ids: [] }, ''), '');
});
