-- Correções da revisão final: apagar prova com reembolsos, datas forjadas em renovação,
-- reenvio exige atleta, fuso de São Paulo nas políticas de participantes
insert into auth.users (id, email, raw_user_meta_data) values
  ('e5000000-0000-4000-8000-000000000001', 'cf1@t.com', '{"nome":"Gestor CF"}'),
  ('e5000000-0000-4000-8000-000000000002', 'cf2@t.com', '{"nome":"Atleta CF"}'),
  ('e5000000-0000-4000-8000-000000000003', 'cf3@t.com', '{"nome":"Gestor CF Dois"}')
on conflict do nothing;
update public.perfis set papel = 'gestao', atleta = true where id in
  ('e5000000-0000-4000-8000-000000000001', 'e5000000-0000-4000-8000-000000000003');
update public.perfis set atleta = true where id = 'e5000000-0000-4000-8000-000000000002';

-- (1) apagar prova com reembolsos em todos os status
insert into public.provas (id, nome, data, valor_inscricao)
select ('f5000000-0000-4000-8000-00000000000' || n)::uuid, 'Prova CF ' || n, current_date + 30, 77
from generate_series(1, 5) n on conflict do nothing;

do $$
declare i int; st text[] := array['pendente','aprovado','pago','recusado','cancelado'];
        rid uuid; pid uuid; msg text;
begin
  for i in 1..5 loop
    rid := ('d5000000-0000-4000-8000-00000000000' || i)::uuid;
    pid := ('f5000000-0000-4000-8000-00000000000' || i)::uuid;
    perform set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000002', true);
    insert into public.reembolsos (id, atleta_id, prova_id, descricao, valor)
    values (rid, 'e5000000-0000-4000-8000-000000000002', pid, 'x', 10);
    perform set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);
    if st[i] = 'aprovado' or st[i] = 'pago' then
      update public.reembolsos set status = 'aprovado' where id = rid;
    end if;
    if st[i] = 'pago' then update public.reembolsos set status = 'pago' where id = rid; end if;
    if st[i] = 'recusado' then update public.reembolsos set status = 'recusado', motivo_decisao = 'm' where id = rid; end if;
    if st[i] = 'cancelado' then
      perform set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000002', true);
      update public.reembolsos set status = 'cancelado' where id = rid;
    end if;
    assert (select status from public.reembolsos where id = rid) = st[i], '1.pre ' || st[i];
  end loop;

  -- o atleta não consegue desvincular a prova por update direto (prova existe)
  perform set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  begin
    update public.reembolsos set prova_id = null where id = 'd5000000-0000-4000-8000-000000000001';
    assert false, '1.atleta: deveria falhar';
  exception when others then
    get stacked diagnostics msg = message_text;
    assert msg not like '1.atleta%', msg;
    assert msg = 'Só é possível editar um pedido recusado ao reenviá-lo.' or msg like 'new row violates%', msg;
  end;
  reset role;
  assert (select prova_id from public.reembolsos where id = 'd5000000-0000-4000-8000-000000000001') is not null, '1.atleta mantém';

  -- a gestão apaga as 5 provas
  perform set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  delete from public.provas where id::text like 'f5000000-0000-4000-8000-00000000000%';
  reset role;
  assert (select count(*) from public.provas where id::text like 'f5000000-0000-4000-8000-00000000000%') = 0, '1.apagou';
  assert (select count(*) from public.reembolsos where id::text like 'd5000000-0000-4000-8000-00000000000%'
          and prova_id is null and valor_prova = 77) = 5, '1.prova_id nulo, valor_prova mantido';
  for i in 1..5 loop
    assert (select status from public.reembolsos where id = ('d5000000-0000-4000-8000-00000000000' || i)::uuid) = st[i], '1.status ' || i;
  end loop;
end $$;

