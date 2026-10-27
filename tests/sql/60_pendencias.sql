-- Pendências finais: correção de emissão sem mudança e permissões da tabela avisos.
do $$
declare antes int; depois int; dt date;
begin
  select emitido_em into dt from public.renovacoes where id = 'b0000000-0000-4000-8000-000000000002';
  assert dt is not null, 'a: fixture da renovação (10_renovacoes.sql)';
  select count(*) into antes from public.renovacao_emissao_historico
    where renovacao_id = 'b0000000-0000-4000-8000-000000000002';

  -- mesma data: não registra histórico nem altera nada
  perform set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  perform public.editar_emissao_renovacao('b0000000-0000-4000-8000-000000000002', dt);
  reset role;
  select count(*) into depois from public.renovacao_emissao_historico
    where renovacao_id = 'b0000000-0000-4000-8000-000000000002';
  assert depois = antes, 'a: mesma data não deve gerar histórico (' || antes || ' -> ' || depois || ')';
  assert (select emitido_em from public.renovacoes where id = 'b0000000-0000-4000-8000-000000000002') = dt, 'a: data intacta';

  -- data diferente continua registrando
  perform set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  perform public.editar_emissao_renovacao('b0000000-0000-4000-8000-000000000002', dt - 1);
  reset role;
  select count(*) into depois from public.renovacao_emissao_historico
    where renovacao_id = 'b0000000-0000-4000-8000-000000000002';
  assert depois = antes + 1, 'b: data diferente registra histórico';

  -- avisos: authenticated só lê e marca como lido; sem TRUNCATE/INSERT/DELETE
  assert has_table_privilege('authenticated', 'public.avisos', 'SELECT'), 'c: select';
  assert not has_table_privilege('authenticated', 'public.avisos', 'TRUNCATE'), 'c: truncate';
  assert not has_table_privilege('authenticated', 'public.avisos', 'INSERT'), 'c: insert';
  assert not has_table_privilege('authenticated', 'public.avisos', 'DELETE'), 'c: delete';
  assert has_column_privilege('authenticated', 'public.avisos', 'lido_em', 'UPDATE'), 'c: lido_em';
  assert not has_column_privilege('authenticated', 'public.avisos', 'texto', 'UPDATE'), 'c: texto';
end $$;
