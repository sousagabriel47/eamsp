# Melhorias EAMSP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Entregar Renovações (emissão/pagamento), Reembolso (valor da inscrição, prévia, reenvio, histórico), Calendário (distâncias, "Vou correr", lista da tenda) e Avisos internos no sistema EAMSP.

**Architecture:** Site estático (`index.html` + `app.js`, sem build) sobre Supabase com RLS. Regras ficam no banco (gatilhos, políticas, RPCs) em `migracao_v2.sql` idempotente, dobrado ao final em `schema.sql`. A interface continua em `app.js` (ES5, strings HTML, `esc()` em todo texto vindo do banco); funções puras novas são testáveis em Node.

**Tech Stack:** PostgreSQL 16 / Supabase (RLS, plpgsql), JavaScript ES5 no navegador, `node:test` (Node 22) para funções puras, `psql` local para o SQL.

**Spec:** `docs/superpowers/specs/2026-10-26-melhorias-eamsp-design.md`

## Global Constraints

- Idioma da interface e das mensagens de erro do banco: português do Brasil.
- Sem build, sem dependências novas, sem arquivos guardados (só PDFs já existentes no bucket `anexos`).
- Toda tabela nova: `revoke all ... from anon`, RLS ligada, políticas no padrão das atuais (`public.is_gestao()`, `public.is_atleta()`, `(select auth.uid())`).
- Funções `security definer` usam `set search_path = ''` e nomes qualificados `public.`.
- `migracao_v2.sql` é idempotente (`if not exists`, `create or replace`, `drop ... if exists`) e pode rodar duas vezes sem erro.
- Em `app.js`: todo texto do banco passa por `esc()`; ações novas de gravação entram na guarda do modo simulação (`if (sim && (...)) { alert(MSGSIM); return; }`) ou checam `sim` no submit.
- Valores monetários: `numeric(10,2)`; exibição com `money()`; datas com `br()`.
- Status existentes de reembolso: `pendente, aprovado, pago, recusado, cancelado`; de renovação: `pendente, aprovada, recusada, cancelada`.
- Ninguém valida a própria solicitação (regra existente; preservar).
- Commits em português, um por tarefa, na branch `claude/clever-hamilton-kth6uh`.

## Review Focus

- Prova sem valor de inscrição (`null`): reembolso segue com valor manual e a prévia não mostra diferença.
- Prova com lista de presença e sem distâncias cadastradas: "Vou correr" não aparece e a gestão é avisada ao cadastrar.
- Nome de atleta/prova com `<`, `&` ou aspas na lista da tenda e nos avisos: deve sair escapado.
- Prova excluída ou distância removida com atletas marcados: marcações somem junto (cascade) e a lista da tenda vazia diz "Nenhum atleta marcado".
- Reenvio de reembolso por quem não é o dono, ou de pedido pago/aprovado/cancelado: o banco recusa. Emissão futura ou pagamento em atestado: o banco recusa.

---

## File Structure

- `migracao_v2.sql` (criar): todas as mudanças de banco, seções numeradas por tarefa.
- `schema.sql` (modificar na Task 8): recebe o mesmo conteúdo antes da seção `-- 5) PRIMEIRO ACESSO` e novos casos no roteiro `-- 6) TESTE DE PERMISSÕES`.
- `app.js` (modificar): telas e fluxos; funções puras novas agrupadas num bloco `/* ---------- Funções puras ---------- */` logo antes de `/* ---------- Telas ---------- */`.
- `index.html` (modificar na Task 7): botão do sino.
- `tests/sql/run.sh`, `tests/sql/00_stub.sql`, `tests/sql/NN_*.sql` (criar): harness e testes do banco.
- `tests/unit/load.js`, `tests/unit/*.test.js` (criar): carrega `app.js` num `vm` com stubs e testa as funções puras.
- `README.md` (modificar na Task 8).

---

### Task 0: Harness de testes

**Files:**
- Create: `tests/sql/run.sh`, `tests/sql/00_stub.sql`, `tests/unit/load.js`, `tests/unit/smoke.test.js`

