const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./load');

test('navFadeClasses: sem rolagem não mostra degradê', () => {
  const c = load();
  assert.deepStrictEqual(JSON.parse(JSON.stringify(c.navFadeClasses(0, 0))), {fl: false, fr: false});
  assert.deepStrictEqual(JSON.parse(JSON.stringify(c.navFadeClasses(1, 0))), {fl: false, fr: false});
});

test('navFadeClasses: no começo só a borda direita, no meio as duas, no fim só a esquerda', () => {
  const c = load();
  assert.deepStrictEqual(JSON.parse(JSON.stringify(c.navFadeClasses(200, 0))), {fl: false, fr: true});
  assert.deepStrictEqual(JSON.parse(JSON.stringify(c.navFadeClasses(200, 100))), {fl: true, fr: true});
  assert.deepStrictEqual(JSON.parse(JSON.stringify(c.navFadeClasses(200, 200))), {fl: true, fr: false});
});

test('navCentro: centraliza a aba ativa sem passar dos limites', () => {
  const c = load();
  // nav de 300 px, aba de 100 px a 500 px do início, conteúdo total 800 px
  assert.strictEqual(c.navCentro(500, 100, 300, 800), 400);
  // aba no começo: não fica negativo
  assert.strictEqual(c.navCentro(0, 100, 300, 800), 0);
  // aba no fim: não passa do máximo (800 - 300)
  assert.strictEqual(c.navCentro(700, 100, 300, 800), 500);
  // tudo cabe: sem rolagem
  assert.strictEqual(c.navCentro(50, 100, 300, 300), 0);
});
