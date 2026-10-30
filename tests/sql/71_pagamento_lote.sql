-- V3.2: pagamento em lote e data de pagamento
begin;


insert into auth.users (id, email, raw_user_meta_data) values
  ('71000000-0000-4000-8000-000000000001', 'lg1@t.com', '{"nome":"Gestor L1"}'),
  ('71000000-0000-4000-8000-000000000002', 'lg2@t.com', '{"nome":"Gestor L2"}'),
  ('71000000-0000-4000-8000-000000000003', 'lat1@t.com', '{"nome":"Atleta L1"}'),
  ('71000000-0000-4000-8000-000000000004', 'lat2@t.com', '{"nome":"Atleta L2"}'),
  ('71000000-0000-4000-8000-000000000005', 'lpat@t.com', '{"nome":"Patrocinador L"}')
on conflict do nothing;
update public.perfis set papel = 'gestao', atleta = true
  where id in ('71000000-0000-4000-8000-000000000001', '71000000-0000-4000-8000-000000000002');
update public.perfis set atleta = true
  where id in ('71000000-0000-4000-8000-000000000003', '71000000-0000-4000-8000-000000000004');
update public.perfis set papel = 'patrocinador', atleta = false
  where id = '71000000-0000-4000-8000-000000000005';

-- reembolsos aprovados (inseridos pelo superusuário): 1-3 de atletas, 4 do gestor L1, 5 pendente, 6-7 extras
insert into public.reembolsos (id, atleta_id, descricao, valor, status) values
  ('71a00000-0000-4000-8000-000000000001', '71000000-0000-4000-8000-000000000003', 'x', 10, 'aprovado'),
  ('71a00000-0000-4000-8000-000000000002', '71000000-0000-4000-8000-000000000003', 'x', 20, 'aprovado'),
  ('71a00000-0000-4000-8000-000000000003', '71000000-0000-4000-8000-000000000004', 'x', 30, 'aprovado'),
  ('71a00000-0000-4000-8000-000000000004', '71000000-0000-4000-8000-000000000001', 'x', 40, 'aprovado'),
  ('71a00000-0000-4000-8000-000000000005', '71000000-0000-4000-8000-000000000004', 'x', 50, 'pendente'),
  ('71a00000-0000-4000-8000-000000000006', '71000000-0000-4000-8000-000000000004', 'x', 60, 'aprovado'),
  ('71a00000-0000-4000-8000-000000000007', '71000000-0000-4000-8000-000000000003', 'x', 70, 'aprovado');

update public.reembolsos set criado_em = timestamptz '2026-01-01 12:00:00+00'
  where id::text like '71a00000-%';

-- (a) lote com 3 aprovados de 2 atletas
do $$
declare n int;
begin
  perform set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  n := public.pagar_reembolsos(array[
    '71a00000-0000-4000-8000-000000000001', '71a00000-0000-4000-8000-000000000002',
    '71a00000-0000-4000-8000-000000000003']::uuid[], date '2026-01-15');
  reset role;
  assert n = 3, 'a1: ' || n;
  assert (select count(*) from public.reembolsos
          where id in ('71a00000-0000-4000-8000-000000000001', '71a00000-0000-4000-8000-000000000002', '71a00000-0000-4000-8000-000000000003')
            and status = 'pago' and pago_em = date '2026-01-15'
            and pago_por = '71000000-0000-4000-8000-000000000001') = 3, 'a2';
  assert (select count(*) from public.reembolso_historico
          where reembolso_id in ('71a00000-0000-4000-8000-000000000001', '71a00000-0000-4000-8000-000000000002', '71a00000-0000-4000-8000-000000000003')
            and status_anterior = 'aprovado' and status_novo = 'pago'
            and alterado_por = '71000000-0000-4000-8000-000000000001') = 3, 'a3';
  assert (select count(*) from public.avisos
          where tipo = 'reembolso_pago'
            and ref_id in ('71a00000-0000-4000-8000-000000000001', '71a00000-0000-4000-8000-000000000002', '71a00000-0000-4000-8000-000000000003')) = 3, 'a4';
end $$;

-- (b) um pendente no meio: nada muda
do $$
declare msg text;
begin
  perform set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  begin
    perform public.pagar_reembolsos(array[
      '71a00000-0000-4000-8000-000000000006', '71a00000-0000-4000-8000-000000000005',
      '71a00000-0000-4000-8000-000000000007']::uuid[], current_date);
    reset role;
    assert false, 'b: deveria falhar';
  exception when raise_exception then
    reset role;
    get stacked diagnostics msg = message_text;
    assert msg = 'Só reembolsos aprovados podem ser pagos.', 'b: ' || msg;
  end;
  assert (select count(*) from public.reembolsos
          where id in ('71a00000-0000-4000-8000-000000000006', '71a00000-0000-4000-8000-000000000007')
            and status = 'aprovado' and pago_em is null) = 2, 'b2';
  assert (select status from public.reembolsos where id = '71a00000-0000-4000-8000-000000000005') = 'pendente', 'b3';
