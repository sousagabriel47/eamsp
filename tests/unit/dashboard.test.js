'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./load');

const nb = (s) => String(s).replace(/ /g, ' ');
const sit = (o) => Object.assign({
  pendente: { qtd: 0, valor: 0 }, aprovado: { qtd: 0, valor: 0 }, pago: { qtd: 0, valor: 0 },
  recusado: { qtd: 0, valor: 0 }, cancelado: { qtd: 0, valor: 0 } }, o);

test('periodoDash', () => {
  const c = load();
  assert.deepStrictEqual({ ...c.periodoDash('mes', '2026-10-30') }, { de: '2026-10-01', ate: '2026-10-30' });
  assert.deepStrictEqual({ ...c.periodoDash('3m', '2026-10-30') }, { de: '2026-08-01', ate: '2026-10-30' });
  assert.deepStrictEqual({ ...c.periodoDash('3m', '2026-01-15') }, { de: '2025-11-01', ate: '2026-01-15' });
  assert.deepStrictEqual({ ...c.periodoDash('ano', '2026-10-30') }, { de: '2026-01-01', ate: '2026-10-30' });
  assert.deepStrictEqual({ ...c.periodoDash('tudo', '2026-10-30') }, { de: null, ate: null });
});
test('cartoesDash mostra valor, quantidade e destaca a pagar', () => {
  const c = load();
  const h = nb(c.cartoesDash({ situacoes: sit({ aprovado: { qtd: 3, valor: 1234.5 } }) }));
  assert.match(h, /R\$ 1\.234,50/); assert.match(h, /3/); assert.match(h, /a pagar/i);
  assert.match(h, /dcard hi/);
});
test('barrasMesDash proporcional e sem NaN', () => {
  const c = load();
  const h = c.barrasMesDash({ meses: [{ mes: '2026-09', solicitado: 50, pago: 25 }, { mes: '2026-10', solicitado: 100, pago: 0 }] });
  assert.match(h, /style="width:100%"/); assert.match(h, /style="width:50%"/); assert.match(h, /style="width:25%"/);
  assert.doesNotMatch(h, /NaN/);
  const z = c.barrasMesDash({ meses: [{ mes: '2026-10', solicitado: 0, pago: 0 }] });
  assert.match(z, /style="width:0%"/); assert.doesNotMatch(z, /NaN/);
});
test('rankingProvaDash escapa nome', () => {
  const c = load();
  const h = c.rankingProvaDash({ provas: [{ prova: '<b>x</b>', qtd: 2, valor: 10 }] });
  assert.doesNotMatch(h, /<b>x<\/b>/); assert.match(h, /&lt;b&gt;x&lt;\/b&gt;/);
});
test('atletasDash', () => {
  const c = load();
  assert.strictEqual(c.atletasDash({}), '');
  const h = c.atletasDash({ atletas: [{ nome: '<i>Ana</i>', pediu: 10, recebeu: 5, a_receber: 5 }] });
  assert.doesNotMatch(h, /<i>Ana/); assert.match(h, /&lt;i&gt;Ana/); assert.match(h, /Por atleta/);
});
test('dashVazio e viewDash', () => {
  const c = load();
  assert.strictEqual(c.dashVazio({ situacoes: sit({}) }), true);
  assert.strictEqual(c.dashVazio({ situacoes: sit({ pago: { qtd: 1, valor: 1 } }) }), false);
  c.DASH = { situacoes: sit({}), meses: [], provas: [], tempo_medio_dias: null };
  assert.match(c.viewDash(), /Sem dados no período/);
});
test('tempoMedioDash', () => {
  const c = load();
  assert.match(c.tempoMedioDash({ tempo_medio_dias: null }), /—/);
  assert.match(c.tempoMedioDash({ tempo_medio_dias: 3.5 }), /3,5 dias/);
});

test('dashEstado', () => {
  const c = load();
  const vazio = { situacoes: sit({}) }, cheio = { situacoes: sit({ pago: { qtd: 1, valor: 1 } }) };
  assert.strictEqual(c.dashEstado({ dash: null, loading: true, erro: false }), 'carregando');
  assert.strictEqual(c.dashEstado({ dash: null, loading: false, erro: false }), 'carregando');
  assert.strictEqual(c.dashEstado({ dash: null, loading: false, erro: true }), 'erro');
  assert.strictEqual(c.dashEstado({ dash: vazio, loading: false, erro: false }), 'vazio');
  assert.strictEqual(c.dashEstado({ dash: cheio, loading: false, erro: false }), 'ok');
});
test('viewDash em erro mostra botão de nova tentativa', () => {
  const c = load();
  c.DASH = null; c.DASH_ERRO = true;
  const h = c.viewDash();
  assert.match(h, /Não foi possível carregar o dashboard/); assert.match(h, /data-dashretry/);
});
test('barras: valor não nulo tem ao menos 1% de largura', () => {
  const c = load();
  const h = c.barrasMesDash({ meses: [{ mes: '2026-10', solicitado: 100000, pago: 1 }] });
  assert.match(h, /class="p" style="width:1%"/); assert.match(h, /class="s" style="width:100%"/);
  const z = c.barrasMesDash({ meses: [{ mes: '2026-10', solicitado: 5, pago: 0 }] });
  assert.match(z, /class="p" style="width:0%"/);
});
