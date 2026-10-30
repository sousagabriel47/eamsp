-- V3.3: dashboard financeiro (public.dashboard_reembolsos)
begin;

-- testes anteriores deixam reembolsos gravados; este arquivo só enxerga os próprios (tudo é desfeito no rollback)
delete from public.reembolsos;

insert into auth.users (id, email, raw_user_meta_data) values
  ('72000000-0000-4000-8000-000000000001', 'dges@t.com', '{"nome":"Gestor Dash"}'),
  ('72000000-0000-4000-8000-000000000002', 'dadm@t.com', '{"nome":"Admin Dash"}'),
  ('72000000-0000-4000-8000-000000000003', 'dana@t.com', '{"nome":"Ana Dash"}'),
  ('72000000-0000-4000-8000-000000000004', 'dbru@t.com', '{"nome":"Bruno Dash"}'),
  ('72000000-0000-4000-8000-000000000005', 'dcai@t.com', '{"nome":"Caio Dash"}'),
  ('72000000-0000-4000-8000-000000000006', 'dpat@t.com', '{"nome":"Patrocinador Dash"}'),
  ('72000000-0000-4000-8000-000000000007', 'dpin@t.com', '{"nome":"Patrocinador Inativo Dash"}')
on conflict do nothing;
update public.perfis set papel = 'gestao', atleta = false where id = '72000000-0000-4000-8000-000000000001';
update public.perfis set papel = 'admin', atleta = false where id = '72000000-0000-4000-8000-000000000002';
update public.perfis set atleta = true where id in
  ('72000000-0000-4000-8000-000000000003', '72000000-0000-4000-8000-000000000004', '72000000-0000-4000-8000-000000000005');
update public.perfis set papel = 'patrocinador', atleta = false where id = '72000000-0000-4000-8000-000000000006';
update public.perfis set papel = 'patrocinador', atleta = false, status = 'inativo' where id = '72000000-0000-4000-8000-000000000007';

insert into public.provas (id, nome, data) values
  ('72b00000-0000-4000-8000-000000000001', 'Maratona Alfa', date '2026-05-01'),
  ('72b00000-0000-4000-8000-000000000002', 'Corrida Beta', date '2026-06-01');

-- Ana=3, Bruno=4, Caio=5; P1=Maratona Alfa, P2=Corrida Beta
insert into public.reembolsos (id, atleta_id, prova_id, descricao, valor, status, criado_em, pago_em) values
  ('72a00000-0000-4000-8000-000000000001', '72000000-0000-4000-8000-000000000003', '72b00000-0000-4000-8000-000000000001', 'segredo-desc-1', 100, 'pago',      timestamptz '2026-01-10 12:00:00+00', date '2026-01-15'),
  ('72a00000-0000-4000-8000-000000000002', '72000000-0000-4000-8000-000000000003', '72b00000-0000-4000-8000-000000000001', 'segredo-desc-2',  50, 'aprovado',  timestamptz '2026-01-20 12:00:00+00', null),
  ('72a00000-0000-4000-8000-000000000003', '72000000-0000-4000-8000-000000000004', '72b00000-0000-4000-8000-000000000002', 'segredo-desc-3', 200, 'pago',      timestamptz '2026-02-05 12:00:00+00', date '2026-02-07'),
  ('72a00000-0000-4000-8000-000000000004', '72000000-0000-4000-8000-000000000004', '72b00000-0000-4000-8000-000000000002', 'segredo-desc-4',  30, 'pendente',  timestamptz '2026-02-15 12:00:00+00', null),
  ('72a00000-0000-4000-8000-000000000005', '72000000-0000-4000-8000-000000000005', null,                                   'segredo-desc-5',  40, 'recusado',  timestamptz '2026-02-20 12:00:00+00', null),
  ('72a00000-0000-4000-8000-000000000006', '72000000-0000-4000-8000-000000000005', '72b00000-0000-4000-8000-000000000001', 'segredo-desc-6',  25, 'cancelado', timestamptz '2026-03-01 12:00:00+00', null),
  ('72a00000-0000-4000-8000-000000000007', '72000000-0000-4000-8000-000000000005', null,                                   'segredo-desc-7',  60, 'pendente',  timestamptz '2026-03-05 12:00:00+00', null),
  ('72a00000-0000-4000-8000-000000000008', '72000000-0000-4000-8000-000000000004', '72b00000-0000-4000-8000-000000000002', 'segredo-desc-8',  80, 'pago',      timestamptz '2026-02-28 12:00:00+00', date '2026-03-04'),
  -- 2026-03-01 02:30 UTC = 2026-02-28 23:30 em São Paulo: pertence a fevereiro
  ('72a00000-0000-4000-8000-000000000009', '72000000-0000-4000-8000-000000000005', null,                                   'segredo-desc-9',  10, 'pendente',  timestamptz '2026-03-01 02:30:00+00', null);

