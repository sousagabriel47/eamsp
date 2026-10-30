# Dashboard financeiro, pagamento em lote e patrocinador — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar a gestão, admin e patrocinador um dashboard financeiro dos reembolsos, permitir à gestão pagar vários reembolsos aprovados de uma vez e criar a função "patrocinador" (que vê só totais).

**Architecture:** As regras ficam no banco (`migracao_v3.sql`, idempotente, dobrado em `schema.sql` na seção 4L): função de papel, colunas de pagamento, RPC `pagar_reembolsos` (tudo ou nada) e RPC `dashboard_reembolsos` que devolve só totais (o patrocinador nunca lê linhas de reembolso). A interface continua em `app.js` (ES5, HTML em strings, `esc()` em texto do banco); funções puras novas são testadas em Node, e o dashboard é desenhado com HTML/CSS, sem biblioteca.

**Tech Stack:** PostgreSQL 16/Supabase (RLS, plpgsql, RPC), JavaScript ES5 no navegador, `node:test`, `psql` local.

**Spec:** `docs/superpowers/specs/2026-10-30-dashboard-financeiro-design.md`

## Global Constraints

- Português do Brasil na interface e nas mensagens de erro do banco; sem build e sem dependência nova.
- `migracao_v3.sql` idempotente (`if not exists`, `create or replace`, `drop ... if exists`), roda depois da `migracao_v2.sql` e termina com `notify pgrst, 'reload schema';`.
- Funções `security definer` usam `set search_path = ''` e nomes `public.`-qualificados; `revoke execute ... from public, anon` e `grant execute ... to authenticated`; a checagem de papel fica dentro da função.
- O patrocinador não ganha leitura direta em nenhuma tabela; só executa `dashboard_reembolsos`.
- "Hoje" no banco é `(now() at time zone 'America/Sao_Paulo')::date`.
- Ninguém valida (nem paga) o próprio reembolso.
- Em `app.js`: todo texto vindo do banco passa por `esc()`; ações novas de gravação entram na guarda do modo simulação (`if (sim && (b.dataset.… )) { alert(MSGSIM); return; }`); valores com `money()`, datas com `br()`; funções puras no bloco `/* ---------- Funções puras ---------- */`.
- Comandos de teste: `bash tests/sql/run.sh`, `SO_SCHEMA=1 bash tests/sql/run.sh`, `node --test "tests/unit/*.test.js"` (a forma com diretório falha no Node 22), `node --check app.js`.
- Commits em português, um por tarefa, na branch `claude/clever-hamilton-kth6uh`.

## Review Focus

- Lote com um item não aprovado, do próprio usuário, inexistente, data futura, lista vazia ou ids repetidos: nada é pago e a mensagem diz o motivo (T2).
- Pagamento individual pelo botão atual também grava `pago_em`/`pago_por` e reembolsos já pagos antes da migração ganham `pago_em` (T2).
- Período sem nenhum reembolso: zeros, `tempo_medio_dias` nulo e a tela mostra "Sem dados no período", nunca `NaN` (T3, T5).
- Patrocinador chamando a função direto ou lendo tabelas: não vê linha de reembolso nem a chave `atletas`; atleta comum e anônimo não executam o dashboard (T1, T3).
- Nome de prova ou de atleta com `<`, `&` ou aspas no dashboard e na barra de lote: sai escapado (T4, T5).

---

## File Structure

- `migracao_v3.sql` (criar): todas as mudanças de banco, seções `-- V3.1`, `-- V3.2`, `-- V3.3`.
- `schema.sql` (T7): recebe o conteúdo como `-- 4L) DASHBOARD, PAGAMENTO EM LOTE E PATROCINADOR`, depois da 4K e antes de `-- 5) PRIMEIRO ACESSO`; roteiro `-- 6)` ganha casos.
- `app.js`: telas, estado e funções puras novas.
- `index.html`: estilos novos (barra de lote, dashboard) e a opção "Patrocinador" no seletor `#sim`.
- `tests/sql/70_patrocinador.sql`, `71_pagamento_lote.sql`, `72_dashboard.sql`; `tests/sql/run.sh` (aplicar `migracao_v3.sql`); `tests/unit/lote.test.js`, `dashboard.test.js`, `abas.test.js`.
- `README.md` (T7).

