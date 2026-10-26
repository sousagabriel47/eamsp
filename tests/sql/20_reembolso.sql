-- V2.2: valor da inscrição, reenvio e histórico de reembolso
insert into auth.users (id, email, raw_user_meta_data) values
  ('e0000000-0000-4000-8000-000000000001', 'rg1@t.com', '{"nome":"Gestor R"}'),
  ('e0000000-0000-4000-8000-000000000002', 'rat1@t.com', '{"nome":"Atleta Dono"}'),
  ('e0000000-0000-4000-8000-000000000003', 'rat2@t.com', '{"nome":"Atleta Outro"}')
on conflict do nothing;
update public.perfis set papel = 'gestao', atleta = true where id = 'e0000000-0000-4000-8000-000000000001';
update public.perfis set atleta = true where id in
  ('e0000000-0000-4000-8000-000000000002', 'e0000000-0000-4000-8000-000000000003');

insert into public.provas (id, nome, data, valor_inscricao) values
  ('f0000000-0000-4000-8000-000000000001', 'Prova com valor', current_date + 30, 150.50),
  ('f0000000-0000-4000-8000-000000000002', 'Prova sem valor', current_date + 30, null),
  ('f0000000-0000-4000-8000-000000000003', 'Prova nova', current_date + 40, 99.00)
on conflict do nothing;

