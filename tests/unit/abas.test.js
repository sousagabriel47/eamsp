'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./load');

const base = { admin: false, sup: false, spons: false, eAtl: false, np: 0, nr: 0, ns: 0 };
function keys(o) { const c = load(); return Array.from(c.montarAbas(Object.assign({}, base, o)), (t) => t[0]); }

test('gestão sem eAtl', () => {
  assert.deepStrictEqual(keys({ admin: true }), ['cal', 'ath', 'ren', 'reb', 'dash', 'conta']);
});
test('gestão com eAtl inclui me depois de dash', () => {
  assert.deepStrictEqual(keys({ admin: true, eAtl: true }), ['cal', 'ath', 'ren', 'reb', 'dash', 'me', 'conta']);
});
test('admin (sup) completo', () => {
  assert.deepStrictEqual(keys({ admin: true, sup: true, eAtl: true }), ['cal', 'ath', 'ren', 'reb', 'dash', 'me', 'usr', 'sen', 'imp', 'conta']);
});
test('patrocinador não atleta', () => {
  assert.deepStrictEqual(keys({ spons: true }), ['dash', 'conta']);
});
test('patrocinador atleta', () => {
  assert.deepStrictEqual(keys({ spons: true, eAtl: true }), ['dash', 'cal', 'me', 'reb', 'conta']);
});
test('atleta inalterado', () => {
  assert.deepStrictEqual(keys({}), ['cal', 'me', 'reb', 'conta']);
});
test('contadores nos rótulos', () => {
  const c = load();
  const t = Array.from(c.montarAbas(Object.assign({}, base, { admin: true, sup: true, np: 2, nr: 3, ns: 4 })), (x) => x[1]);
  assert.ok(t.includes('Renovações (2)')); assert.ok(t.includes('Reembolsos (3)')); assert.ok(t.includes('Senhas (4)'));
  assert.ok(t.includes('Dashboard')); assert.strictEqual(t[t.length - 1], 'Minha conta');
});
