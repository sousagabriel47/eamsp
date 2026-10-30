'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./load');

const base = { sim: '', realSup: false, realAdmin: false, spons: false };
test('rotuloAcesso cobre cada caso', () => {
  const c = load();
  const r = (o) => c.rotuloAcesso(Object.assign({}, base, o));
  assert.strictEqual(r({ sim: 'patrocinador', realSup: true, realAdmin: true }), 'Simulando a visão de patrocinador');
  assert.strictEqual(r({ sim: 'gestao', realSup: true, realAdmin: true }), 'Simulando a visão de gestão');
  assert.strictEqual(r({ sim: 'atleta', realSup: true, realAdmin: true }), 'Simulando a visão de atleta');
  assert.strictEqual(r({ spons: true }), 'Acesso de patrocinador');
  assert.strictEqual(r({ realSup: true, realAdmin: true }), 'Acesso de administrador');
  assert.strictEqual(r({ realAdmin: true }), 'Acesso de gestão');
  assert.strictEqual(r({}), 'Acesso de atleta');
});
test('dashParaPapel remove atletas só na simulação e não muta o original', () => {
  const c = load();
  const d = { atletas: [{ nome: 'A' }], situacoes: {} };
  const s = c.dashParaPapel(d, true);
  assert.ok(!('atletas' in s)); assert.deepStrictEqual({ ...s.situacoes }, {});
  assert.ok('atletas' in d);
  assert.strictEqual(c.dashParaPapel(d, false).atletas.length, 1);
  assert.strictEqual(c.dashParaPapel(null, true), null);
});
test('consultasUsuario pula dados de atleta só para patrocinador sem atleta', () => {
  const c = load();
  assert.strictEqual(c.consultasUsuario({ spons: true, atleta: false }).dados, false);
  assert.strictEqual(c.consultasUsuario({ spons: true, atleta: true }).dados, true);
  assert.strictEqual(c.consultasUsuario({ spons: false, atleta: true }).dados, true);
  assert.strictEqual(c.consultasUsuario({ spons: false, atleta: false }).dados, true);
});