-- (a) gestão e admin: valores exatos
do $$
declare r jsonb; u text;
begin
  foreach u in array array['72000000-0000-4000-8000-000000000001', '72000000-0000-4000-8000-000000000002'] loop
    perform set_config('request.jwt.claim.sub', u, true);
    set local role authenticated;
    r := public.dashboard_reembolsos(null, null);
    reset role;
    assert r->'situacoes'->'pendente'  = '{"qtd":3,"valor":100}'::jsonb, 'a1: ' || r::text;
    assert r->'situacoes'->'aprovado'  = '{"qtd":1,"valor":50}'::jsonb,  'a2: ' || r::text;
    assert r->'situacoes'->'pago'      = '{"qtd":3,"valor":380}'::jsonb, 'a3: ' || r::text;
    assert r->'situacoes'->'recusado'  = '{"qtd":1,"valor":40}'::jsonb,  'a4: ' || r::text;
    assert r->'situacoes'->'cancelado' = '{"qtd":1,"valor":25}'::jsonb,  'a5: ' || r::text;
    assert jsonb_typeof(r->'situacoes'->'pago'->'valor') = 'number', 'a6: número, não texto';
    assert r->'meses' = '[{"mes":"2026-01","solicitado":150,"pago":100},
                          {"mes":"2026-02","solicitado":360,"pago":200},
                          {"mes":"2026-03","solicitado":60,"pago":80}]'::jsonb, 'a7: ' || (r->'meses')::text;
    assert r->'provas' = '[{"prova":"Corrida Beta","qtd":3,"valor":310},
                           {"prova":"Maratona Alfa","qtd":2,"valor":150},
                           {"prova":"Sem prova","qtd":2,"valor":70}]'::jsonb, 'a8: ' || (r->'provas')::text;
    assert r->'tempo_medio_dias' = '3.7'::jsonb, 'a9: ' || (r->'tempo_medio_dias')::text;
    assert jsonb_typeof(r->'tempo_medio_dias') = 'number', 'a9b';
    assert r->'atletas' = '[{"nome":"Ana Dash","pediu":150,"recebeu":100,"a_receber":50},
                            {"nome":"Bruno Dash","pediu":310,"recebeu":280,"a_receber":0},
                            {"nome":"Caio Dash","pediu":110,"recebeu":0,"a_receber":0}]'::jsonb, 'a10: ' || (r->'atletas')::text;
  end loop;
end $$;

-- (b) patrocinador: mesmos agregados, sem atletas, sem nomes nem descrições
do $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', '72000000-0000-4000-8000-000000000006', true);
  set local role authenticated;
  r := public.dashboard_reembolsos(null, null);
  reset role;
  assert not (r ? 'atletas'), 'b1: ' || r::text;
  assert r->'situacoes'->'pago' = '{"qtd":3,"valor":380}'::jsonb, 'b2';
  assert r->'situacoes'->'pendente' = '{"qtd":3,"valor":100}'::jsonb, 'b3';
  assert jsonb_array_length(r->'meses') = 3, 'b4';
  assert r->'provas'->0->>'prova' = 'Corrida Beta', 'b5';
  assert r->'tempo_medio_dias' = '3.7'::jsonb, 'b6';
  assert r::text not like '%Ana%' and r::text not like '%Bruno%' and r::text not like '%Caio%'
     and r::text not like '%Dash%' and r::text not like '%segredo%', 'b7: vazamento ' || r::text;
end $$;

-- (c) sem permissão: atleta, sem login, patrocinador inativo
do $$
declare msg text; u text;
begin
  foreach u in array array['72000000-0000-4000-8000-000000000003', '', '72000000-0000-4000-8000-000000000007'] loop
    perform set_config('request.jwt.claim.sub', u, true);
    set local role authenticated;
    begin
      perform public.dashboard_reembolsos(null, null);
      reset role;
      assert false, 'c: deveria falhar para "' || u || '"';
    exception when raise_exception then
      reset role;
      get stacked diagnostics msg = message_text;
      assert msg = 'Sem permissão para ver o dashboard.', 'c: ' || msg;
    end;
  end loop;
end $$;

-- (d) período restringe (fevereiro; pago conta por pago_em, solicitado por criado_em)
do $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', '72000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  r := public.dashboard_reembolsos(date '2026-02-01', date '2026-02-28');
  reset role;
  assert r->'situacoes'->'pendente'  = '{"qtd":2,"valor":40}'::jsonb,  'd1: ' || r::text;
  assert r->'situacoes'->'pago'      = '{"qtd":2,"valor":280}'::jsonb, 'd2: ' || r::text;
  assert r->'situacoes'->'recusado'  = '{"qtd":1,"valor":40}'::jsonb,  'd3';
  assert r->'situacoes'->'aprovado'  = '{"qtd":0,"valor":0}'::jsonb,   'd4';
  assert r->'situacoes'->'cancelado' = '{"qtd":0,"valor":0}'::jsonb,   'd5';
  assert r->'meses' = '[{"mes":"2026-02","solicitado":360,"pago":200}]'::jsonb, 'd6: ' || (r->'meses')::text;
  assert r->'provas' = '[{"prova":"Corrida Beta","qtd":3,"valor":310},
                           {"prova":"Sem prova","qtd":1,"valor":10}]'::jsonb, 'd7: ' || (r->'provas')::text;
  assert r->'tempo_medio_dias' = '3.0'::jsonb, 'd8: média de #3 (2 dias) e #8 (4 dias), criados em fevereiro: ' || (r->'tempo_medio_dias')::text;
  assert r->'atletas' = '[{"nome":"Bruno Dash","pediu":310,"recebeu":280,"a_receber":0},
                          {"nome":"Caio Dash","pediu":50,"recebeu":0,"a_receber":0}]'::jsonb, 'd9: ' || (r->'atletas')::text;
