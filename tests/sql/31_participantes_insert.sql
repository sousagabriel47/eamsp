-- "Vou correr": INSERT simples funciona para o atleta; upsert (ON CONFLICT DO UPDATE
-- SET prova_id/atleta_id) exige UPDATE em colunas que o atleta não tem -> não usar upsert.
insert into auth.users (id, email, raw_user_meta_data) values
  ('e2000000-0000-4000-8000-000000000001', 'pi1@t.com', '{"nome":"Atleta PI"}')
on conflict do nothing;
update public.perfis set atleta = true where id = 'e2000000-0000-4000-8000-000000000001';
insert into public.provas (id, nome, data) values
  ('f2000000-0000-4000-8000-000000000001', 'PI futura', current_date + 30)
on conflict do nothing;
insert into public.prova_distancias (id, prova_id, rotulo) values
  ('a2000000-0000-4000-8000-000000000001', 'f2000000-0000-4000-8000-000000000001', '10k')
on conflict do nothing;

do $$
begin
  perform set_config('request.jwt.claim.sub', 'e2000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  insert into public.prova_participantes (prova_id, atleta_id, distancia_id)
    values ('f2000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001');
  assert (select count(*) from public.prova_participantes) = 1, 'p1: insert simples';
  delete from public.prova_participantes where atleta_id = 'e2000000-0000-4000-8000-000000000001';
  assert (select count(*) from public.prova_participantes) = 0, 'p2: sair';
  insert into public.prova_participantes (prova_id, atleta_id, distancia_id)
    values ('f2000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001');
  begin
    insert into public.prova_participantes (prova_id, atleta_id, distancia_id)
      values ('f2000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001')
      on conflict (prova_id, atleta_id) do update
      set prova_id = excluded.prova_id, atleta_id = excluded.atleta_id, distancia_id = excluded.distancia_id;
    assert false, 'p3: upsert deveria falhar';
  exception when insufficient_privilege then null;
  end;
  reset role;
end $$;