---

### Task 1: Função "patrocinador" no banco

**Files:**
- Create: `migracao_v3.sql` (cabeçalho + `-- V3.1`), `tests/sql/70_patrocinador.sql`
- Modify: `tests/sql/run.sh`

**Interfaces:**
- Produces: `perfis.papel` aceita `'patrocinador'` (constraint `perfis_papel_check`); `public.is_patrocinador() returns boolean` (papel `patrocinador` e `status = 'ativo'`); `public.definir_papel(alvo uuid, novo text)` aceita `'patrocinador'` (mantém a regra de só admin e do último admin; a marca `atleta` não é alterada ao virar patrocinador).
- `run.sh`: aplica `migracao_v3.sql` duas vezes, logo após as aplicações de `migracao_v2.sql`, e as pula quando `SO_SCHEMA=1`.

- [ ] **Step 1: Escrever `tests/sql/70_patrocinador.sql`** com asserts específicos: (a) admin define papel `patrocinador` num atleta → `papel = 'patrocinador'`, `atleta` permanece como estava, histórico em `papel_historico`; (b) gestão e atleta chamando `definir_papel` → erro `Somente o administrador pode atribuir funções.`; (c) papel `xpto` → `Função inválida.`; (d) `is_patrocinador()` verdadeira só para patrocinador ativo (falsa para inativo, atleta e gestão); (e) patrocinador autenticado: `select count(*) from public.reembolsos`, `public.renovacoes` e `public.perfis` where id <> próprio devolvem 0; só lê o próprio perfil; (f) rebaixar o último admin continua sendo recusado.
- [ ] **Step 2: Rodar** `bash tests/sql/run.sh` — Expected: FAIL (papel inválido pela constraint).
- [ ] **Step 3: Implementar** a seção `-- V3.1` em `migracao_v3.sql` (constraint recriada, `is_patrocinador`, `create or replace` de `definir_papel` com base na última versão em `schema.sql` ~linha 391) e ajustar `run.sh`.
- [ ] **Step 4: Rodar** `bash tests/sql/run.sh` — Expected: PASS. O modo `SO_SCHEMA=1` só fica válido para os testes 70–72 depois da T7, porque o `schema.sql` ainda não tem a seção 4L; até lá rode apenas o modo padrão e diga isso no relatório.
- [ ] **Step 5: Commit** `feat: função patrocinador no banco`

---

### Task 2: Pagamento em lote no banco

**Files:**
- Modify: `migracao_v3.sql` (seção `-- V3.2`)
- Create: `tests/sql/71_pagamento_lote.sql`

**Interfaces:**
- Consumes: T1 (nada além da migração existir); gatilho `registrar_mudanca_reembolso` da V2.2 em `migracao_v2.sql` (leia-o antes; a nova definição `create or replace` preserva todas as regras).
- Produces: `reembolsos.pago_em date`, `reembolsos.pago_por uuid`; backfill (`status = 'pago'` sem `pago_em` → `pago_em = decidido_em::date`, `pago_por = decidido_por`); no gatilho, quando o status passa para `pago` e `new.pago_em` está nulo, `pago_em := hoje (São Paulo)` e `pago_por := auth.uid()` (cobre o botão individual); `public.pagar_reembolsos(p_ids uuid[], p_data date) returns integer`.
- `pago_em`/`pago_por` NÃO entram no `grant update` de `authenticated` (continua `status, motivo_decisao, prova_id, descricao, valor, anexo_path`).