**Interfaces:**
- Produces: `bash tests/sql/run.sh` (aplica stub + `schema.sql` + `migracao_v2.sql` duas vezes num PostgreSQL temporário e executa cada `tests/sql/[1-9]*.sql` com `psql -v ON_ERROR_STOP=1`; sai com código ≠ 0 se qualquer um falhar). `load(): object` em `tests/unit/load.js` devolve o contexto `vm` com as funções globais de `app.js` (ex.: `ctx.money`).

- [ ] **Step 1: Escrever `tests/unit/smoke.test.js`**: teste `carrega app.js e expõe money()` afirmando `load().money(1234.5)` contém `1.234,50`.
- [ ] **Step 2: Rodar** `node --test tests/unit/` — Expected: FAIL (`load` não existe).
- [ ] **Step 3: Implementar `tests/unit/load.js`**: lê `app.js`, executa com `vm.runInNewContext` num contexto com `document` (`querySelector` devolve objeto com `innerHTML`, `hidden`, `addEventListener` no-op), `location` (`hash:''`, `pathname:'/'`, `search:''`), `window`, `localStorage` que lança, `crypto`, `alert`, `prompt`, `confirm`, e `SUPABASE_URL` indefinida (o IIFE final cai no ramo "Falta configurar"). Declarações `function` e `var` de topo ficam no contexto.
- [ ] **Step 4: Rodar** `node --test tests/unit/` — Expected: PASS.
- [ ] **Step 5: Escrever `tests/sql/00_stub.sql`**: cria papéis `anon, authenticated, service_role`, schemas `auth` e `storage`, tabela `auth.users (id uuid pk, email text, raw_user_meta_data jsonb, recovery_sent_at timestamptz, banned_until timestamptz)`, função `auth.uid()` lendo `current_setting('request.jwt.claim.sub', true)::uuid`, e as tabelas mínimas de `storage` que o `schema.sql` referencia (`storage.buckets`, `storage.objects` com RLS) — ajuste até `schema.sql` aplicar sem erro.
- [ ] **Step 6: Implementar `tests/sql/run.sh`**: `initdb` em diretório temporário pertencente ao usuário `postgres` (rodar via `su postgres -c`), `pg_ctl start` em porta livre, `createdb`, aplicar stub, `schema.sql`, `migracao_v2.sql` (duas vezes, se existir), depois os testes; `pg_ctl stop` num `trap EXIT`. Helper SQL por teste: `set local role authenticated; select set_config('request.jwt.claim.sub', '<uuid>', true);` para simular usuários.
- [ ] **Step 7: Rodar** `bash tests/sql/run.sh` — Expected: aplica `schema.sql` sem erro e termina com código 0 (ainda sem testes).
- [ ] **Step 8: Commit** `test: harness de testes SQL e de funções puras`

---

### Task 1: Renovações — emissão e pagamento (banco + tela)

**Files:**
- Create: `migracao_v2.sql` (seção `-- V2.1`), `tests/sql/10_renovacoes.sql`, `tests/unit/renovacoes.test.js`
- Modify: `app.js` (`viewRen`, handler `data-rn`, nova ação `data-em`, `refresh`)

**Interfaces:**
- Produces (banco): colunas `renovacoes.emitido_em date`, `renovacoes.pago_em date`; tabela `renovacao_emissao_historico(id, renovacao_id, anterior date, novo date, alterado_por uuid, alterado_em timestamptz)` legível só pela gestão; RPC `public.editar_emissao_renovacao(p_id uuid, p_emissao date) returns void` (só gestão, só renovação `aprovada`, não a própria, emissão ≤ hoje, grava histórico); `grant update (status, motivo_decisao, emitido_em, pago_em)` para `authenticated`.
- Produces (app): `function datasRenovacao(x): string` — texto `Emitido em dd/mm/aaaa` + `• Pago em dd/mm/aaaa` (só se `pago_em`), ou `''` se sem emissão.