end $$;

-- (d2) só limite superior (janeiro)
do $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', '72000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  r := public.dashboard_reembolsos(null, date '2026-01-31');
  reset role;
  assert r->'situacoes'->'pago' = '{"qtd":1,"valor":100}'::jsonb, 'd2a: ' || r::text;
  assert r->'situacoes'->'aprovado' = '{"qtd":1,"valor":50}'::jsonb, 'd2b';
  assert r->'tempo_medio_dias' = '5'::jsonb, 'd2c: ' || (r->'tempo_medio_dias')::text;
  -- só limite inferior (março)
  set local role authenticated;
  r := public.dashboard_reembolsos(date '2026-03-01', null);
  reset role;
  assert r->'situacoes'->'pendente' = '{"qtd":1,"valor":60}'::jsonb, 'd2d: ' || r::text;
  assert r->'meses' = '[{"mes":"2026-03","solicitado":60,"pago":80}]'::jsonb, 'd2e: ' || (r->'meses')::text;
  -- nenhum pago foi solicitado em março: média nula, mesmo havendo pagamento em março
  assert jsonb_typeof(r->'tempo_medio_dias') = 'null', 'd2f: ' || (r->'tempo_medio_dias')::text;
  -- fuso: a linha de 23:30 em São Paulo (02:30 UTC de 01/03) não entra em até 27/02 e entra em até 28/02
  set local role authenticated;
  r := public.dashboard_reembolsos(date '2026-02-28', date '2026-02-28');
  reset role;
  assert r->'situacoes'->'pendente' = '{"qtd":1,"valor":10}'::jsonb, 'd2g: ' || r::text;
  assert r->'situacoes'->'pago' = '{"qtd":1,"valor":80}'::jsonb, 'd2h: ' || r::text;
  set local role authenticated;
  r := public.dashboard_reembolsos(null, date '2026-02-27');
  reset role;
  assert r->'situacoes'->'pendente' = '{"qtd":1,"valor":30}'::jsonb, 'd2i: ' || r::text;
end $$;

-- (d3) período vazio e período invertido: zeros
do $$
declare r jsonb; i int;
begin
  perform set_config('request.jwt.claim.sub', '72000000-0000-4000-8000-000000000001', true);
  for i in 1..2 loop
    set local role authenticated;
    if i = 1 then r := public.dashboard_reembolsos(date '2025-01-01', date '2025-12-31');
    else r := public.dashboard_reembolsos(date '2026-12-31', date '2026-01-01');
    end if;
    reset role;
    assert r->'situacoes'->'pago' = '{"qtd":0,"valor":0}'::jsonb, 'd3a/' || i || ': ' || r::text;
    assert r->'situacoes'->'pendente' = '{"qtd":0,"valor":0}'::jsonb, 'd3b/' || i;
    assert (select count(*) from jsonb_object_keys(r->'situacoes')) = 5, 'd3c/' || i;
    assert r->'meses' = '[]'::jsonb, 'd3d/' || i;
    assert r->'provas' = '[]'::jsonb, 'd3e/' || i;
    assert jsonb_typeof(r->'tempo_medio_dias') = 'null', 'd3f/' || i;
    assert r->'atletas' = '[]'::jsonb, 'd3g/' || i;
  end loop;
end $$;

-- (e) período nulo = tudo (idêntico a um intervalo amplo)
do $$
declare a jsonb; b jsonb;
begin
  perform set_config('request.jwt.claim.sub', '72000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  a := public.dashboard_reembolsos(null, null);
  b := public.dashboard_reembolsos(date '2000-01-01', date '2100-01-01');
  reset role;
  assert a = b, 'e1';
  assert a->'situacoes'->'pago' = '{"qtd":3,"valor":380}'::jsonb, 'e2';
end $$;

-- (f) anon não executa; authenticated sim
do $$
begin
  assert not has_function_privilege('anon', 'public.dashboard_reembolsos(date,date)', 'EXECUTE'), 'f1';
  assert has_function_privilege('authenticated', 'public.dashboard_reembolsos(date,date)', 'EXECUTE'), 'f2';
end $$;

rollback;
