'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./load');

// Datas relativas ao today() do próprio contexto (determinístico).
function rel(c, n) {
  const d = new Date(c.today() + 'T12:00:00'); d.setDate(d.getDate() + n);
  return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2);
}
const base = { prof: null, eAtl: false, admin: false, ATL: [], R: [], REN: [], meId: 'eu' };

test('atleta com atestado vencido -> sev b', () => {
  const c = load();
  const r = c.avisosCalculados(Object.assign({}, base, { eAtl: true, prof: { atestado_validade: rel(c, -3), anuidade_ate: rel(c, 90) } }));
  assert.strictEqual(r.length, 1); assert.strictEqual(r[0].sev, 'b'); assert.match(r[0].texto, /testado/);
});
test('anuidade vencendo em 10 dias -> sev w', () => {
  const c = load();
  const r = c.avisosCalculados(Object.assign({}, base, { eAtl: true, prof: { atestado_validade: rel(c, 90), anuidade_ate: rel(c, 10) } }));
  assert.strictEqual(r.length, 1); assert.strictEqual(r[0].sev, 'w'); assert.match(r[0].texto, /nuidade/);
});
test('tudo válido por 90 dias -> nenhum aviso', () => {
  const c = load();
  const r = c.avisosCalculados(Object.assign({}, base, { eAtl: true, prof: { atestado_validade: rel(c, 90), anuidade_ate: rel(c, 90) } }));
  assert.strictEqual(r.length, 0);
});
test('gestão: pendentes excluem os próprios pedidos', () => {
  const c = load();
  const r = c.avisosCalculados(Object.assign({}, base, { admin: true, prof: {},
    R: [{ status: 'pendente', atleta_id: 'eu' }, { status: 'pendente', atleta_id: 'outro' }, { status: 'pago', atleta_id: 'outro' }],
    REN: [{ status: 'pendente', atleta_id: 'eu' }] }));
  assert.strictEqual(r.length, 1); assert.match(r[0].texto, /1 reembolso pendente/);
});
test('gestão: plural e atleta vencido pelo nome escapado', () => {
  const c = load();
  const r = c.avisosCalculados(Object.assign({}, base, { admin: true, prof: {},
    REN: [{ status: 'pendente', atleta_id: 'a' }, { status: 'pendente', atleta_id: 'b' }],
    ATL: [{ id: 'a', nome: '<b>X</b>', atestado_validade: rel(c, -1), anuidade_ate: rel(c, 90) }] }));
  assert.ok(r.some(x => /2 renovações pendentes/.test(x.texto)));
  const l = r.filter(x => x.sev === 'b')[0];
  assert.ok(l.texto.indexOf('&lt;b&gt;X&lt;/b&gt;') >= 0); assert.ok(l.texto.indexOf('<b>X') < 0);
});
test('totalAvisos soma calculados e salvos não lidos', () => {
  const c = load();
  c.prof = { atestado_validade: rel(c, -3), anuidade_ate: rel(c, 90) }; c.eAtl = true; c.me = { id: 'eu' };
  c.AV = [{ id: 1, lido_em: null }, { id: 2, lido_em: '2026-01-01' }];
  assert.strictEqual(c.totalAvisos(), 2);
});
