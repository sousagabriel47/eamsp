-- migracao_v3.sql — dashboard financeiro, pagamento em lote e função patrocinador.
-- Rode depois da migracao_v2.sql. Idempotente.

-- V3.1) FUNÇÃO PATROCINADOR ---------------------------------------------------------------
-- Novo valor de papel: só enxerga o próprio perfil (nenhuma política existente o libera)
alter table public.perfis drop constraint if exists perfis_papel_check;
alter table public.perfis add constraint perfis_papel_check
  check (papel in ('atleta', 'gestao', 'admin', 'patrocinador'));

create or replace function public.is_patrocinador() returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.perfis
    where id = (select auth.uid()) and papel = 'patrocinador' and status = 'ativo');
$$;
revoke execute on function public.is_patrocinador() from public, anon;
grant execute on function public.is_patrocinador() to authenticated;

-- Mesmas regras de antes; a marca atleta só sobe ao virar "atleta" (patrocinador não a altera)
create or replace function public.definir_papel(alvo uuid, novo text) returns void
language plpgsql security definer set search_path = ''
as $$
declare atual text;
begin
  if not public.is_admin() then
    raise exception 'Somente o administrador pode atribuir funções.';
  end if;
  if novo not in ('atleta', 'gestao', 'admin', 'patrocinador') then
    raise exception 'Função inválida.';
  end if;
  select papel into atual from public.perfis where id = alvo for update;
  if atual is null then
    raise exception 'Usuário não encontrado.';
  end if;
  if atual = novo then
    return;
  end if;
  if atual = 'admin' and (select count(*) from public.perfis where papel = 'admin') <= 1 then
    raise exception 'Mantenha pelo menos um administrador.';
  end if;
  update public.perfis set papel = novo, atleta = (atleta or novo = 'atleta') where id = alvo;
  insert into public.papel_historico (alvo, papel_anterior, papel_novo, alterado_por)
  values (alvo, atual, novo, (select auth.uid()));
end;
$$;
revoke execute on function public.definir_papel(uuid, text) from public, anon;
grant execute on function public.definir_papel(uuid, text) to authenticated;
