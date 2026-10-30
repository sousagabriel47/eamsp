-- V3.2: pago_em/pago_por não podem ser forjados pelo atleta no INSERT nem por update sem virar "pago"
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('73000000-0000-4000-8000-000000000001', 'fg1@t.com', '{"nome":"Gestor F1"}'),
  ('73000000-0000-4000-8000-000000000002', 'fat1@t.com', '{"nome":"Atleta F1"}')
on conflict do nothing;
update public.perfis set papel = 'gestao', atleta = true where id = '73000000-0000-4000-8000-000000000001';
update public.perfis set atleta = true where id = '73000000-0000-4000-8000-000000000002';

-- (a) atleta insere reembolso com pago_em/pago_por forjados: ficam nulos
do $$
begin
  perform set_config('request.jwt.claim.sub', '73000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  insert into public.reembolsos (id, atleta_id, descricao, valor, status, pago_em, pago_por)
  values ('73a00000-0000-4000-8000-000000000001', '73000000-0000-4000-8000-000000000002', 'x', 10, 'pendente',
          date '2020-01-01', '73000000-0000-4000-8000-000000000002');
  reset role;
  assert (select pago_em from public.reembolsos where id = '73a00000-0000-4000-8000-000000000001') is null, 'a1';
  assert (select pago_por from public.reembolsos where id = '73a00000-0000-4000-8000-000000000001') is null, 'a2';
end $$;

-- (b) gestão aprova e paga individualmente: data de hoje (São Paulo) e o gestor
do $$
begin
  perform set_config('request.jwt.claim.sub', '73000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  update public.reembolsos set status = 'aprovado' where id = '73a00000-0000-4000-8000-000000000001';
  update public.reembolsos set status = 'pago' where id = '73a00000-0000-4000-8000-000000000001';
  reset role;
  assert (select pago_em from public.reembolsos where id = '73a00000-0000-4000-8000-000000000001')
         = (now() at time zone 'America/Sao_Paulo')::date, 'b1';
  assert (select pago_por from public.reembolsos where id = '73a00000-0000-4000-8000-000000000001')
         = '73000000-0000-4000-8000-000000000001', 'b2';
end $$;

-- (c) update direto da gestão sem virar "pago" não altera pago_*
insert into public.reembolsos (id, atleta_id, descricao, valor, status) values
  ('73a00000-0000-4000-8000-000000000002', '73000000-0000-4000-8000-000000000002', 'x', 20, 'aprovado');
do $$
begin
  perform set_config('request.jwt.claim.sub', '73000000-0000-4000-8000-000000000001', true);
  -- update direto da gestão (aprovado -> aprovado) não altera pago_*
  set local role authenticated;
  update public.reembolsos set status = 'aprovado' where id = '73a00000-0000-4000-8000-000000000002';
  reset role;
  assert (select pago_em from public.reembolsos where id = '73a00000-0000-4000-8000-000000000002') is null, 'c3';
  assert (select pago_por from public.reembolsos where id = '73a00000-0000-4000-8000-000000000002') is null, 'c4';
end $$;

-- (d) pagar_reembolsos: data anterior à solicitação é negada, tudo ou nada
insert into public.reembolsos (id, atleta_id, descricao, valor, status) values
  ('73a00000-0000-4000-8000-000000000003', '73000000-0000-4000-8000-000000000002', 'x', 30, 'aprovado'),
  ('73a00000-0000-4000-8000-000000000004', '73000000-0000-4000-8000-000000000002', 'x', 40, 'aprovado');
update public.reembolsos set criado_em = timestamptz '2026-02-10 12:00:00+00'
  where id = '73a00000-0000-4000-8000-000000000004';
update public.reembolsos set criado_em = timestamptz '2026-01-01 12:00:00+00'
  where id = '73a00000-0000-4000-8000-000000000003';
do $$
declare msg text; n int;
begin
  perform set_config('request.jwt.claim.sub', '73000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  begin
    perform public.pagar_reembolsos(array['73a00000-0000-4000-8000-000000000003',
      '73a00000-0000-4000-8000-000000000004']::uuid[], date '2026-02-09');
    reset role;
    assert false, 'd: deveria falhar';
  exception when raise_exception then
    reset role;
    get stacked diagnostics msg = message_text;
    assert msg = 'A data do pagamento não pode ser anterior à data da solicitação.', 'd: ' || msg;
  end;
  assert (select count(*) from public.reembolsos
          where id in ('73a00000-0000-4000-8000-000000000003', '73a00000-0000-4000-8000-000000000004')
            and status = 'aprovado' and pago_em is null) = 2, 'd2';
  -- no dia da solicitação mais recente vale
  set local role authenticated;
  n := public.pagar_reembolsos(array['73a00000-0000-4000-8000-000000000003',
      '73a00000-0000-4000-8000-000000000004']::uuid[], date '2026-02-10');
  reset role;
  assert n = 2, 'd3: ' || n;
end $$;

rollback;
