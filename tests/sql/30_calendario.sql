-- V2.3: calendário (distâncias, participantes, lista de presença)
insert into auth.users (id, email, raw_user_meta_data) values
  ('e1000000-0000-4000-8000-000000000001', 'cg1@t.com', '{"nome":"Gestor C"}'),
  ('e1000000-0000-4000-8000-000000000002', 'cat1@t.com', '{"nome":"Atleta A"}'),
  ('e1000000-0000-4000-8000-000000000003', 'cat2@t.com', '{"nome":"Atleta B"}'),
  ('e1000000-0000-4000-8000-000000000004', 'cnat@t.com', '{"nome":"Nao Atleta"}')
on conflict do nothing;
update public.perfis set papel = 'gestao', atleta = true where id = 'e1000000-0000-4000-8000-000000000001';
update public.perfis set atleta = false where id = 'e1000000-0000-4000-8000-000000000004';
update public.perfis set atleta = true where id in
  ('e1000000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000003');

insert into public.provas (id, nome, data, distancia) values
  ('f1000000-0000-4000-8000-000000000001', 'Cal futura 1', current_date + 30, '5k, 10k'),
  ('f1000000-0000-4000-8000-000000000002', 'Cal futura 2', current_date + 30, null),
  ('f1000000-0000-4000-8000-000000000003', 'Cal passada', current_date - 5, null),
  ('f1000000-0000-4000-8000-000000000004', 'Cal hoje', current_date, '   ')
on conflict do nothing;
insert into public.prova_distancias (id, prova_id, rotulo) values
  ('a1000000-0000-4000-8000-000000000002', 'f1000000-0000-4000-8000-000000000002', '21k'),
  ('a1000000-0000-4000-8000-000000000003', 'f1000000-0000-4000-8000-000000000003', '42k'),
  ('a1000000-0000-4000-8000-000000000004', 'f1000000-0000-4000-8000-000000000004', '3k'),
  ('a1000000-0000-4000-8000-000000000005', 'f1000000-0000-4000-8000-000000000004', '6k')
on conflict do nothing;

-- (a) texto antigo de distancia vira linha; não duplica ao reaplicar
\ir ../../migracao_v2.sql
do $$ begin
  assert (select count(*) from public.prova_distancias where prova_id = 'f1000000-0000-4000-8000-000000000001') = 1, 'a1';
  assert (select rotulo from public.prova_distancias where prova_id = 'f1000000-0000-4000-8000-000000000001') = '5k, 10k', 'a2';
  assert (select count(*) from public.prova_distancias where prova_id = 'f1000000-0000-4000-8000-000000000002') = 1, 'a3: já tinha linha';
  assert (select count(*) from public.prova_distancias where prova_id = 'f1000000-0000-4000-8000-000000000004') = 2, 'a4: texto em branco não migra';
end $$;
\ir ../../migracao_v2.sql
do $$ begin
  assert (select count(*) from public.prova_distancias where prova_id = 'f1000000-0000-4000-8000-000000000001') = 1, 'a5: duplicou';
  assert (select tem_lista_presenca from public.provas where id = 'f1000000-0000-4000-8000-000000000001') = false, 'a6';
end $$;

-- (b) A marca a prova; B não vê a linha de A; gestão vê
do $$
declare d1 uuid := (select id from public.prova_distancias where prova_id = 'f1000000-0000-4000-8000-000000000001');
begin
  perform set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  insert into public.prova_participantes (prova_id, atleta_id, distancia_id)
    values ('f1000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000002', d1);
  assert (select count(*) from public.prova_participantes) = 1, 'b1: A vê a própria';
  reset role;
  perform set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000003', true);
  set local role authenticated;
  assert (select count(*) from public.prova_participantes) = 0, 'b2: B não vê a de A';
  reset role;
  perform set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  assert (select count(*) from public.prova_participantes) = 1, 'b3: gestão vê';
  reset role;
end $$;