end $$;

-- (c) reembolso do próprio gestor: nada muda
do $$
declare msg text;
begin
  perform set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  begin
    perform public.pagar_reembolsos(array[
      '71a00000-0000-4000-8000-000000000006', '71a00000-0000-4000-8000-000000000004']::uuid[], current_date);
    reset role;
    assert false, 'c: deveria falhar';
  exception when raise_exception then
    reset role;
    get stacked diagnostics msg = message_text;
    assert msg = 'Você não pode pagar o seu próprio reembolso. Peça a outro gestor.', 'c: ' || msg;
  end;
  assert (select count(*) from public.reembolsos
          where id in ('71a00000-0000-4000-8000-000000000004', '71a00000-0000-4000-8000-000000000006')
            and status = 'aprovado' and pago_em is null) = 2, 'c2';
end $$;

-- (d) data futura
do $$
declare msg text;
begin
  perform set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  begin
    perform public.pagar_reembolsos(array['71a00000-0000-4000-8000-000000000006']::uuid[],
      (now() at time zone 'America/Sao_Paulo')::date + 1);
    reset role;
    assert false, 'd: deveria falhar';
  exception when raise_exception then
    reset role;
    get stacked diagnostics msg = message_text;
    assert msg = 'A data do pagamento não pode ser futura.', 'd: ' || msg;
  end;
  assert (select status from public.reembolsos where id = '71a00000-0000-4000-8000-000000000006') = 'aprovado', 'd2';
end $$;

-- (e) id inexistente
do $$
declare msg text;
begin
  perform set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  begin
    perform public.pagar_reembolsos(array[
      '71a00000-0000-4000-8000-000000000006', '71a00000-0000-4000-8000-0000000000ff']::uuid[], current_date);
    reset role;
    assert false, 'e: deveria falhar';
  exception when raise_exception then
    reset role;
    get stacked diagnostics msg = message_text;
    assert msg = 'Reembolso não encontrado.', 'e: ' || msg;
  end;
  assert (select status from public.reembolsos where id = '71a00000-0000-4000-8000-000000000006') = 'aprovado', 'e2';
end $$;

-- (f) lista vazia e nula; data nula
do $$
declare msg text;
begin
  perform set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  begin
    perform public.pagar_reembolsos(array[]::uuid[], current_date);
    reset role;
    assert false, 'f1: deveria falhar';
  exception when raise_exception then
    reset role;
    get stacked diagnostics msg = message_text;
    assert msg = 'Selecione ao menos um reembolso.', 'f1: ' || msg;
  end;
  set local role authenticated;
  begin
    perform public.pagar_reembolsos(null, current_date);
    reset role;
    assert false, 'f2: deveria falhar';
  exception when raise_exception then
    reset role;
    get stacked diagnostics msg = message_text;
    assert msg = 'Selecione ao menos um reembolso.', 'f2: ' || msg;
  end;
  set local role authenticated;
  begin
    perform public.pagar_reembolsos(array['71a00000-0000-4000-8000-000000000006']::uuid[], null);
    reset role;
    assert false, 'f3: deveria falhar';
  exception when raise_exception then
    reset role;
    get stacked diagnostics msg = message_text;
    assert msg = 'A data do pagamento não pode ser futura.', 'f3: ' || msg;
  end;
end $$;

-- (h) atleta e patrocinador não pagam
do $$
declare msg text; u text;
begin
  foreach u in array array['71000000-0000-4000-8000-000000000003', '71000000-0000-4000-8000-000000000005'] loop
    perform set_config('request.jwt.claim.sub', u, true);
    set local role authenticated;
    begin
      perform public.pagar_reembolsos(array['71a00000-0000-4000-8000-000000000006']::uuid[], current_date);
      reset role;
      assert false, 'h: deveria falhar para ' || u;
    exception when raise_exception then
      reset role;
      get stacked diagnostics msg = message_text;
      assert msg = 'Somente a gestão pode pagar reembolsos.', 'h: ' || msg;
    end;
  end loop;
  assert (select status from public.reembolsos where id = '71a00000-0000-4000-8000-000000000006') = 'aprovado', 'h2';
end $$;

