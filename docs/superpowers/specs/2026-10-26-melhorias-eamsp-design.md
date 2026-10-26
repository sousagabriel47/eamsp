# Melhorias EAMSP — Reembolso, Calendário, Avisos e Renovações

Data: 2026-10-26

## Objetivo
Evoluir o sistema (site estático + Supabase) em quatro frentes independentes, entregues nesta ordem:
1) Renovações, 2) Reembolso, 3) Calendário e lista de presença, 4) Avisos.
Avisos funcionam dentro do sistema; e-mail fica para uma etapa posterior (a entrega é separada da geração dos avisos).

## Decisões do usuário
- Avisos: dentro do sistema primeiro, e-mail depois.
- "Valor da prova" = valor de inscrição, cadastrado na prova pela gestão.
- Distância: várias distâncias por prova; o atleta escolhe a sua.
- Lista de presença: o atleta se marca na prova ("Vou correr" + distância); a lista da tenda sai só com esses atletas.
- Renovações: a gestão informa data de emissão e data de pagamento.
- Reenvio de reembolso: editar e reenviar o mesmo pedido recusado, com histórico completo.

## Modelo de dados (migração `migracao_v2.sql`, idempotente; `schema.sql` atualizado)
- `provas`: + `valor_inscricao numeric(10,2)`, + `tem_lista_presenca boolean default false`.
- `prova_distancias` (nova): `prova_id`, `rotulo`, `ordem`. Gestão escreve; todos leem. `provas.distancia` (texto) é migrado para uma linha e deixa de ser usado.
- `prova_participantes` (nova): `prova_id`, `atleta_id`, `distancia_id`, `criado_em`; único (prova, atleta). Atleta só altera a própria linha; gestão lê tudo.
- `reembolsos`: + `valor_prova` (cópia do valor da inscrição no pedido). `recusado -> pendente` permitido só ao próprio atleta; cada reenvio grava linha em `reembolso_historico` (motivo e valor anteriores).
- `renovacoes`: + `emitido_em date`, + `pago_em date` (só anuidade), preenchidos pela gestão na aprovação; emissão editável depois pela gestão, com registro em histórico.
- `avisos` (nova): `usuario_id`, `tipo`, `texto`, `ref_id`, `lido_em`, `criado_em`. Usuário lê e marca como lido só os próprios; escrita apenas por gatilhos.
- RLS em todas as tabelas novas, sem acesso `anon`.

## Interface (`app.js`)
- **Reembolso:** escolher a prova preenche o valor (ajustável); "Solicitar" abre prévia (prova, descrição, valor da prova, valor pedido, diferença, anexo) e só "Confirmar envio" grava; recusado ganha "Corrigir e reenviar"; histórico de aprovação expansível para atleta e gestão.
- **Calendário:** gestão define valor, distâncias e "Tem lista de presença"; atleta usa "Vou correr" com distância / "Sair"; selo "Lista de presença" e etiquetas de distância; botão "Lista da tenda" (gestão, só em provas com lista) abre página de impressão agrupada por distância, ordem alfabética, colunas número/nome/assinatura.
- **Renovações:** pedido do atleta inalterado; na validação a gestão informa emissão (obrigatória para aprovar) e, para anuidade, pagamento; emissão corrigível depois.
- **Avisos:** sino com contador. Atleta: vencimento em 30 dias/vencido; reembolso aprovado/recusado (com motivo)/pago; renovação aprovada/recusada. Gestão: renovações e reembolsos pendentes; atestado/anuidade de atletas vencendo ou vencidos. Decisões ficam salvas (gatilho em `avisos`, marcáveis como lidas); vencimentos e pendências são calculados ao abrir.

## Erros, testes e entrega
- Regras ficam no banco; mensagens do banco são exibidas como hoje.
- Sem suíte de testes no repositório: acrescentar ao roteiro de permissões do `schema.sql` casos para as tabelas novas (isolamento de avisos, reenvio só pelo dono, emissão/pagamento só pela gestão) e conferir a interface no navegador com o modo simulado (`sim`).
- Etapas independentes e funcionais, na ordem acima.

## Fora de escopo
- Envio de e-mail e rotinas agendadas (`pg_cron`).