Regras de `pagar_reembolsos` (tudo ou nada, mensagens em português): só `is_gestao()` (`Somente a gestão pode pagar reembolsos.`); lista não nula e com ao menos um id (`Selecione ao menos um reembolso.`); ids repetidos contam uma vez; `p_data` não nula e ≤ hoje (`A data do pagamento não pode ser futura.`); todo id existe (`Reembolso não encontrado.`), está `aprovado` (`Só reembolsos aprovados podem ser pagos.`) e não é do próprio usuário (`Você não pode pagar o seu próprio reembolso. Peça a outro gestor.`); trava as linhas com `for update`; faz o update de status com `pago_em = p_data` e `pago_por = auth.uid()` (gatilho cuida de histórico e aviso); devolve a quantidade paga.

- [ ] **Step 1: Escrever `tests/sql/71_pagamento_lote.sql`** (fixtures próprias; estilo de `20_reembolso.sql`): (a) lote com 3 aprovados de 2 atletas → devolve 3, os três `pago` com `pago_em = p_data` e `pago_por` = gestor, 3 linhas de `reembolso_historico` `aprovado→pago` e 3 `avisos` tipo `reembolso_pago`; (b) lote com um `pendente` no meio → erro `Só reembolsos aprovados podem ser pagos.` e **nenhum** dos outros mudou; (c) lote com reembolso do próprio gestor → erro da regra própria e nada muda; (d) `p_data = hoje + 1` → `A data do pagamento não pode ser futura.`; (e) id inexistente → `Reembolso não encontrado.`; (f) lista vazia e `null` → `Selecione ao menos um reembolso.`; (g) ids repetidos no array pagam uma vez; (h) atleta e patrocinador executando → `Somente a gestão pode pagar reembolsos.`; (i) update direto de `pago_em` por `authenticated` → `permission denied for table reembolsos` (SQLSTATE `42501`); (j) botão individual: gestão faz `update reembolsos set status='pago'` num aprovado → `pago_em = hoje`, `pago_por` preenchido; (k) backfill: reembolso `pago` inserido antes (superusuário, sem `pago_em`) recebe `pago_em` ao reaplicar a migração.
- [ ] **Step 2: Rodar** `bash tests/sql/run.sh` — Expected: FAIL (coluna/função inexistente).
- [ ] **Step 3: Implementar** a seção `-- V3.2` (colunas, backfill idempotente, `create or replace` do gatilho, `pagar_reembolsos`, grants).
- [ ] **Step 4: Rodar** `bash tests/sql/run.sh` — Expected: PASS (migração aplicada duas vezes sem erro).
- [ ] **Step 5: Commit** `feat: pagamento em lote e data de pagamento no banco`

---

### Task 3: Função do dashboard no banco

**Files:**
- Modify: `migracao_v3.sql` (seção `-- V3.3`, terminando em `notify pgrst, 'reload schema';`)
- Create: `tests/sql/72_dashboard.sql`

**Interfaces:**
- Consumes: T1 (`is_patrocinador`), T2 (`pago_em`).
- Produces: `public.dashboard_reembolsos(p_de date, p_ate date) returns jsonb` (`security definer`, `stable`); `p_de`/`p_ate` nulos = sem limite; período aplicado à data de solicitação (`criado_em` em São Paulo). Permitido a `is_gestao()` ou `is_patrocinador()`; senão `raise exception 'Sem permissão para ver o dashboard.'`. Formato:

```json
{"situacoes": {"pendente": {"qtd": 0, "valor": 0}, "aprovado": {...}, "pago": {...}, "recusado": {...}, "cancelado": {...}},
 "meses": [{"mes": "2026-10", "solicitado": 0, "pago": 0}],
 "provas": [{"prova": "Nome", "qtd": 1, "valor": 100}],
 "tempo_medio_dias": null,
 "atletas": [{"nome": "Ana", "pediu": 0, "recebeu": 0, "a_receber": 0}]}
```

Decisões: as cinco situações sempre presentes (zeros); `meses` em ordem crescente, `solicitado` = soma de reembolsos criados no mês excluindo `cancelado`, `pago` = soma de `pago_em` no mês dentro do período (`pago_em` entre `p_de` e `p_ate`); `provas` = reembolsos com status `pendente|aprovado|pago` agrupados por prova (sem prova → "Sem prova"), por valor decrescente; `tempo_medio_dias` = média de `pago_em - criado_em::date` dos `pago` do período, arredondada a 1 casa, `null` sem pagos; `atletas` (chave só existe para gestão/admin) = `pediu` (status ≠ `cancelado`), `recebeu` (`pago`), `a_receber` (`aprovado`), ordenado por nome. Valores como número (não texto).