Regras do gatilho `decidir_renovacao` (substituir com `create or replace`, mantendo as regras atuais): ao **aprovar**, `emitido_em` é obrigatório e ≤ `current_date`; `pago_em` só é aceito para `tipo = 'anuidade'` e ≤ `current_date`; ao **recusar** ou **cancelar**, `emitido_em`/`pago_em` não podem mudar (erro `Datas só podem ser informadas na aprovação.`).

- [ ] **Step 1: Escrever `tests/sql/10_renovacoes.sql`** com asserts (`do $$ ... assert ... $$`): (a) gestão aprova atestado sem emissão → erro; (b) com emissão futura → erro; (c) atestado com `pago_em` → erro; (d) anuidade com emissão e pagamento → aprovada, perfil atualizado; (e) atleta tentando gravar `emitido_em` ao cancelar → erro; (f) `editar_emissao_renovacao` por gestão grava histórico com `anterior`/`novo`; por atleta → erro; na própria renovação → erro.
- [ ] **Step 2: Rodar** `bash tests/sql/run.sh` — Expected: FAIL (colunas inexistentes).
- [ ] **Step 3: Implementar** a seção `-- V2.1` em `migracao_v2.sql` (colunas, tabela de histórico com RLS e política `select` para `is_gestao()`, gatilho, RPC, grants).
- [ ] **Step 4: Rodar** `bash tests/sql/run.sh` — Expected: PASS.
- [ ] **Step 5: Escrever `tests/unit/renovacoes.test.js`**: `datasRenovacao({emitido_em:'2026-03-01', pago_em:'2026-03-05'})` → `Emitido em 01/03/2026 • Pago em 05/03/2026`; sem `pago_em` → só a emissão; sem emissão → `''`.
- [ ] **Step 6: Implementar** `datasRenovacao` no bloco de funções puras; em `viewRen` mostrar `datasRenovacao(x)` nas decididas e botão "Corrigir emissão" (`data-em="<id>"`) nas aprovadas; no handler `data-rn`, ao aprovar, trocar o `confirm` por dois `prompt`: emissão (obrigatória, aceita `dd/mm/aaaa` ou `aaaa-mm-dd` via `parseData`) e, só para anuidade, pagamento (opcional); enviar em `w.emitido_em`/`w.pago_em`. Handler `data-em`: `prompt` da nova emissão, `sb.rpc('editar_emissao_renovacao', {p_id, p_emissao})`. Incluir `data-em` na guarda de simulação. `viewMine` mostra `datasRenovacao` nas aprovadas.
- [ ] **Step 7: Rodar** `node --test tests/unit/` e `node --check app.js` — Expected: PASS.
- [ ] **Step 8: Commit** `feat: data de emissão e pagamento nas renovações`

---

### Task 2: Reembolso — banco

**Files:**
- Modify: `migracao_v2.sql` (seção `-- V2.2`)
- Create: `tests/sql/20_reembolso.sql`

**Interfaces:**
- Produces: `provas.valor_inscricao numeric(10,2) check (valor_inscricao is null or valor_inscricao >= 0)`; `reembolsos.valor_prova numeric(10,2)` preenchido pelo gatilho `before insert` (e no reenvio) com `provas.valor_inscricao` da prova escolhida, ignorando o que o cliente mandar; `reembolso_historico` ganha `motivo text` e `valor numeric(10,2)`; novo status permitido `recusado → pendente` (só o dono); política `reembolsos_atleta_reenviar`; `grant update (status, motivo_decisao, prova_id, descricao, valor, anexo_path)`; política de leitura do histórico para o dono do reembolso.

Regras do gatilho `registrar_mudanca_reembolso` (substituir com `create or replace`, preservando as atuais): alterar `prova_id/descricao/valor/anexo_path` só é permitido na transição `recusado → pendente` feita pelo dono (erro `Só é possível editar um pedido recusado ao reenviá-lo.`); no reenvio zera `motivo_decisao`, `decidido_por`, `decidido_em` e recalcula `valor_prova`; toda mudança de status grava em `reembolso_historico` `motivo = new.motivo_decisao` (quando recusado) e `valor = new.valor`.

