-- V3.4: quantas PESSOAS já pediram reembolso de cada prova (public.pedidos_reembolso_por_prova)
-- O atleta não lê os reembolsos dos outros; a função devolve só prova_id e a contagem.
begin;

-- testes anteriores deixam reembolsos gravados; este arquivo só enxerga os próprios (tudo é desfeito no rollback)
delete from public.reembolsos;

insert into auth.users (id, email, raw_user_meta_data) values
  ('75000000-0000-4000-8000-000000000001', 'pgest@t.com', '{"nome":"Gestor Prova"}'),
  ('75000000-0000-4000-8000-000000000002', 'pana@t.com',  '{"nome":"Ana Prova"}'),
  ('75000000-0000-4000-8000-000000000003', 'pbru@t.com',  '{"nome":"Bruno Prova"}'),
  ('75000000-0000-4000-8000-000000000004', 'pcai@t.com',  '{"nome":"Caio Prova"}'),
  ('75000000-0000-4000-8000-000000000005', 'ppat@t.com',  '{"nome":"Patrocinador Prova"}'),
  ('75000000-0000-4000-8000-000000000006', 'pina@t.com',  '{"nome":"Atleta Inativo Prova"}')
on conflict do nothing;
update public.perfis set papel = 'gestao', atleta = false where id = '75000000-0000-4000-8000-000000000001';
update public.perfis set atleta = true where id in
  ('75000000-0000-4000-8000-000000000002', '75000000-0000-4000-8000-000000000003', '75000000-0000-4000-8000-000000000004');
update public.perfis set papel = 'patrocinador', atleta = false where id = '75000000-0000-4000-8000-000000000005';
update public.perfis set atleta = true, status = 'inativo' where id = '75000000-0000-4000-8000-000000000006';

insert into public.provas (id, nome, data) values
  ('75b00000-0000-4000-8000-000000000001', 'Prova Um',   date '2026-05-01'),
  ('75b00000-0000-4000-8000-000000000002', 'Prova Dois', date '2026-06-01'),
  ('75b00000-0000-4000-8000-000000000003', 'Prova Tres', date '2026-07-01'),
  ('75b00000-0000-4000-8000-000000000004', 'Prova Sem Pedidos', date '2026-08-01');

-- Ana=2, Bruno=3, Caio=4.
-- Prova Um:   Ana (pendente) + Ana (aprovado) + Bruno (recusado) + Caio (cancelado)  => 2 pessoas (Ana, Bruno)
-- Prova Dois: Caio (pendente)                                                         => 1 pessoa
-- Prova Tres: só um pedido cancelado do Bruno                                         => não aparece
-- Prova Sem Pedidos: nada                                                             => não aparece
-- Pedido sem prova (Ana)                                                              => não entra
insert into public.reembolsos (id, atleta_id, prova_id, descricao, valor, status) values
  ('75a00000-0000-4000-8000-000000000001', '75000000-0000-4000-8000-000000000002', '75b00000-0000-4000-8000-000000000001', 'segredo-1', 100, 'pendente'),
  ('75a00000-0000-4000-8000-000000000002', '75000000-0000-4000-8000-000000000002', '75b00000-0000-4000-8000-000000000001', 'segredo-2',  50, 'aprovado'),
  ('75a00000-0000-4000-8000-000000000003', '75000000-0000-4000-8000-000000000003', '75b00000-0000-4000-8000-000000000001', 'segredo-3',  70, 'recusado'),
  ('75a00000-0000-4000-8000-000000000004', '75000000-0000-4000-8000-000000000004', '75b00000-0000-4000-8000-000000000001', 'segredo-4',  30, 'cancelado'),
  ('75a00000-0000-4000-8000-000000000005', '75000000-0000-4000-8000-000000000004', '75b00000-0000-4000-8000-000000000002', 'segredo-5',  80, 'pendente'),
  ('75a00000-0000-4000-8000-000000000006', '75000000-0000-4000-8000-000000000003', '75b00000-0000-4000-8000-000000000003', 'segredo-6',  20, 'cancelado'),
  ('75a00000-0000-4000-8000-000000000007', '75000000-0000-4000-8000-000000000002', null,                                   'segredo-7',  10, 'pendente');

-- (a) atleta (Ana) e gestão veem as mesmas contagens; só prova_id e pessoas
do $$
declare u text; r jsonb;
begin
  foreach u in array array['75000000-0000-4000-8000-000000000002', '75000000-0000-4000-8000-000000000003', '75000000-0000-4000-8000-000000000001'] loop
    perform set_config('request.jwt.claim.sub', u, true);
    set local role authenticated;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.prova_id), '[]'::jsonb) into r from public.pedidos_reembolso_por_prova() x;
    reset role;
    assert r = '[{"prova_id":"75b00000-0000-4000-8000-000000000001","pessoas":2},
                 {"prova_id":"75b00000-0000-4000-8000-000000000002","pessoas":1}]'::jsonb, 'a: ' || u || ' ' || r::text;
    assert jsonb_typeof(r->0->'pessoas') = 'number', 'a2: número';
    assert r::text not like '%segredo%' and r::text not like '%Ana%' and r::text not like '%Bruno%' and r::text not like '%Caio%',
      'a3: vazamento ' || r::text;
  end loop;
end $$;

-- (b) o atleta continua sem ler os reembolsos dos outros diretamente
do $$
declare n int;
begin
  perform set_config('request.jwt.claim.sub', '75000000-0000-4000-8000-000000000003', true);
  set local role authenticated;
  select count(*) into n from public.reembolsos where atleta_id <> '75000000-0000-4000-8000-000000000003';
  reset role;
  assert n = 0, 'b: atleta não deve ler pedidos de outros (' || n || ')';
end $$;

-- (c) sem permissão: patrocinador (não atleta), sem login e atleta inativo
do $$
declare msg text; u text;
begin
  foreach u in array array['75000000-0000-4000-8000-000000000005', '', '75000000-0000-4000-8000-000000000006'] loop
    perform set_config('request.jwt.claim.sub', u, true);
    set local role authenticated;
    begin
      perform * from public.pedidos_reembolso_por_prova();
      reset role;
      assert false, 'c: deveria falhar para "' || u || '"';
    exception when raise_exception then
      reset role;
      get stacked diagnostics msg = message_text;
      assert msg = 'Sem permissão para ver os pedidos de reembolso por prova.', 'c: mensagem "' || msg || '" para "' || u || '"';
    end;
  end loop;
end $$;

-- (d) um pedido cancelado deixa de contar: a Prova Dois some quando o único pedido (Caio, pendente) é cancelado
do $$
declare r jsonb;
begin
  update public.reembolsos set status = 'cancelado' where id = '75a00000-0000-4000-8000-000000000005';
  perform set_config('request.jwt.claim.sub', '75000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.prova_id), '[]'::jsonb) into r from public.pedidos_reembolso_por_prova() x;
  reset role;
  assert r = '[{"prova_id":"75b00000-0000-4000-8000-000000000001","pessoas":2}]'::jsonb, 'd: ' || r::text;
end $$;

-- (e) anon não executa; autenticado sim
do $$
begin
  assert not has_function_privilege('anon', 'public.pedidos_reembolso_por_prova()', 'EXECUTE'), 'e1';
  assert has_function_privilege('authenticated', 'public.pedidos_reembolso_por_prova()', 'EXECUTE'), 'e2';
end $$;

rollback;