-- (c) distância de outra prova -> erro de FK (no insert e no update)
do $$
declare msg text; n int;
begin
  perform set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000003', true);
  set local role authenticated;
  begin
    insert into public.prova_participantes (prova_id, atleta_id, distancia_id)
      values ('f1000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-000000000002');
    assert false, 'c1: deveria falhar';
  exception when foreign_key_violation then
    get stacked diagnostics msg = message_text;
    assert msg like '%prova_participantes_distancia_id_prova_id_fkey%', msg;
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  begin
    update public.prova_participantes set distancia_id = 'a1000000-0000-4000-8000-000000000002'
      where atleta_id = 'e1000000-0000-4000-8000-000000000002';
    assert false, 'c2: deveria falhar';
  exception when foreign_key_violation then null;
  end;
  reset role;
end $$;

-- (c3) atleta A troca para outra distância da mesma prova (update) e não consegue mudar prova_id
do $$
declare msg text; n int;
begin
  insert into public.prova_distancias (id, prova_id, rotulo)
    values ('a1000000-0000-4000-8000-000000000006', 'f1000000-0000-4000-8000-000000000001', '15k');
  perform set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  update public.prova_participantes set distancia_id = 'a1000000-0000-4000-8000-000000000006'
    where atleta_id = 'e1000000-0000-4000-8000-000000000002';
  get diagnostics n = row_count;
  assert n = 1, 'c3';
  begin
    update public.prova_participantes set prova_id = 'f1000000-0000-4000-8000-000000000002';
    assert false, 'c4: deveria falhar';
  exception when insufficient_privilege then
    get stacked diagnostics msg = message_text;
    assert msg like 'permission denied%', msg;
  end;
  reset role;
end $$;

-- (d) prova passada: insert recusado pela RLS; update e delete afetam 0 linhas; hoje é permitido
do $$
declare msg text; n int;
begin
  insert into public.prova_participantes (prova_id, atleta_id, distancia_id)
    values ('f1000000-0000-4000-8000-000000000003', 'e1000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-000000000003');
  perform set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  begin
    insert into public.prova_participantes (prova_id, atleta_id, distancia_id)
      values ('f1000000-0000-4000-8000-000000000003', 'e1000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000003');
    assert false, 'd1: deveria falhar';
  exception when insufficient_privilege then
    get stacked diagnostics msg = message_text;
    assert msg like 'new row violates row-level security policy for table "prova_participantes"', msg;
  end;
  reset role;
  -- A tem linha em prova passada (inserida pelo superusuário): não pode alterar nem apagar
  insert into public.prova_participantes (prova_id, atleta_id, distancia_id)
    values ('f1000000-0000-4000-8000-000000000004', 'e1000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000004');
  update public.provas set data = current_date - 1 where id = 'f1000000-0000-4000-8000-000000000004';
  set local role authenticated;
  update public.prova_participantes set distancia_id = 'a1000000-0000-4000-8000-000000000005'
    where prova_id = 'f1000000-0000-4000-8000-000000000004';
  get diagnostics n = row_count;
  assert n = 0, 'd2: update em prova passada';
  delete from public.prova_participantes where prova_id = 'f1000000-0000-4000-8000-000000000004';
  get diagnostics n = row_count;
  assert n = 0, 'd3: delete em prova passada';
  reset role;
  assert (select distancia_id from public.prova_participantes
          where prova_id = 'f1000000-0000-4000-8000-000000000004') = 'a1000000-0000-4000-8000-000000000004', 'd4';
  -- hoje (data = current_date) ainda pode
  update public.provas set data = current_date where id = 'f1000000-0000-4000-8000-000000000004';
  set local role authenticated;
  update public.prova_participantes set distancia_id = 'a1000000-0000-4000-8000-000000000005'
    where prova_id = 'f1000000-0000-4000-8000-000000000004';
  get diagnostics n = row_count;
  assert n = 1, 'd5: hoje permitido';
  reset role;
end $$;