- [ ] **Step 1: Escrever `tests/sql/20_reembolso.sql`**: (a) insert com `valor_prova` forjado → gravado com o valor real da prova (ou `null` se prova sem valor / sem prova); (b) gestão recusa com motivo → histórico com motivo e valor; (c) dono reenvia alterando valor → status `pendente`, `motivo_decisao` nulo, nova linha de histórico `recusado→pendente`; (d) outro atleta reenviando → erro; (e) reenviar pedido `pago`, `aprovado`, `cancelado` → erro; (f) editar `valor` de pedido `pendente` sem mudar status → erro; (g) dono lê o próprio histórico, outro atleta não.
- [ ] **Step 2: Rodar** `bash tests/sql/run.sh` — Expected: FAIL.
- [ ] **Step 3: Implementar** a seção `-- V2.2` (colunas, gatilho de insert, gatilho de update, políticas, grants).
- [ ] **Step 4: Rodar** `bash tests/sql/run.sh` — Expected: PASS (inclusive a segunda aplicação idempotente de `migracao_v2.sql`).
- [ ] **Step 5: Commit** `feat: valor da inscrição, reenvio e histórico de reembolso no banco`

---

### Task 3: Reembolso — tela

**Files:**
- Modify: `app.js` (`viewReb`, `refresh`, submit do `tab == 'reb'`, handlers de clique), `viewCal` (campo de valor da inscrição, ver Task 5 para o restante do formulário)
- Create: `tests/unit/reembolso.test.js`

**Interfaces:**
- Consumes: Task 2 (colunas e regras).
- Produces: globais `HR = []` (linhas de `reembolso_historico`, carregadas em `refresh` com `order('alterado_em')`), `previa = null`, `editRb = ''`; `function valorProva(provaId: string): number|null` (usa `P`); `function previaReembolso(d: {prova: string, descricao: string, valor: number, valorProva: number|null, anexo: string}): string` (HTML; mostra "Valor da inscrição" e "Diferença" só se `valorProva != null`; tudo escapado); `function historicoReembolso(r, hr): string` (HTML `<details>` com linhas "Pendente → Recusado · Gestão · dd/mm/aaaa · Motivo: …", rótulo "Atleta" quando `alterado_por === r.atleta_id`, senão "Gestão").

- [ ] **Step 1: Escrever `tests/unit/reembolso.test.js`**: `previaReembolso` com `valor 120`, `valorProva 100` contém `R$ 100,00` e `+ R$ 20,00` (formato com `money`) ; com `valorProva null` não contém "Diferença"; `descricao '<b>x</b>'` sai escapada; `historicoReembolso` ordena por data, mostra o motivo escapado da recusa e o rótulo "Atleta" no reenvio.
- [ ] **Step 2: Rodar** `node --test tests/unit/` — Expected: FAIL.
- [ ] **Step 3: Implementar** as funções puras e `valorProva`.
- [ ] **Step 4: Implementar a tela**: `<select name="p">` com `onchange` preenchendo o campo valor com `valorProva` (se houver); o submit do formulário passa a abrir a prévia (`previa = {...incluindo o File}`; `render()` mostra `previaReembolso` + botões `data-rbok` "Confirmar envio" e `data-rbno` "Voltar" no lugar do formulário); `data-rbok` faz o upload (`prepararAnexo`) e o `insert` já existente, ou o `update` do reenvio quando `editRb` está definido (`{prova_id, descricao, valor, anexo_path, status:'pendente'}`, mantendo o `anexo_path` antigo se não houver arquivo novo); recusados do próprio atleta ganham "Corrigir e reenviar" (`data-rv="<id>"` → `editRb`, formulário preenchido, título "Reenviar reembolso"); cada pedido mostra `historicoReembolso`. `data-rbok`, `data-rv` entram na guarda de simulação. Em `viewCal`, adicionar `<label>Valor da inscrição (R$)<input type="number" name="v" step="0.01" min="0">` e gravar `valor_inscricao`.
- [ ] **Step 5: Rodar** `node --test tests/unit/` e `node --check app.js` — Expected: PASS.
- [ ] **Step 6: Verificar no navegador** (Playwright já instalado) com um `supabase` falso injetado antes de `app.js`: atleta escolhe prova de R$ 100, valor vem 100, altera para 120, vê a prévia com diferença, confirma; pedido recusado mostra "Corrigir e reenviar" e histórico. Capturar tela e anexar ao relato.
- [ ] **Step 7: Commit** `feat: prévia, reenvio e histórico de aprovação no reembolso`