-- (2) datas forjadas na criação de renovação
do $$
declare r public.renovacoes;
begin
  perform set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  insert into public.renovacoes (id, atleta_id, tipo, nova_validade, emitido_em, pago_em) values
    ('b5000000-0000-4000-8000-000000000001', 'e5000000-0000-4000-8000-000000000002', 'anuidade', current_date + 200, current_date - 5, current_date - 3),
    ('b5000000-0000-4000-8000-000000000002', 'e5000000-0000-4000-8000-000000000002', 'atestado', current_date + 100, current_date - 5, current_date - 3);
  reset role;
  assert (select count(*) from public.renovacoes where id::text like 'b5000000-%' and emitido_em is null and pago_em is null) = 2, '2.datas nulas';
  -- gestão aprova o atestado com emissão válida
  perform set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  update public.renovacoes set status = 'aprovada', emitido_em = current_date
    where id = 'b5000000-0000-4000-8000-000000000002';
  reset role;
  select * into r from public.renovacoes where id = 'b5000000-0000-4000-8000-000000000002';
  assert r.status = 'aprovada' and r.emitido_em = current_date and r.pago_em is null, '2.atestado aprovado';
end $$;

-- (6) reenvio exige o papel de atleta
do $$
declare n int;
begin
  perform set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000002', true);
  insert into public.reembolsos (id, atleta_id, descricao, valor)
    values ('d5000000-0000-4000-8000-000000000011', 'e5000000-0000-4000-8000-000000000002', 'r', 10);
  perform set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000001', true);
  update public.reembolsos set status = 'recusado', motivo_decisao = 'm' where id = 'd5000000-0000-4000-8000-000000000011';
  update public.perfis set atleta = false where id = 'e5000000-0000-4000-8000-000000000002';
  perform set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  update public.reembolsos set status = 'pendente' where id = 'd5000000-0000-4000-8000-000000000011';
  get diagnostics n = row_count;
  reset role;
  assert n = 0, '6: sem a flag de atleta não reenvia';
  assert (select status from public.reembolsos where id = 'd5000000-0000-4000-8000-000000000011') = 'recusado', '6: segue recusado';
  update public.perfis set atleta = true where id = 'e5000000-0000-4000-8000-000000000002';
  set local role authenticated;
  update public.reembolsos set status = 'pendente' where id = 'd5000000-0000-4000-8000-000000000011';
  get diagnostics n = row_count;
  reset role;
  assert n = 1, '6: com a flag reenvia';
end $$;

-- (5) participantes: "hoje" é o de São Paulo; prova de hoje (SP) é permitida, de ontem (SP) não
insert into public.provas (id, nome, data) values
  ('f5000000-0000-4000-8000-000000000011', 'Hoje SP', (now() at time zone 'America/Sao_Paulo')::date),
  ('f5000000-0000-4000-8000-000000000012', 'Ontem SP', (now() at time zone 'America/Sao_Paulo')::date - 1)
on conflict do nothing;
insert into public.prova_distancias (id, prova_id, rotulo) values
  ('a5000000-0000-4000-8000-000000000011', 'f5000000-0000-4000-8000-000000000011', '5k'),
  ('a5000000-0000-4000-8000-000000000012', 'f5000000-0000-4000-8000-000000000012', '5k')
on conflict do nothing;
do $$
begin
  perform set_config('request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  insert into public.prova_participantes (prova_id, atleta_id, distancia_id)
    values ('f5000000-0000-4000-8000-000000000011', 'e5000000-0000-4000-8000-000000000002', 'a5000000-0000-4000-8000-000000000011');
  begin
    insert into public.prova_participantes (prova_id, atleta_id, distancia_id)
      values ('f5000000-0000-4000-8000-000000000012', 'e5000000-0000-4000-8000-000000000002', 'a5000000-0000-4000-8000-000000000012');
    assert false, '5: prova de ontem deveria falhar';
  exception when insufficient_privilege then null;
  end;
  reset role;
end $$;