- [ ] **Step 1: Escrever `tests/sql/72_dashboard.sql`** com dados conhecidos (3 atletas, 2 provas, reembolsos em status e meses variados, um sem prova): (a) gestão: totais por situação, soma por mês, ranking por prova (ordem e "Sem prova"), tempo médio e bloco `atletas` conferidos com valores exatos; (b) patrocinador: mesmo conteúdo **sem** a chave `atletas` (`not (r ? 'atletas')`) e sem nenhum nome de atleta ou descrição em `r::text`; (c) atleta comum e usuário sem login → `Sem permissão para ver o dashboard.`; patrocinador inativo também; (d) período `p_de/p_ate` restringe; período vazio → zeros, `meses` `[]`, `tempo_medio_dias` nulo; (e) `p_de` nulo e `p_ate` nulo = tudo; (f) `has_function_privilege('anon', 'public.dashboard_reembolsos(date,date)', 'EXECUTE')` falso.
- [ ] **Step 2: Rodar** `bash tests/sql/run.sh` — Expected: FAIL (função inexistente).
- [ ] **Step 3: Implementar** a seção `-- V3.3` (função, grants, `notify pgrst, 'reload schema';` por último).
- [ ] **Step 4: Rodar** `bash tests/sql/run.sh` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: função do dashboard financeiro no banco`

---

### Task 4: Pagamento em lote na tela

**Files:**
- Modify: `app.js` (`viewReb`, estado global, handlers de clique/`change`, guarda de simulação), `index.html` (estilo da barra)
- Create: `tests/unit/lote.test.js`

**Interfaces:**
- Consumes: T2 (`sb.rpc('pagar_reembolsos', {p_ids, p_data})`).
- Produces: globais `SEL = {}` (id → `true`) e `LOTE_DATA = ''`; `function lotePodeSelecionar(r: {status, atleta_id}, meId: string): boolean` (aprovado e de outro atleta); `function loteResumo(sel: object, rs: Array<{id, valor, status, atleta_id}>, meId: string): {n: number, total: number, ids: string[]}` (conta só selecionados que ainda podem ser selecionados); `function loteBarraHtml(resumo, data: string): string` (barra com "N selecionados · R$ total", `<input type="date" id="lotedata" max="hoje" value="data">`, botão `data-lote="1"` "Marcar como pagos" e botão `data-lotelimpa="1"`; vazia quando `n === 0`).

- [ ] **Step 1: Escrever `tests/unit/lote.test.js`**: `lotePodeSelecionar` é falso para `pendente`, `pago` e para pedido do próprio usuário, verdadeiro para aprovado de outro; `loteResumo` soma `valor` só dos elegíveis (ignora ids selecionados que mudaram de status) e devolve `ids`; `loteBarraHtml` com `n = 2` contém `2 selecionados` e `R$ 150,00` (via `money`), não contém `<script`, e com `n = 0` devolve `''`.
- [ ] **Step 2: Rodar** `node --test "tests/unit/*.test.js"` — Expected: FAIL.
- [ ] **Step 3: Implementar** as funções puras e a tela: em `viewReb`, para `admin`, cada reembolso `aprovado` de outro atleta ganha `<input type="checkbox" data-sel="<id>">` (marcada conforme `SEL`), seguido de "selecionar todos os aprovados" (`data-selall`) acima da lista; os do próprio usuário mostram "outro gestor precisa pagar"; a barra de lote (`position: sticky; bottom: 0`) vem ao fim da lista; um listener `change` no `document` atualiza `SEL`/`LOTE_DATA` e chama `render()`; `data-lote`: `confirm` com quantidade, total e data (`br`), `sb.rpc('pagar_reembolsos', {p_ids: resumo.ids, p_data: data})`, em sucesso limpa `SEL`, mostra `aviso = N reembolso(s) marcado(s) como pago(s).` e dá `refresh()`; erro do banco vai para `fail(error)` e nada muda na seleção. `data-lote` entra na guarda de simulação. Data padrão = `today()`. Mantenha o botão individual "Marcar como pago".
- [ ] **Step 4: Rodar** `node --test "tests/unit/*.test.js"` e `node --check app.js` — Expected: PASS.
- [ ] **Step 5: Verificar no navegador** (Playwright pré-instalado, `supabase` falso fora do repositório, reaproveite os de `/tmp/claude-0/-home-user-eamsp/2fdae0e9-9ded-55b1-8861-0cbf6568ff07/scratchpad/`): como gestão com 3 aprovados (um próprio), selecionar dois, ver "2 selecionados · total", confirmar e conferir a chamada `pagar_reembolsos` com os dois ids e a data; em 390 px a barra não cobre o botão de confirmar nem estoura a largura. Salvar captura no scratchpad (não comitar).
- [ ] **Step 6: Commit** `feat: pagamento em lote de reembolsos na tela`

---

### Task 5: Dashboard e abas por papel

**Files:**
- Modify: `app.js` (estado, `refresh`, `render`, nova `viewDash`), `index.html` (estilos do dashboard)
- Create: `tests/unit/dashboard.test.js`, `tests/unit/abas.test.js`

**Interfaces:**
- Consumes: T3 (`sb.rpc('dashboard_reembolsos', {p_de, p_ate})` devolve o JSON do formato acima em `data`).
- Produces: globais `DASH = null` e `dashPer = 'mes'`; `function periodoDash(chave: 'mes'|'3m'|'ano'|'tudo', hoje: string): {de: string|null, ate: string|null}` (`mes` = dia 1 do mês de `hoje` até `hoje`; `3m` = dia 1 de dois meses antes até `hoje`; `ano` = 1º de janeiro até `hoje`; `tudo` = `{de: null, ate: null}`; datas `aaaa-mm-dd`); `function cartoesDash(d): string`, `barrasMesDash(d): string`, `rankingProvaDash(d): string`, `tempoMedioDash(d): string`, `atletasDash(d): string` (`''` se `d.atletas` ausente) — todos devolvem HTML com `esc()`; `function dashVazio(d): boolean` (todas as situações com `qtd = 0`); `async function carregarDash()` (lê `dashPer`, chama a RPC, guarda `DASH`, `render()`; em erro `fail`); `function viewDash(): string`; `function montarAbas(o: {admin, sup, spons, eAtl, np, nr, ns}): Array<[string, string]>` — gestão/admin: Calendário, Atletas, Renovações(np), Reembolsos(nr), **Dashboard** (`'dash'`), + Atestado e anuidade se `eAtl`, + Usuários/Senhas(ns)/Importar CSV se `sup`; patrocinador (`spons`): Dashboard, + Calendário/Atestado e anuidade/Reembolsos se `eAtl`; atleta: Calendário, Atestado e anuidade, Reembolsos; todos terminam com Minha conta.

- [ ] **Step 1: Escrever `tests/unit/abas.test.js`**: para cada papel, a lista exata de chaves (`['cal','ath','ren','reb','dash','conta']` para gestão sem `eAtl`, com `'me'` incluído se `eAtl`; `['dash','conta']` para patrocinador não atleta; `['dash','cal','me','reb','conta']` para patrocinador atleta; contadores `Renovações (2)` quando `np = 2`).
- [ ] **Step 2: Escrever `tests/unit/dashboard.test.js`**: `periodoDash('mes','2026-10-30')` → `{de:'2026-10-01',ate:'2026-10-30'}`; `'3m'` → `de:'2026-08-01'`; `'3m'` em `'2026-01-15'` → `de:'2025-11-01'`; `'ano'`; `'tudo'`; `cartoesDash` mostra `R$ 1.234,50` e a quantidade e destaca "a pagar" (aprovado); `barrasMesDash` desenha uma barra por mês com largura proporcional (`style="width:100%"` no maior valor, `0%` quando tudo zero, sem `NaN`); `rankingProvaDash` escapa `<b>x</b>` no nome da prova; `atletasDash({})` → `''` e com `atletas` escapa nomes; `dashVazio` e a mensagem "Sem dados no período" no `viewDash` quando vazio; `tempoMedioDash({tempo_medio_dias: null})` → `—` e `3.5` → `3,5 dias`.
- [ ] **Step 3: Rodar** `node --test "tests/unit/*.test.js"` — Expected: FAIL.
- [ ] **Step 4: Implementar** as funções puras (no bloco de funções puras), `viewDash` (cabeçalho com `<select id="dashper">`, cartões, barras, ranking, tempo médio, bloco por atleta quando vier), `carregarDash` (chamada ao entrar na aba `dash` e ao mudar `#dashper`), a troca do cálculo de `tabs` em `render()` por `montarAbas`, o mapa de views com `dash: viewDash` e o estilo (cartões em grade que quebra em 1 coluna no celular, barras com cor do tema). Fallback de aba: `if (tab != 'avi' && !tabs.some(...)) tab = tabs[0][0]`.
- [ ] **Step 5: Rodar** `node --test "tests/unit/*.test.js"` e `node --check app.js` — Expected: PASS.
- [ ] **Step 6: Verificar no navegador** (Supabase simulado com a RPC devolvendo o JSON de exemplo): como gestão, a aba Dashboard mostra cartões, barras, ranking, tempo médio e "Por atleta"; trocar o período dispara nova chamada com `p_de/p_ate` corretos; a página não rola na horizontal em 390 px. Capturas no scratchpad (não comitar).
- [ ] **Step 7: Commit** `feat: dashboard financeiro e abas por papel`

