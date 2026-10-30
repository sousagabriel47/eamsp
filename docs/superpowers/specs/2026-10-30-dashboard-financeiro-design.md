# Dashboard financeiro, pagamento em lote e função "patrocinador"

Data: 2026-10-30

## Objetivo
1. Dar à gestão, ao admin e a um novo nível "patrocinador" um **dashboard financeiro dos reembolsos**.
2. Permitir à gestão **marcar vários reembolsos aprovados como pagos** de uma vez, após o pagamento feito fora do sistema.
3. Criar a função **patrocinador**, que pode ou não ser atleta e que vê apenas o dashboard (totais, sem dados pessoais).

## Decisões do usuário
- Patrocinador vê só totais e gráficos: nenhum nome de atleta, nenhuma descrição de pedido, nenhum comprovante.
- O lote usa **uma data de pagamento única**, com a data de hoje preenchida, gravada em cada reembolso.
- O dashboard tem: cartões por situação (valor e quantidade), barras por mês (solicitado e pago), ranking por prova, tempo médio da solicitação ao pagamento, filtro de período e, **só para gestão e admin**, o bloco "por atleta".
- Gestão e admin também veem o dashboard.
- A responsividade geral do site (pedido anterior) fica para depois; os componentes novos já devem funcionar no celular.

## Regras existentes preservadas
- Ninguém valida o próprio reembolso (também vale para pagar).
- Fluxo de reembolso: pendente → aprovado/recusado/cancelado; aprovado → pago. Cada mudança grava o histórico e, em pago, o aviso ao atleta.
- Papéis hoje: atleta, gestao, admin; `perfis.atleta` marca quem também é atleta.

## Banco de dados (`migracao_v3.sql`, idempotente; dobrado em `schema.sql` na seção 4L)
- **Função patrocinador:** `perfis.papel` aceita `'patrocinador'`; `definir_papel` aceita o novo valor (somente admin); nova `public.is_patrocinador()` (papel e status ativo). Patrocinador não ganha leitura direta em nenhuma tabela existente. Pode ter `atleta = true`.
- **`reembolsos`:** colunas `pago_em date` e `pago_por uuid`. Backfill: para `status = 'pago'` sem `pago_em`, `pago_em = decidido_em::date`.
- **`pagar_reembolsos(p_ids uuid[], p_data date) returns integer`** (`security definer`, `search_path = ''`): só `is_gestao()`; lista não vazia; data não futura; todos os pedidos devem existir e estar `aprovado`; nenhum pode ser do próprio usuário; tudo ou nada, com mensagem em português que identifica o motivo. Grava `pago_em`, `pago_por` e passa para `pago` (o gatilho existente registra histórico e dispara o aviso). Devolve a quantidade paga. O gatilho de reembolso passa a impedir `pago_em`/`pago_por` fora desse caminho (nem atleta nem gestão os editam por update direto).
- **`dashboard_reembolsos(p_de date, p_ate date) returns jsonb`** (`security definer`): permitido a `is_gestao()` ou `is_patrocinador()` ativos; senão erro. Período por `criado_em` (e por `pago_em` na série "pago por mês"). Devolve:
  - `situacoes`: por status (pendente, aprovado, pago, recusado, cancelado) → `{qtd, valor}`;
  - `meses`: lista `{mes, solicitado, pago}`;
  - `provas`: ranking `{prova, qtd, valor}` (reembolsos sem prova agrupados como "Sem prova");
  - `tempo_medio_dias`: média de `pago_em - criado_em::date` dos pagos no período (`null` se nenhum);
  - `atletas` (somente quando quem chama é gestão/admin): `{nome, pediu, recebeu, a_receber}`; para patrocinador a chave não existe.
- RLS e grants: `revoke execute ... from public, anon`; `grant execute ... to authenticated`; validação de papel dentro da função.
- A aba Usuários (admin) e o modo simulação aceitam o papel novo.

## Interface (`app.js`, `index.html`)
- **Aba Dashboard** (gestão, admin e patrocinador; primeira aba do patrocinador): filtro de período (mês atual, últimos 3 meses, ano, tudo); cartões por situação com "aprovado a pagar" em destaque; barras por mês solicitado × pago; ranking por prova; tempo médio; bloco "Por atleta" apenas se a resposta trouxer `atletas`. Tudo em HTML/CSS, sem biblioteca, com cores do tema claro e escuro e layout que cabe no celular.
- **Pagamento em lote** (aba Reembolsos, gestão e admin): caixa de seleção nos reembolsos `aprovado` de outros atletas, "selecionar todos os aprovados", barra com "N selecionados · R$ total", campo de data (hoje) e "Marcar como pagos" com confirmação (quantidade, total, data); erro do banco aparece e nada muda. O botão individual atual permanece.
- **Patrocinador:** abas Dashboard e Minha conta; se também atleta, acrescenta as abas de atleta; sino de avisos só se atleta; rótulo "Acesso de patrocinador"; modo simulação do admin ganha a visão "patrocinador".
- Textos do banco passam por `esc()`; novas ações de gravação entram na guarda do modo simulação.

## Testes
- Banco (`tests/sql`): patrocinador não lê `reembolsos`/`perfis` e a função não expõe nome nem descrição; a chave `atletas` só existe para gestão/admin; atleta comum e anônimo não executam o dashboard; lote tudo-ou-nada (não aprovado, próprio, data futura, inexistente, lista vazia); `pago_em`/`pago_por` não editáveis por update direto; totais conferidos com dados conhecidos; backfill; idempotência (rodar duas vezes) e modo `SO_SCHEMA=1`.
- Interface (`tests/unit`): montagem dos cartões, barras e ranking; formatação de moeda; seleção em lote.
- Navegador com Supabase simulado em celular (390 px) e desktop (1280 px).

## Entrega em etapas
1. Banco (papel, colunas, `pagar_reembolsos`, `dashboard_reembolsos`). 2. Pagamento em lote na tela. 3. Dashboard. 4. Patrocinador nas abas Usuários, navegação e simulação. 5. `schema.sql`, roteiro de permissões e README.

## Fora de escopo
- Exportação (CSV/PDF), gráficos interativos, e-mail e responsividade geral do site.