-- (e) A apagando a linha de B -> 0 linhas; apagar a própria -> 1
do $$
declare n int;
begin
  insert into public.prova_participantes (prova_id, atleta_id, distancia_id)
    values ('f1000000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-000000000002');
  perform set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  delete from public.prova_participantes where atleta_id = 'e1000000-0000-4000-8000-000000000003';
  get diagnostics n = row_count;
  assert n = 0, 'e1';
  reset role;
  assert (select count(*) from public.prova_participantes where atleta_id = 'e1000000-0000-4000-8000-000000000003'
          and prova_id = 'f1000000-0000-4000-8000-000000000002') = 1, 'e2';
  -- A não pode inscrever B
  set local role authenticated;
  begin
    insert into public.prova_participantes (prova_id, atleta_id, distancia_id)
      values ('f1000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-000000000006');
    assert false, 'e3: deveria falhar';
  exception when insufficient_privilege then null;
  end;
  delete from public.prova_participantes where atleta_id = 'e1000000-0000-4000-8000-000000000002'
    and prova_id = 'f1000000-0000-4000-8000-000000000001';
  get diagnostics n = row_count;
  assert n = 1, 'e4: apaga a própria';
  reset role;
end $$;

-- (e5) quem não é atleta não se inscreve
do $$
declare msg text;
begin
  perform set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000004', true);
  set local role authenticated;
  begin
    insert into public.prova_participantes (prova_id, atleta_id, distancia_id)
      values ('f1000000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-000000000002');
    assert false, 'e5: deveria falhar';
  exception when insufficient_privilege then
    get stacked diagnostics msg = message_text;
    assert msg like 'new row violates row-level security policy%', msg;
  end;
  reset role;
end $$;

-- (g) não-gestão não escreve distâncias; todos leem; anon sem acesso
do $$
declare msg text; n int;
begin
  perform set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  assert (select count(*) from public.prova_distancias) >= 5, 'g0: atleta lê distâncias';
  begin
    insert into public.prova_distancias (prova_id, rotulo) values ('f1000000-0000-4000-8000-000000000002', 'hack');
    assert false, 'g1: deveria falhar';
  exception when insufficient_privilege then
    get stacked diagnostics msg = message_text;
    assert msg like 'new row violates row-level security policy for table "prova_distancias"', msg;
  end;
  update public.prova_distancias set rotulo = 'hack' where id = 'a1000000-0000-4000-8000-000000000002';
  get diagnostics n = row_count;
  assert n = 0, 'g2';
  delete from public.prova_distancias where id = 'a1000000-0000-4000-8000-000000000002';
  get diagnostics n = row_count;
  assert n = 0, 'g3';
  reset role;
  perform set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  insert into public.prova_distancias (id, prova_id, rotulo, ordem) values ('a1000000-0000-4000-8000-000000000007', 'f1000000-0000-4000-8000-000000000002', 'ok', 1);
  assert (select count(*) from public.prova_distancias where id = 'a1000000-0000-4000-8000-000000000007') = 1, 'g5: gestão insere distância';
  reset role;
  set local role anon;
  begin
    perform 1 from public.prova_distancias;
    assert false, 'g6: anon deveria falhar';
  exception when insufficient_privilege then null;
  end;
  begin
    perform 1 from public.prova_participantes;
    assert false, 'g7: anon deveria falhar';
  exception when insufficient_privilege then null;
  end;
  reset role;
end $$;

-- (f) apagar a prova remove participantes e distâncias
do $$
begin
  assert (select count(*) from public.prova_participantes where prova_id = 'f1000000-0000-4000-8000-000000000002') = 1, 'f0';
  delete from public.provas where id = 'f1000000-0000-4000-8000-000000000002';
  assert (select count(*) from public.prova_participantes where prova_id = 'f1000000-0000-4000-8000-000000000002') = 0, 'f1';
  assert (select count(*) from public.prova_distancias where prova_id = 'f1000000-0000-4000-8000-000000000002') = 0, 'f2';
end $$;