---

### Task 6: Patrocinador na interface

**Files:**
- Modify: `app.js` (`PAP`, `refresh`, `render`, `viewUsr`, `viewConta`, simulação), `index.html` (opção do `#sim`)
- Create: `tests/unit/patrocinador.test.js`

**Interfaces:**
- Consumes: T5 (`montarAbas`, `viewDash`, `DASH`), T1 (papel `patrocinador`).
- Produces: global `spons` (verdadeira para `prof.papel === 'patrocinador'`, ou para a simulação `patrocinador`); `PAP.patrocinador = 'Patrocinador'`; `function rotuloAcesso(o: {sim: string, realSup: boolean, realAdmin: boolean, spons: boolean}): string` (`Simulando a visão de patrocinador`, `Acesso de patrocinador`, `Acesso de administrador`, `Acesso de gestão`, `Acesso de atleta`); `function dashParaPapel(d, simPatro: boolean): object` (remove a chave `atletas` quando `simPatro`).

- [ ] **Step 1: Escrever `tests/unit/patrocinador.test.js`**: `rotuloAcesso` para cada caso; `dashParaPapel({atletas:[...], situacoes:{}}, true)` não tem `atletas` e não altera o objeto original; com `false` mantém.
- [ ] **Step 2: Rodar** `node --test "tests/unit/*.test.js"` — Expected: FAIL.
- [ ] **Step 3: Implementar**: em `refresh`, `spons = prof.papel === 'patrocinador'`; para patrocinador, não consultar `reembolsos`, `reembolso_historico`, `renovacoes`, `perfis` (atletas) nem `provas`/`prova_participantes` quando `!prof.atleta` (use `Promise.resolve({data: []})`, mantendo a ordem dos índices de `a[]`); `render()` passa `spons` e `eAtl` a `montarAbas`; sino oculto quando `spons && !eAtl`; rótulo via `rotuloAcesso`; `viewUsr` ganha `patrocinador` no seletor de função e `viewConta` mostra o papel; `#sim` ganha `<option value="patrocinador">Patrocinador</option>` e, na simulação `patrocinador`, `admin = false`, `sup = false`, `eAtl = false`, `spons = true` e o dashboard exibido passa por `dashParaPapel(DASH, true)`; ao entrar como patrocinador (ou simulá-lo) a aba inicial é `dash`.
- [ ] **Step 4: Rodar** `node --test "tests/unit/*.test.js"` e `node --check app.js` — Expected: PASS.
- [ ] **Step 5: Verificar no navegador** com o Supabase simulado: perfil `patrocinador` sem `atleta` vê só Dashboard e Minha conta, sem sino e sem "Por atleta"; com `atleta = true` ganha Calendário, Atestado e anuidade, Reembolsos e o sino; admin simulando patrocinador vê o dashboard sem o bloco por atleta. Capturas no scratchpad (não comitar).
- [ ] **Step 6: Commit** `feat: função patrocinador na interface`