-- (a) valor_prova vem da prova, nunca do cliente
do $$
declare msg text;
begin
  perform set_config('request.jwt.claim.sub', 'e0000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  insert into public.reembolsos (id, atleta_id, prova_id, descricao, valor, valor_prova) values
    ('d0000000-0000-4000-8000-000000000001', 'e0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000001', 'x', 100, 9999),
    ('d0000000-0000-4000-8000-000000000002', 'e0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000002', 'x', 100, 9999),
    ('d0000000-0000-4000-8000-000000000003', 'e0000000-0000-4000-8000-000000000002', null, 'x', 100, 9999);
  reset role;
  assert (select valor_prova from public.reembolsos where id = 'd0000000-0000-4000-8000-000000000001') = 150.50, 'a1';
  assert (select valor_prova from public.reembolsos where id = 'd0000000-0000-4000-8000-000000000002') is null, 'a2';
  assert (select valor_prova from public.reembolsos where id = 'd0000000-0000-4000-8000-000000000003') is null, 'a3';
  -- valor_inscricao negativo é recusado
  begin
    insert into public.provas (nome, data, valor_inscricao) values ('neg', current_date, -1);
    assert false, 'a4: deveria falhar';
  exception when check_violation then null;
  end;
end $$;

-- (b) gestão recusa com motivo -> histórico com motivo e valor
do $$
begin
  perform set_config('request.jwt.claim.sub', 'e0000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  update public.reembolsos set status = 'recusado', motivo_decisao = 'Falta comprovante'
    where id = 'd0000000-0000-4000-8000-000000000001';
  reset role;
  assert (select count(*) from public.reembolso_historico
          where reembolso_id = 'd0000000-0000-4000-8000-000000000001'
            and status_anterior = 'pendente' and status_novo = 'recusado'
            and motivo = 'Falta comprovante' and valor = 100) = 1, 'b';
end $$;

-- (c) dono reenvia alterando valor e prova
do $$
begin
  perform set_config('request.jwt.claim.sub', 'e0000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  update public.reembolsos set status = 'pendente', valor = 80, prova_id = 'f0000000-0000-4000-8000-000000000003', descricao = 'novo'
    where id = 'd0000000-0000-4000-8000-000000000001';
  reset role;
  assert (select status from public.reembolsos where id = 'd0000000-0000-4000-8000-000000000001') = 'pendente', 'c1';
  assert (select motivo_decisao from public.reembolsos where id = 'd0000000-0000-4000-8000-000000000001') is null, 'c2';
  assert (select decidido_por from public.reembolsos where id = 'd0000000-0000-4000-8000-000000000001') is null, 'c3';
  assert (select decidido_em from public.reembolsos where id = 'd0000000-0000-4000-8000-000000000001') is null, 'c4';
  assert (select valor from public.reembolsos where id = 'd0000000-0000-4000-8000-000000000001') = 80, 'c5';
  assert (select valor_prova from public.reembolsos where id = 'd0000000-0000-4000-8000-000000000001') = 99.00, 'c6';
  assert (select count(*) from public.reembolso_historico
          where reembolso_id = 'd0000000-0000-4000-8000-000000000001'
            and status_anterior = 'recusado' and status_novo = 'pendente'
            and motivo is null and valor = 80) = 1, 'c7';
end $$;

-- (d) outro atleta não reenvia; gestão (não dona) também não
do $$
declare msg text; n int;
begin
  perform set_config('request.jwt.claim.sub', 'e0000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  update public.reembolsos set status = 'recusado', motivo_decisao = 'Ilegível'
    where id = 'd0000000-0000-4000-8000-000000000001';
  reset role;

  perform set_config('request.jwt.claim.sub', 'e0000000-0000-4000-8000-000000000003', true);
  set local role authenticated;
  update public.reembolsos set status = 'pendente', valor = 1 where id = 'd0000000-0000-4000-8000-000000000001';
  get diagnostics n = row_count;
  reset role;
  assert n = 0, 'd1: RLS deveria bloquear';
  assert (select status from public.reembolsos where id = 'd0000000-0000-4000-8000-000000000001') = 'recusado', 'd2';

  perform set_config('request.jwt.claim.sub', 'e0000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  begin
    update public.reembolsos set status = 'pendente', valor = 1 where id = 'd0000000-0000-4000-8000-000000000001';
    assert false, 'd3: deveria falhar';
  exception when others then
    get stacked diagnostics msg = message_text;
    assert msg not like 'd3:%', msg;
    assert msg like '%Só o dono do pedido pode reenviá-lo%', msg;
  end;
  reset role;
end $$;

-- (e) reenviar pago, aprovado e cancelado falha
do $$
declare i int; n int; ids uuid[] := array[
  'd0000000-0000-4000-8000-000000000011','d0000000-0000-4000-8000-000000000012','d0000000-0000-4000-8000-000000000013']::uuid[];
begin
  insert into public.reembolsos (id, atleta_id, descricao, valor, status) values
    (ids[1], 'e0000000-0000-4000-8000-000000000002', 'p', 10, 'pago'),
    (ids[2], 'e0000000-0000-4000-8000-000000000002', 'a', 10, 'aprovado'),
    (ids[3], 'e0000000-0000-4000-8000-000000000002', 'c', 10, 'cancelado');
  perform set_config('request.jwt.claim.sub', 'e0000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  for i in 1..3 loop
    -- sem política de reenvio para esses status: RLS filtra a linha
    update public.reembolsos set status = 'pendente', valor = 11 where id = ids[i];
    get diagnostics n = row_count;
    assert n = 0, 'e: RLS deveria bloquear ' || i;
  end loop;
  reset role;
  assert (select count(*) from public.reembolsos where id = any(ids) and valor = 10
          and status in ('pago','aprovado','cancelado')) = 3, 'e-final';
end $$;

-- (f) editar valor de pedido pendente sem mudar status
do $$
declare msg text;
begin
  insert into public.reembolsos (id, atleta_id, descricao, valor)
  values ('d0000000-0000-4000-8000-000000000021', 'e0000000-0000-4000-8000-000000000002', 'pend', 10);
  perform set_config('request.jwt.claim.sub', 'e0000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  begin
    update public.reembolsos set valor = 20 where id = 'd0000000-0000-4000-8000-000000000021';
    assert false, 'f: deveria falhar';
  exception when others then
    get stacked diagnostics msg = message_text;
    assert msg not like 'f:%', msg;
    assert msg like '%Só é possível editar um pedido recusado ao reenviá-lo%', msg;
  end;
  reset role;
end $$;

-- (g) dono lê o próprio histórico; outro atleta não
do $$
declare n int;
begin
  perform set_config('request.jwt.claim.sub', 'e0000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  select count(*) into n from public.reembolso_historico where reembolso_id = 'd0000000-0000-4000-8000-000000000001';
  assert n = 3, 'g1: dono deveria ver 3 linhas, viu ' || n;
  reset role;
  perform set_config('request.jwt.claim.sub', 'e0000000-0000-4000-8000-000000000003', true);
  set local role authenticated;
  select count(*) into n from public.reembolso_historico where reembolso_id = 'd0000000-0000-4000-8000-000000000001';
  assert n = 0, 'g2: outro atleta não deveria ver';
  -- ninguém grava no histórico pelo cliente
  begin
    insert into public.reembolso_historico (reembolso_id, status_novo) values ('d0000000-0000-4000-8000-000000000001', 'pago');
    assert false, 'g3: deveria falhar';
  exception when insufficient_privilege then null;
  end;
  reset role;
end $$;

-- (h) decisão forjada no insert é zerada
do $$
declare r public.reembolsos;
begin
  perform set_config('request.jwt.claim.sub', 'e0000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  insert into public.reembolsos (id, atleta_id, descricao, valor, motivo_decisao, decidido_por, decidido_em)
  values ('d0000000-0000-4000-8000-000000000031', 'e0000000-0000-4000-8000-000000000002', 'forjado', 10,
          'forjado', 'e0000000-0000-4000-8000-000000000001', now());
  reset role;
  select * into r from public.reembolsos where id = 'd0000000-0000-4000-8000-000000000031';
  assert r.motivo_decisao is null and r.decidido_por is null and r.decidido_em is null, 'h';
end $$;

-- (i) dono não consegue gravar valor_prova no reenvio
do $$
declare msg text;
begin
  perform set_config('request.jwt.claim.sub', 'e0000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  update public.reembolsos set status = 'recusado', motivo_decisao = 'x'
    where id = 'd0000000-0000-4000-8000-000000000001' and status = 'pendente';
  reset role;
  perform set_config('request.jwt.claim.sub', 'e0000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  begin
    update public.reembolsos set status = 'pendente', valor_prova = 1 where id = 'd0000000-0000-4000-8000-000000000001';
    assert false, 'i: deveria falhar';
  exception when insufficient_privilege then
    get stacked diagnostics msg = message_text;
    assert msg like 'permission denied%', msg;
  end;
  reset role;
end $$;
