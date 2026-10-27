'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./load');

test('valorProva: acha pelo id e devolve null sem valor', () => {
  const c = load();
  c.P = [{ id: 'a', valor_inscricao: 100 }, { id: 'b', valor_inscricao: null }];
  assert.strictEqual(c.valorProva('a'), 100);
  assert.strictEqual(c.valorProva('b'), null);
  assert.strictEqual(c.valorProva(''), null);
  assert.strictEqual(c.valorProva('zzz'), null);
});
test('previaReembolso: mostra valor da inscrição e diferença positiva', () => {
  const c = load();
  const h = c.previaReembolso({ prova: 'Corrida X', descricao: 'Inscrição', valor: 120, valorProva: 100, anexo: 'a.pdf' });
  assert.ok(h.includes(c.money(100)));
  assert.ok(h.includes('+ ' + c.money(20)));
  assert.ok(h.includes('Diferença'));
  assert.ok(h.includes(c.money(120)));
});
test('previaReembolso: diferença negativa', () => {
  const c = load();
  const h = c.previaReembolso({ prova: '', descricao: 'x', valor: 80, valorProva: 100, anexo: '' });
  assert.ok(h.includes('- ' + c.money(20)));
});
test('previaReembolso: sem valor da prova não mostra diferença', () => {
  const c = load();
  const h = c.previaReembolso({ prova: '', descricao: 'x', valor: 120, valorProva: null, anexo: '' });
  assert.ok(!h.includes('Diferença'));
  assert.ok(!h.includes('Valor da inscrição'));
});
test('previaReembolso: escapa texto', () => {
  const c = load();
  const h = c.previaReembolso({ prova: '<i>p</i>', descricao: '<b>x</b>', valor: 1, valorProva: null, anexo: '<u>f</u>' });
  assert.ok(!h.includes('<b>x</b>'));
  assert.ok(h.includes('&lt;b&gt;x&lt;/b&gt;'));
  assert.ok(!h.includes('<i>p</i>'));
  assert.ok(!h.includes('<u>f</u>'));
});
test('historicoReembolso: ordena por data, motivo escapado, rótulo Atleta/Gestão', () => {
  const c = load();
  const r = { id: 'r1', atleta_id: 'at' };
  const hr = [
    { reembolso_id: 'r1', status_anterior: 'recusado', status_novo: 'pendente', alterado_por: 'at', alterado_em: '2026-03-05T10:00:00Z', motivo: null },
    { reembolso_id: 'r1', status_anterior: 'pendente', status_novo: 'recusado', alterado_por: 'g1', alterado_em: '2026-03-02T10:00:00Z', motivo: '<b>sem nota</b>' },
    { reembolso_id: 'outro', status_anterior: 'pendente', status_novo: 'pago', alterado_por: 'g1', alterado_em: '2026-03-01T10:00:00Z', motivo: null },
  ];
  const h = c.historicoReembolso(r, hr);
  assert.ok(h.includes('<details'));
  assert.ok(h.includes('Pendente → Recusado · Gestão · 02/03/2026 · Motivo: &lt;b&gt;sem nota&lt;/b&gt;'));
  assert.ok(h.includes('Recusado → Pendente · Atleta · 05/03/2026'));
  assert.ok(!h.includes('Pago'));
  assert.ok(h.indexOf('02/03/2026') < h.indexOf('05/03/2026'));
});
test('historicoReembolso: sem linhas devolve vazio', () => {
  const c = load();
  assert.strictEqual(c.historicoReembolso({ id: 'r1', atleta_id: 'a' }, []), '');
});