---

### Task 4: Calendário — banco

**Files:**
- Modify: `migracao_v2.sql` (seção `-- V2.3`)
- Create: `tests/sql/30_calendario.sql`

**Interfaces:**
- Produces: `provas.tem_lista_presenca boolean not null default false`; `prova_distancias(id uuid pk, prova_id uuid → provas on delete cascade, rotulo text not null, ordem int not null default 0, unique (id, prova_id))` (todos leem; gestão escreve); `prova_participantes(prova_id, atleta_id → perfis on delete cascade, distancia_id, criado_em, primary key (prova_id, atleta_id), foreign key (distancia_id, prova_id) → prova_distancias (id, prova_id) on delete cascade)`. Políticas: atleta (`is_atleta()`) insere/atualiza/apaga só a própria linha e só em prova com `data >= current_date`; leitura da própria linha ou `is_gestao()`. Migração de dados: para cada prova com `distancia` não vazia e sem linhas em `prova_distancias`, inserir uma linha com esse texto.

- [ ] **Step 1: Escrever `tests/sql/30_calendario.sql`**: (a) texto antigo de `distancia` vira linha em `prova_distancias`, sem duplicar na segunda aplicação; (b) atleta A marca a prova e B não vê a linha de A; gestão vê; (c) A usando distância de outra prova → erro; (d) A marcando prova passada → erro; (e) A apagando a linha de B → 0 linhas afetadas; (f) apagar a prova remove participantes; (g) não-gestão inserindo distância → erro.
- [ ] **Step 2: Rodar** `bash tests/sql/run.sh` — Expected: FAIL.
- [ ] **Step 3: Implementar** a seção `-- V2.3`.
- [ ] **Step 4: Rodar** `bash tests/sql/run.sh` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: distâncias, participantes e lista de presença no banco`

---

### Task 5: Calendário — tela e lista da tenda

**Files:**
- Modify: `app.js` (`viewCal`, `refresh`, submit do `tab == 'cal'`, handlers de clique)
- Create: `tests/unit/calendario.test.js`

**Interfaces:**
- Consumes: Task 4.
- Produces: `refresh` carrega `provas` com `select('*, prova_distancias(id,rotulo,ordem)')` e `PART` (`prova_participantes` com `perfis(nome)`); `function distanciasProva(p): Array<{id,rotulo}>` (ordenadas por `ordem`); `function listaTendaHtml(p, parts: Array<{distancia_id, perfis:{nome}}>): string` — documento HTML completo para impressão (título com nome, data e local; um bloco por distância na ordem; nomes em ordem alfabética `localeCompare('pt-BR')`; colunas Nº / Nome / Assinatura; "Nenhum atleta marcado" quando vazio; tudo escapado).

- [ ] **Step 1: Escrever `tests/unit/calendario.test.js`**: `distanciasProva` ordena por `ordem`; `listaTendaHtml` agrupa por distância na ordem das distâncias, ordena nomes alfabeticamente ("Ana" antes de "Bruno"), numera a partir de 1 em cada grupo, escapa `<script>` no nome da prova e do atleta, e com `parts = []` contém "Nenhum atleta marcado".
- [ ] **Step 2: Rodar** `node --test tests/unit/` — Expected: FAIL.
- [ ] **Step 3: Implementar** as funções puras.
- [ ] **Step 4: Implementar a tela**: formulário da gestão troca o campo "Distância" por "Distâncias (separadas por vírgula)" (`name="k"`) e acrescenta checkbox "Tem lista de presença" (`name="lp"`); o submit passa a `insert(...).select('id').single()` e depois insere `prova_distancias` (rótulos aparados, sem vazios, `ordem` = posição); se `lp` marcado e nenhuma distância, `alert('Cadastre ao menos uma distância para usar a lista de presença.')` e não grava. Cada prova mostra etiquetas das distâncias e o selo `Lista de presença`; atleta (`eAtl`) em prova futura com `tem_lista_presenca` e distâncias vê `<select class="dsel">` + botão "Vou correr" (`data-vc="<provaId>"`, upsert em `prova_participantes`) ou, se já marcado, "Marcado: 10 km" + "Sair" (`data-vs`); gestão em prova com lista vê "Lista da tenda" (`data-lt`) que abre `listaTendaHtml` via `Blob` + `window.open(URL.createObjectURL(...))` e chama `print()` ao carregar, e a contagem de marcados. `data-vc`, `data-vs` entram na guarda de simulação.
- [ ] **Step 5: Rodar** `node --test tests/unit/` e `node --check app.js` — Expected: PASS.
- [ ] **Step 6: Verificar no navegador** com `supabase` falso: gestão cria prova com `5 km, 10 km` e lista; atleta marca "10 km"; gestão abre a lista da tenda; conferir agrupamento e impressão (captura de tela).
- [ ] **Step 7: Commit** `feat: distâncias, "Vou correr" e lista de presença da tenda`

---

### Task 6: Avisos — banco

**Files:**
- Modify: `migracao_v2.sql` (seção `-- V2.4`)
- Create: `tests/sql/40_avisos.sql`

**Interfaces:**
- Produces: `avisos(id bigint identity pk, usuario_id uuid → perfis on delete cascade, tipo text, texto text, ref_id uuid, lido_em timestamptz, criado_em timestamptz default now())`; índice `(usuario_id, lido_em)`; RLS: `select` e `update` só do próprio usuário, `grant update (lido_em)`, sem `insert/delete` para `authenticated`; gatilho `after update` em `reembolsos` (status virou `aprovado`, `recusado` ou `pago`) criando aviso para `atleta_id` (tipos `reembolso_aprovado|reembolso_recusado|reembolso_pago`, texto com valor e, se recusado, o motivo) e em `renovacoes` (`aprovada`/`recusada`; tipos `renovacao_aprovada|renovacao_recusada`).

- [ ] **Step 1: Escrever `tests/sql/40_avisos.sql`**: aprovar, recusar (com motivo no texto) e pagar reembolso geram um aviso cada para o atleta; aprovar/recusar renovação idem; cancelamento não gera aviso; atleta B não lê avisos de A; A marca `lido_em` do próprio; A tentando alterar `texto` ou inserir aviso → erro.
- [ ] **Step 2: Rodar** `bash tests/sql/run.sh` — Expected: FAIL.
- [ ] **Step 3: Implementar** a seção `-- V2.4` (tabela, políticas, grants, funções `security definer` e gatilhos).
- [ ] **Step 4: Rodar** `bash tests/sql/run.sh` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: tabela de avisos e gatilhos de decisão`