-- (g) ids repetidos pagam uma vez
do $$
declare n int;
begin
  perform set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  n := public.pagar_reembolsos(array[
    '71a00000-0000-4000-8000-000000000006', null, '71a00000-0000-4000-8000-000000000006',
    '71a00000-0000-4000-8000-000000000004']::uuid[], current_date);
  reset role;
  assert n = 2, 'g1: ' || n;
  assert (select count(*) from public.reembolso_historico
          where reembolso_id = '71a00000-0000-4000-8000-000000000006' and status_novo = 'pago') = 1, 'g2';
  assert (select count(*) from public.avisos
          where tipo = 'reembolso_pago' and ref_id = '71a00000-0000-4000-8000-000000000006') = 1, 'g3';
end $$;

-- (i) update direto de pago_em/pago_por é negado
do $$
declare st text;
begin
  perform set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  begin
    update public.reembolsos set pago_em = current_date where id = '71a00000-0000-4000-8000-000000000007';
    reset role;
    assert false, 'i1: deveria falhar';
  exception when insufficient_privilege then
    reset role;
    get stacked diagnostics st = returned_sqlstate;
    assert st = '42501', 'i1: ' || st;
  end;
  set local role authenticated;
  begin
    update public.reembolsos set pago_por = '71000000-0000-4000-8000-000000000001'
      where id = '71a00000-0000-4000-8000-000000000007';
    reset role;
    assert false, 'i2: deveria falhar';
  exception when insufficient_privilege then
    reset role;
    get stacked diagnostics st = returned_sqlstate;
    assert st = '42501', 'i2: ' || st;
  end;
  assert (select pago_em from public.reembolsos where id = '71a00000-0000-4000-8000-000000000007') is null, 'i3';
end $$;

-- (j) botão individual: o gatilho preenche pago_em (hoje, São Paulo) e pago_por
do $$
begin
  perform set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  update public.reembolsos set status = 'pago' where id = '71a00000-0000-4000-8000-000000000007';
  reset role;
  assert (select pago_em from public.reembolsos where id = '71a00000-0000-4000-8000-000000000007')
         = (now() at time zone 'America/Sao_Paulo')::date, 'j1';
  assert (select pago_por from public.reembolsos where id = '71a00000-0000-4000-8000-000000000007')
         = '71000000-0000-4000-8000-000000000001', 'j2';
end $$;

-- (k) backfill: pago sem pago_em recebe a data da decisão ao reaplicar a migração
insert into public.reembolsos (id, atleta_id, descricao, valor, status) values
  ('71a00000-0000-4000-8000-000000000008', '71000000-0000-4000-8000-000000000003', 'x', 80, 'pago');
update public.reembolsos set decidido_em = timestamptz '2026-03-10 02:00:00+00',
  decidido_por = '71000000-0000-4000-8000-000000000002'
  where id = '71a00000-0000-4000-8000-000000000008';
insert into public.reembolsos (id, atleta_id, descricao, valor, status) values
  ('71a00000-0000-4000-8000-000000000009', '71000000-0000-4000-8000-000000000003', 'x', 90, 'pago');
do $$
begin
  assert (select pago_em from public.reembolsos where id = '71a00000-0000-4000-8000-000000000008') is null, 'k0';
end $$;
\ir ../../migracao_v3.sql
do $$
begin
  assert (select pago_em from public.reembolsos where id = '71a00000-0000-4000-8000-000000000008') = date '2026-03-09', 'k1';
  assert (select pago_por from public.reembolsos where id = '71a00000-0000-4000-8000-000000000008')
         = '71000000-0000-4000-8000-000000000002', 'k2';
  assert (select pago_em from public.reembolsos where id = '71a00000-0000-4000-8000-000000000009') = (now() at time zone 'America/Sao_Paulo')::date, 'k3: usa atualizado_em';
  assert (select pago_por from public.reembolsos where id = '71a00000-0000-4000-8000-000000000009') is null, 'k4';
end $$;

-- (l) depois do re-apply v2 (teste 30) + v3 e de reaplicar a v3, o botão individual ainda preenche pago_em
insert into public.reembolsos (id, atleta_id, descricao, valor, status) values
  ('71a00000-0000-4000-8000-00000000000a', '71000000-0000-4000-8000-000000000003', 'x', 15, 'aprovado');
do $$
begin
  perform set_config('request.jwt.claim.sub', '71000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  update public.reembolsos set status = 'pago' where id = '71a00000-0000-4000-8000-00000000000a';
  reset role;
  assert (select pago_em from public.reembolsos where id = '71a00000-0000-4000-8000-00000000000a')
         = (now() at time zone 'America/Sao_Paulo')::date, 'l1';
  assert (select pago_por from public.reembolsos where id = '71a00000-0000-4000-8000-00000000000a')
         = '71000000-0000-4000-8000-000000000002', 'l2';
end $$;

rollback;