---

### Task 7: Fechamento — schema, roteiro e documentação

**Files:**
- Modify: `schema.sql`, `tests/sql/run.sh` (se necessário), `README.md`, `migracao_v3.sql` (cabeçalho)

- [ ] **Step 1:** Dobrar o corpo de `migracao_v3.sql` em `schema.sql` como `-- 4L) DASHBOARD, PAGAMENTO EM LOTE E PATROCINADOR`, depois da 4K e antes de `-- 5) PRIMEIRO ACESSO`, byte a byte igual ao corpo da migração (apenas o cabeçalho muda); `migracao_v3.sql` ganha cabeçalho "Para quem já tem a v2 instalada; instalações novas usam apenas o schema.sql".
- [ ] **Step 2:** Estender o roteiro `-- 6) TESTE DE PERMISSÕES` com: patrocinador não lê reembolsos nem perfis de outras pessoas e o dashboard dele não traz nome nem descrição; só gestão/admin pagam em lote e ninguém paga o próprio reembolso; `pago_em`/`pago_por` não são editáveis por update direto; atleta comum não executa o dashboard.
- [ ] **Step 3:** Rodar `bash tests/sql/run.sh` e `SO_SCHEMA=1 bash tests/sql/run.sh` — Expected: os testes 70–72 passam nos dois modos.
- [ ] **Step 4:** README: seção "Atualizar uma instalação existente" passa a mandar rodar `migracao_v2.sql` e depois `migracao_v3.sql` (cada uma pode ser repetida sem problema); descrever o dashboard, o pagamento em lote, a função patrocinador (como o admin a atribui na aba Usuários, e que ela pode ser também atleta) e o que o patrocinador vê; lembrar de publicar a migração e o `app.js` juntos.
- [ ] **Step 5:** Rodar `node --test "tests/unit/*.test.js"`, `node --check app.js` e os dois modos SQL — Expected: tudo passa.
- [ ] **Step 6: Commit** `docs: schema consolidado, roteiro e README do dashboard financeiro`

