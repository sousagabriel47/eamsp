-- V3.1: função "patrocinador"
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('70000000-0000-4000-8000-000000000001', 'padm@t.com', '{"nome":"Admin P"}'),
  ('70000000-0000-4000-8000-000000000002', 'pges@t.com', '{"nome":"Gestor P"}'),
  ('70000000-0000-4000-8000-000000000003', 'pat@t.com', '{"nome":"Atleta P"}'),
  ('70000000-0000-4000-8000-000000000004', 'ppat@t.com', '{"nome":"Patrocinador P"}'),
  ('70000000-0000-4000-8000-000000000005', 'pina@t.com', '{"nome":"Patrocinador Inativo"}')
on conflict do nothing;
-- este arquivo roda por último: o admin de teste é o único admin
update public.perfis set papel = 'gestao' where papel = 'admin';
update public.perfis set papel = 'admin' where id = '70000000-0000-4000-8000-000000000001';
update public.perfis set papel = 'gestao' where id = '70000000-0000-4000-8000-000000000002';
update public.perfis set atleta = true where id = '70000000-0000-4000-8000-000000000003';
update public.perfis set atleta = true where id = '70000000-0000-4000-8000-000000000004';
update public.perfis set atleta = false where id = '70000000-0000-4000-8000-000000000005';

-- (a) admin define patrocinador; marca atleta preservada; histórico registrado
do $$
begin
  perform set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  perform public.definir_papel('70000000-0000-4000-8000-000000000004', 'patrocinador');
  perform public.definir_papel('70000000-0000-4000-8000-000000000005', 'patrocinador');
  reset role;
  assert (select papel from public.perfis where id = '70000000-0000-4000-8000-000000000004') = 'patrocinador', 'a1';
  assert (select atleta from public.perfis where id = '70000000-0000-4000-8000-000000000004') = true, 'a2: atleta preservado';
  assert (select atleta from public.perfis where id = '70000000-0000-4000-8000-000000000005') = false, 'a3: atleta continua falso';
  assert (select count(*) from public.papel_historico
          where alvo = '70000000-0000-4000-8000-000000000004'
            and papel_anterior = 'atleta' and papel_novo = 'patrocinador'
            and alterado_por = '70000000-0000-4000-8000-000000000001') = 1, 'a4';
end $$;

-- (b) gestão e atleta não atribuem funções
do $$
declare msg text; u text;
begin
  foreach u in array array['70000000-0000-4000-8000-000000000002', '70000000-0000-4000-8000-000000000003'] loop
    perform set_config('request.jwt.claim.sub', u, true);
    set local role authenticated;
    begin
      perform public.definir_papel('70000000-0000-4000-8000-000000000003', 'patrocinador');
      reset role;
      assert false, 'b: deveria falhar para ' || u;
    exception when raise_exception then
      reset role;
      get stacked diagnostics msg = message_text;
      assert msg = 'Somente o administrador pode atribuir funções.', 'b: ' || msg;
    end;
  end loop;
end $$;

-- (c) papel inválido
do $$
declare msg text;
begin
  perform set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  begin
    perform public.definir_papel('70000000-0000-4000-8000-000000000003', 'xpto');
    reset role;
    assert false, 'c: deveria falhar';
  exception when raise_exception then
    reset role;
    get stacked diagnostics msg = message_text;
    assert msg = 'Função inválida.', 'c: ' || msg;
  end;
end $$;

-- (d) is_patrocinador: só patrocinador ativo
update public.perfis set status = 'inativo' where id = '70000000-0000-4000-8000-000000000005';
do $$
declare u text; esperado boolean;
begin
  foreach u in array array[
    '70000000-0000-4000-8000-000000000004', '70000000-0000-4000-8000-000000000005',
    '70000000-0000-4000-8000-000000000003', '70000000-0000-4000-8000-000000000002'] loop
    esperado := (u = '70000000-0000-4000-8000-000000000004');
    perform set_config('request.jwt.claim.sub', u, true);
    set local role authenticated;
    assert public.is_patrocinador() is not distinct from esperado, 'd: ' || u;
    reset role;
  end loop;
end $$;

-- (e) patrocinador não enxerga reembolsos, renovações nem outros perfis
insert into public.reembolsos (id, atleta_id, descricao, valor) values
  ('70000000-0000-4000-8000-0000000000a1', '70000000-0000-4000-8000-000000000003', 'x', 10);
insert into public.renovacoes (id, atleta_id, tipo, nova_validade) values
  ('70000000-0000-4000-8000-0000000000b1', '70000000-0000-4000-8000-000000000003', 'anuidade', current_date + 365);
do $$
begin
  assert (select count(*) from public.reembolsos) >= 1, 'e0';
  perform set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-000000000004', true);
  set local role authenticated;
  assert (select count(*) from public.reembolsos) = 0, 'e1';
  assert (select count(*) from public.renovacoes) = 0, 'e2';
  assert (select count(*) from public.perfis where id <> '70000000-0000-4000-8000-000000000004') = 0, 'e3';
  assert (select count(*) from public.perfis) = 1, 'e4';
  reset role;
end $$;

-- (f) último admin não pode ser rebaixado
do $$
declare msg text;
begin
  perform set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  begin
    perform public.definir_papel('70000000-0000-4000-8000-000000000001', 'patrocinador');
    reset role;
    assert false, 'f: deveria falhar';
  exception when raise_exception then
    reset role;
    get stacked diagnostics msg = message_text;
    assert msg = 'Mantenha pelo menos um administrador.', 'f: ' || msg;
  end;
end $$;

rollback;
