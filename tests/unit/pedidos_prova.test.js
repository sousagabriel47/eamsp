'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./load');

test('textoPedidosProva: nenhum, uma pessoa e várias pessoas (singular e plural)', () => {
  const c = load();
  assert.strictEqual(c.textoPedidosProva(0), 'Ninguém pediu reembolso desta prova ainda.');
  assert.strictEqual(c.textoPedidosProva(undefined), 'Ninguém pediu reembolso desta prova ainda.');
  assert.strictEqual(c.textoPedidosProva(1), '1 pessoa já pediu reembolso desta prova.');
  assert.strictEqual(c.textoPedidosProva(2), '2 pessoas já pediram reembolso desta prova.');
  assert.strictEqual(c.textoPedidosProva(12), '12 pessoas já pediram reembolso desta prova.');
});

test('contagemPorProva: vira um mapa prova_id -> pessoas, ignorando linhas inválidas', () => {
  const c = load();
  const m = c.contagemPorProva([{prova_id: 'p1', pessoas: 2}, {prova_id: 'p2', pessoas: 1}, {prova_id: null, pessoas: 5}, {pessoas: 3}]);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(m)), {p1: 2, p2: 1});
  assert.deepStrictEqual(JSON.parse(JSON.stringify(c.contagemPorProva(null))), {});
  assert.deepStrictEqual(JSON.parse(JSON.stringify(c.contagemPorProva([]))), {});
});

test('pedidosProvaHtml: sem dados carregados não mostra nada; com dados mostra o texto escapado', () => {
  const c = load();
  assert.strictEqual(c.pedidosProvaHtml(null, 'p1'), '');
  const h = c.pedidosProvaHtml({p1: 2}, 'p1');
  assert.ok(h.includes('2 pessoas já pediram reembolso desta prova.'), h);
  assert.ok(c.pedidosProvaHtml({p1: 2}, 'p9').includes('Ninguém pediu reembolso desta prova ainda.'));
  assert.ok(!/<script/i.test(h));
});
