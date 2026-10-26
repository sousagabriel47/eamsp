'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./load');

test('distanciasProva: ordena por ordem e tolera ausência', () => {
  const c = load();
  const r = c.distanciasProva({ prova_distancias: [{ id: 'b', rotulo: '10 km', ordem: 1 }, { id: 'a', rotulo: '5 km', ordem: 0 }] });
  assert.deepStrictEqual(Array.from(r, (x) => x.rotulo), ['5 km', '10 km']);
  assert.deepStrictEqual(Array.from(c.distanciasProva({})), []);
});
const prova = { nome: 'Corrida <script>x</script>', data: '2027-01-10', local: 'Parque', prova_distancias: [{ id: 'd2', rotulo: '10 km', ordem: 1 }, { id: 'd1', rotulo: '5 km', ordem: 0 }] };
test('listaTendaHtml: agrupa por distância, ordena nomes e numera', () => {
  const c = load();
  const h = c.listaTendaHtml(prova, [
    { distancia_id: 'd1', perfis: { nome: 'Bruno' } },
    { distancia_id: 'd2', perfis: { nome: 'Zeca' } },
    { distancia_id: 'd1', perfis: { nome: 'Ana' } },
  ]);
  assert.ok(h.indexOf('5 km') < h.indexOf('10 km'));
  assert.ok(h.indexOf('Ana') < h.indexOf('Bruno'));
  assert.ok(h.indexOf('Bruno') < h.indexOf('Zeca'));
  assert.ok(h.includes('10/01/2027'));
  assert.ok(h.includes('Parque'));
  assert.ok(h.includes('Assinatura'));
  assert.ok(/<td[^>]*>1<\/td>[^]*Ana[^]*<td[^>]*>2<\/td>[^]*Bruno[^]*<td[^>]*>1<\/td>[^]*Zeca/.test(h));
});
test('listaTendaHtml: escapa prova e atleta', () => {
  const c = load();
  const h = c.listaTendaHtml(prova, [{ distancia_id: 'd1', perfis: { nome: '<script>y</script>' } }]);
  assert.ok(!h.includes('<script>x'));
  assert.ok(!h.includes('<script>y'));
  assert.ok(h.includes('&lt;script&gt;y'));
});
test('listaTendaHtml: vazio mostra mensagem', () => {
  const c = load();
  assert.ok(c.listaTendaHtml(prova, []).includes('Nenhum atleta marcado'));
});
