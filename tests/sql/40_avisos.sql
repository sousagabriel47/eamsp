-- V2.4: avisos de decisão (reembolso e renovação)
insert into auth.users (id, email, raw_user_meta_data) values
  ('c4000000-0000-4000-8000-000000000001', 'vg@t.com', '{"nome":"Gestor V"}'),
  ('c4000000-0000-4000-8000-000000000002', 'va@t.com', '{"nome":"Atleta VA"}'),
  ('c4000000-0000-4000-8000-000000000003', 'vb@t.com', '{"nome":"Atleta VB"}')
on conflict do nothing;
update public.perfis set papel = 'gestao', atleta = true where id = 'c4000000-0000-4000-8000-000000000001';
update public.perfis set atleta = true where id in
  ('c4000000-0000-4000-8000-000000000002', 'c4000000-0000-4000-8000-000000000003');

insert into public.reembolsos (id, atleta_id, descricao, valor) values
  ('c4100000-0000-4000-8000-000000000001', 'c4000000-0000-4000-8000-000000000002', 'r1', 120),
  ('c4100000-0000-4000-8000-000000000002', 'c4000000-0000-4000-8000-000000000002', 'r2', 1234.5),
  ('c4100000-0000-4000-8000-000000000003', 'c4000000-0000-4000-8000-000000000002', 'r3', 50)
on conflict do nothing;
insert into public.renovacoes (id, atleta_id, tipo, nova_validade, status) values
  ('c4200000-0000-4000-8000-000000000001', 'c4000000-0000-4000-8000-000000000002', 'atestado', date '2027-03-05', 'pendente'),
  ('c4200000-0000-4000-8000-000000000002', 'c4000000-0000-4000-8000-000000000002', 'anuidade', date '2027-12-31', 'pendente')
on conflict do nothing;

-- (a) gestão decide reembolsos
do $$
declare t text;
begin
  perform set_config('request.jwt.claim.sub', 'c4000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  update public.reembolsos set status = 'aprovado' where id = 'c4100000-0000-4000-8000-000000000001';
  update public.reembolsos set status = 'recusado', motivo_decisao = 'Comprovante ilegível'
    where id = 'c4100000-0000-4000-8000-000000000002';
  reset role;
  assert (select count(*) from public.avisos where ref_id = 'c4100000-0000-4000-8000-000000000001') = 1, 'a1';
  select texto into t from public.avisos where ref_id = 'c4100000-0000-4000-8000-000000000001' and tipo = 'reembolso_aprovado';
  assert t like '%R$ 120,00%', 'a2: ' || coalesce(t, 'null');
  assert (select usuario_id from public.avisos where ref_id = 'c4100000-0000-4000-8000-000000000001') = 'c4000000-0000-4000-8000-000000000002', 'a3';
  select texto into t from public.avisos where ref_id = 'c4100000-0000-4000-8000-000000000002' and tipo = 'reembolso_recusado';
  assert t like '%R$ 1.234,50%' and t like '%Comprovante ilegível%', 'a4: ' || coalesce(t, 'null');
  -- pagar o aprovado
  perform set_config('request.jwt.claim.sub', 'c4000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  update public.reembolsos set status = 'pago' where id = 'c4100000-0000-4000-8000-000000000001';
  reset role;
  assert (select count(*) from public.avisos where ref_id = 'c4100000-0000-4000-8000-000000000001') = 2, 'a5';
  assert (select count(*) from public.avisos where ref_id = 'c4100000-0000-4000-8000-000000000001' and tipo = 'reembolso_pago') = 1, 'a6';
end $$;

-- (b) reenvio do recusado e cancelamento não geram aviso
do $$
begin
  perform set_config('request.jwt.claim.sub', 'c4000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  update public.reembolsos set status = 'pendente' where id = 'c4100000-0000-4000-8000-000000000002';
  update public.reembolsos set status = 'cancelado' where id = 'c4100000-0000-4000-8000-000000000003';
  reset role;
  assert (select count(*) from public.avisos where ref_id = 'c4100000-0000-4000-8000-000000000002') = 1, 'b1: reenvio gerou aviso';
  assert (select count(*) from public.avisos where ref_id = 'c4100000-0000-4000-8000-000000000003') = 0, 'b2: cancelamento gerou aviso';
end $$;

-- (c) renovações
do $$
declare t text;
begin
  perform set_config('request.jwt.claim.sub', 'c4000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  update public.renovacoes set status = 'aprovada', emitido_em = current_date
    where id = 'c4200000-0000-4000-8000-000000000001';
  update public.renovacoes set status = 'recusada', motivo_decisao = 'Documento vencido'
    where id = 'c4200000-0000-4000-8000-000000000002';
  reset role;
  select texto into t from public.avisos where ref_id = 'c4200000-0000-4000-8000-000000000001' and tipo = 'renovacao_aprovada';
  assert t like '%atestado%' and t like '%05/03/2027%', 'c1: ' || coalesce(t, 'null');
  select texto into t from public.avisos where ref_id = 'c4200000-0000-4000-8000-000000000002' and tipo = 'renovacao_recusada';
  assert t like '%anuidade%' and t like '%Documento vencido%', 'c2: ' || coalesce(t, 'null');
  assert (select count(*) from public.avisos where ref_id in
    ('c4200000-0000-4000-8000-000000000001', 'c4200000-0000-4000-8000-000000000002')) = 2, 'c3';
end $$;

-- (d) RLS: B não lê avisos de A; A lê os seus e marca lido_em
do $$
declare msg text; n int;
begin
  perform set_config('request.jwt.claim.sub', 'c4000000-0000-4000-8000-000000000003', true);
  set local role authenticated;
  assert (select count(*) from public.avisos) = 0, 'd1: B vê avisos de A';
  update public.avisos set lido_em = now();
  get diagnostics n = row_count;
  assert n = 0, 'd2: B alterou avisos de A';
  reset role;
  perform set_config('request.jwt.claim.sub', 'c4000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  assert (select count(*) from public.avisos) = 5, 'd3: A deveria ver 5, viu ' || (select count(*) from public.avisos);
  update public.avisos set lido_em = now() where tipo = 'reembolso_pago';
  get diagnostics n = row_count;
  assert n = 1, 'd4';
  reset role;
  assert (select count(*) from public.avisos where lido_em is not null) = 1, 'd5';
end $$;

-- (e) A não altera texto nem insere nem apaga
do $$
declare msg text; n int;
begin
  perform set_config('request.jwt.claim.sub', 'c4000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  begin
    update public.avisos set texto = 'hack';
    assert false, 'e1: deveria falhar';
  exception when insufficient_privilege then
    get stacked diagnostics msg = message_text;
    assert msg like 'permission denied for table avisos%', 'e1: ' || msg;
  end;
  begin
    insert into public.avisos (usuario_id, tipo, texto)
      values ('c4000000-0000-4000-8000-000000000002', 'x', 'falso');
    assert false, 'e2: deveria falhar';
  exception when insufficient_privilege then
    get stacked diagnostics msg = message_text;
    assert msg like 'permission denied for table avisos%', 'e2: ' || msg;
  end;
  begin
    delete from public.avisos;
    assert false, 'e3: deveria falhar';
  exception when insufficient_privilege then
    get stacked diagnostics msg = message_text;
    assert msg like 'permission denied for table avisos%', 'e3: ' || msg;
  end;
  reset role;
end $$;

-- (f) anon sem acesso
do $$
declare msg text;
begin
  set local role anon;
  begin
    perform count(*) from public.avisos;
    assert false, 'f1: deveria falhar';
  exception when insufficient_privilege then null;
  end;
  reset role;
end $$;