---

## Self-Review (feita)

- **Cobertura da spec:** função patrocinador (T1, T6), `pago_em/pago_por` e backfill (T2), `pagar_reembolsos` tudo ou nada (T2) e sua tela (T4), `dashboard_reembolsos` e privacidade do patrocinador (T3), aba Dashboard, período, cartões, barras, ranking, tempo médio e bloco por atleta (T5), patrocinador também atleta, aba Usuários e modo simulação (T6), consolidação, roteiro e README (T7). Sem lacunas.
- **Consistência de nomes:** `is_patrocinador`, `pagar_reembolsos(p_ids, p_data)`, `dashboard_reembolsos(p_de, p_ate)`, `montarAbas`, `periodoDash`, `loteResumo`, `rotuloAcesso`, `dashParaPapel` e os globais `SEL`, `LOTE_DATA`, `DASH`, `dashPer`, `spons` aparecem iguais nas Interfaces de produtores e consumidores.
- **Decisões que a spec deixou em aberto, fixadas aqui:** `solicitado` e o ranking por prova excluem cancelado (o ranking também exclui recusado); `pediu` por atleta exclui cancelado; o botão individual de pagar também grava `pago_em` (hoje, São Paulo).
- **Proporção:** o plano só fixa decisões, assinaturas e asserts; corpos de função ficam para quem implementa.
- **Observação:** os testes SQL 70–72 só passam em `SO_SCHEMA=1` depois da T7, porque o `schema.sql` só ganha a 4L lá.
