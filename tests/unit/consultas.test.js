'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { load } = require('./load');

// A consulta de reembolsos traz o nome do atleta (perfis). Para a API do Supabase nunca ficar em dúvida
// sobre QUAL ligação usar (erro "more than one relationship was found"), a consulta nomeia a ligação.
test('SEL_REEMBOLSOS nomeia a ligação com perfis e mantém provas(nome)', () => {
  const c = load();
  assert.strictEqual(c.SEL_REEMBOLSOS, '*, perfis!reembolsos_atleta_id_fkey(nome), provas(nome)');
});
