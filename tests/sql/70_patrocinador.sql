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

-- (g) patrocinador só lê o calendário (provas, prova_distancias), igual a todo usuário ativo
insert into public.provas (id, nome, data) values
  ('70000000-0000-4000-8000-0000000000c1', 'Prova Patrocínio', current_date + 30);
insert into public.prova_distancias (id, prova_id, rotulo) values
  ('70000000-0000-4000-8000-0000000000d1', '70000000-0000-4000-8000-0000000000c1', '10 km');
insert into public.prova_participantes (prova_id, atleta_id, distancia_id) values
  ('70000000-0000-4000-8000-0000000000c1', '70000000-0000-4000-8000-000000000003', '70000000-0000-4000-8000-0000000000d1');
insert into public.avisos (usuario_id, tipo, texto) values
  ('70000000-0000-4000-8000-000000000003', 'teste', 'aviso de outro');
insert into public.reembolso_historico (reembolso_id, status_anterior, status_novo) values
  ('70000000-0000-4000-8000-0000000000a1', 'pendente', 'aprovado');
insert into public.renovacao_emissao_historico (renovacao_id, anterior, novo) values
  ('70000000-0000-4000-8000-0000000000b1', null, current_date);
do $$
declare n int;
begin
  assert (select count(*) from public.provas) >= 1, 'g0';
  perform set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-000000000004', true);
  set local role authenticated;
  assert (select count(*) from public.provas where id = '70000000-0000-4000-8000-0000000000c1') = 1, 'g1';
  assert (select count(*) from public.prova_distancias where prova_id = '70000000-0000-4000-8000-0000000000c1') = 1, 'g2';
  assert (select count(*) from public.reembolso_historico) = 0, 'g3';
  assert (select count(*) from public.avisos) = 0, 'g4';
  assert (select count(*) from public.renovacao_emissao_historico) = 0, 'g5';
  assert (select count(*) from public.prova_participantes) = 0, 'g6';
  -- não altera o calendário
  begin
    insert into public.provas (nome, data) values ('invasora', current_date + 5);
    assert false, 'g7: insert deveria falhar';
  exception when insufficient_privilege then null;
  end;
  -- sem privilégio de tabela ou sem política: nada muda
  begin
    update public.provas set nome = 'hackeada' where id = '70000000-0000-4000-8000-0000000000c1';
    get diagnostics n = row_count;
    assert n = 0, 'g8: update afetou linhas';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from public.provas where id = '70000000-0000-4000-8000-0000000000c1';
    get diagnostics n = row_count;
    assert n = 0, 'g9: delete afetou linhas';
  exception when insufficient_privilege then null;
  end;
  reset role;
  assert (select nome from public.provas where id = '70000000-0000-4000-8000-0000000000c1') = 'Prova Patrocínio', 'g10';
end $$;

-- (h) alvo inexistente e papel igual ao atual (sem novo registro no histórico)
do $$
declare msg text; antes int;
begin
  perform set_config('request.jwt.claim.sub', '70000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  begin
    perform public.definir_papel('70000000-0000-4000-8000-0000000000ff', 'patrocinador');
    reset role;
    assert false, 'h1: deveria falhar';
  exception when raise_exception then
    reset role;
    get stacked diagnostics msg = message_text;
    assert msg = 'Usuário não encontrado.', 'h1: ' || msg;
  end;
  select count(*) into antes from public.papel_historico where alvo = '70000000-0000-4000-8000-000000000004';
  set local role authenticated;
  perform public.definir_papel('70000000-0000-4000-8000-000000000004', 'patrocinador');
  reset role;
  assert (select count(*) from public.papel_historico where alvo = '70000000-0000-4000-8000-000000000004') = antes, 'h2';
  assert (select papel from public.perfis where id = '70000000-0000-4000-8000-000000000004') = 'patrocinador', 'h3';
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