---

### Task 7: Avisos — tela

**Files:**
- Modify: `app.js` (`refresh`, `render`, nova `viewAvisos`, handlers), `index.html` (botão do sino em `.tools`)
- Create: `tests/unit/avisos.test.js`

**Interfaces:**
- Consumes: Task 6.
- Produces: global `AV = []` (carregado em `refresh`: `avisos` do usuário, mais recentes primeiro, `limit(50)`); `function avisosCalculados(o: {prof, eAtl, admin, ATL, R, REN, meId}): Array<{sev: 'b'|'w'|'', texto: string}>` — atleta (`eAtl`): atestado/anuidade vencido ou vencendo em ≤ 30 dias (usa `st()`/`days()`); gestão (`admin`): "N renovação(ões) pendente(s)" e "N reembolso(s) pendente(s)" contando só pedidos que **não** são do próprio usuário, e uma linha por atleta com atestado/anuidade vencido ou vencendo; `function totalAvisos(): number` = calculados + `AV` não lidos. Botão `#sino` ("Avisos (n)") leva a `tab = 'avi'`; aba `avi` renderiza `viewAvisos` (calculados primeiro, depois salvos com botão "Marcar como lido" `data-lido="<id>"` e "Marcar todos" `data-lidot`).

- [ ] **Step 1: Escrever `tests/unit/avisos.test.js`** (com `today()` fixado via `Date` falso no contexto ou datas relativas): atleta com atestado vencido → `sev 'b'`; anuidade vencendo em 10 dias → `sev 'w'`; válido por 90 dias → nenhum aviso; gestão com 2 reembolsos pendentes, um próprio → "1 reembolso pendente"; atleta marcado como vencido aparece pelo nome escapado.
- [ ] **Step 2: Rodar** `node --test tests/unit/` — Expected: FAIL.
- [ ] **Step 3: Implementar** `avisosCalculados`, `totalAvisos`, `viewAvisos`, o botão no `index.html` e os handlers `data-lido`/`data-lidot` (`update({lido_em: new Date().toISOString()})`; ambos entram na guarda de simulação). Registrar `avi` no mapa de views de `render()` e garantir que `tabs` não precise listá-la (o sino abre a aba; ajustar a checagem `tabs.some(...)` para aceitar `avi`).
- [ ] **Step 4: Rodar** `node --test tests/unit/` e `node --check app.js` — Expected: PASS.
- [ ] **Step 5: Verificar no navegador** com `supabase` falso: sino mostra contagem, lista mistura calculados e salvos, marcar como lido reduz o contador (captura de tela).
- [ ] **Step 6: Commit** `feat: avisos dentro do sistema`

