'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./load');

test('lerValorInscricao: vírgula, ponto, vazio e inválidos', () => {
  const c = load();
  assert.deepStrictEqual({ ...c.lerValorInscricao('150,50') }, { ok: true, valor: 150.5 });
  assert.deepStrictEqual({ ...c.lerValorInscricao(' 99.9 ') }, { ok: true, valor: 99.9 });
  assert.deepStrictEqual({ ...c.lerValorInscricao('0') }, { ok: true, valor: 0 });
  assert.deepStrictEqual({ ...c.lerValorInscricao('') }, { ok: true, valor: null });
  assert.deepStrictEqual({ ...c.lerValorInscricao('   ') }, { ok: true, valor: null });
  assert.strictEqual(c.lerValorInscricao('-5').ok, false);
  assert.strictEqual(c.lerValorInscricao('abc').ok, false);
  assert.strictEqual(c.lerValorInscricao('1,2,3').ok, false);
});

test('novasDistancias: ignora vazias, repetidas e as que já existem (sem diferenciar caixa)', () => {
  const c = load();
  const r = c.novasDistancias('5 km, 10 KM, , 21 km, 21 KM', ['10 km', '42 km']);
  assert.deepStrictEqual(Array.from(r), ['5 km', '21 km']);
  assert.deepStrictEqual(Array.from(c.novasDistancias('', ['a'])), []);
});

test('previaReembolso: mostra comprovante mantido no reenvio', () => {
  const c = load();
  const base = { prova: 'P', descricao: 'd', valor: 10, valorProva: null, anexo: '' };
  assert.ok(c.previaReembolso({ ...base, mantido: true }).indexOf('mantido o comprovante anterior') > -1);
  assert.ok(c.previaReembolso(base).indexOf('Comprovante: nenhum') > -1);
  assert.ok(c.previaReembolso({ ...base, anexo: 'a.pdf', mantido: true }).indexOf('a.pdf') > -1);
});