---

### Task 8: Fechamento — schema, roteiro e documentação

**Files:**
- Modify: `schema.sql`, `README.md`

- [ ] **Step 1:** Inserir o conteúdo completo de `migracao_v2.sql` em `schema.sql` imediatamente antes de `-- 5) PRIMEIRO ACESSO DE ADMINISTRADOR`, como seção `-- 4K) MELHORIAS V2`; acrescentar ao roteiro `-- 6)` os casos: A não lê avisos nem participações de B; só o dono reenvia reembolso recusado; só a gestão informa emissão/pagamento; atleta só se marca em prova futura e com distância da própria prova.
- [ ] **Step 2:** Rodar `bash tests/sql/run.sh` aplicando só `schema.sql` (sem `migracao_v2.sql`) — Expected: PASS em todos os testes SQL, provando que instalação nova equivale a atualização.
- [ ] **Step 3:** Atualizar `README.md`: nova seção "Atualizar uma instalação existente" (rodar `migracao_v2.sql` no SQL Editor), descrição das funções novas (valor da inscrição, prévia/reenvio, "Vou correr" e lista da tenda, avisos, emissão/pagamento) e nota "avisos por e-mail ainda não existem".
- [ ] **Step 4:** Rodar `node --test tests/unit/`, `node --check app.js` e `bash tests/sql/run.sh` — Expected: tudo PASS.
- [ ] **Step 5: Commit** `docs: schema consolidado, roteiro de permissões e README`

---

## Self-Review (feita)

- **Cobertura da spec:** Renovações (T1), Reembolso seleção/valor/prévia/reenvio/histórico (T2–T3; "seleção da prova" = seletor existente com preenchimento do valor), Calendário distâncias/indicação/lista/"Vou correr" (T4–T5), Avisos gestão/usuário/reembolso (T6–T7), migração e roteiro (T8). Sem lacunas.
- **Consistência de nomes:** `valorProva`, `previaReembolso`, `historicoReembolso`, `HR`, `previa`, `editRb`, `distanciasProva`, `listaTendaHtml`, `PART`, `avisosCalculados`, `totalAvisos`, `AV`, `datasRenovacao` e as colunas/RPCs definidos nas Interfaces de cada tarefa são os usados nas seguintes.
- **Proporção:** o plano só fixa decisões (nomes, regras de gatilho, valores); corpos de função ficam a cargo de quem implementa.
