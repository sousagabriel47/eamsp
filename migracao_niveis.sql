-- EAMSP · Três níveis de acesso: atleta, gestao e admin
-- Quem já rodou o schema.sql: rode SOMENTE este arquivo (SQL Editor > Run).
-- Instalação nova: o schema.sql já inclui tudo isto.
--   atleta : vê e edita os próprios dados e faz solicitações
--   gestao : tudo do atleta + cadastra provas e valida renovações e reembolsos
--   admin  : tudo da gestão + atribui as funções aos usuários cadastrados

-- 1) Novo valor de papel e e-mail no perfil (para o admin localizar as pessoas) ----
alter table public.perfis drop constraint if exists perfis_papel_check;
alter table public.perfis add constraint perfis_papel_check
  check (papel in ('atleta', 'gestao', 'admin'));

alter table public.perfis add column if not exists email text;
update public.perfis p set email = u.email from auth.users u where u.id = p.id and p.email is null;

create or replace function public.criar_perfil() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.perfis (id, nome, email)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'nome', ''), new.email);
  return new;
end;
$$;

-- 2) Funções de apoio: o admin também tem os poderes da gestão -----------------------
create or replace function public.is_gestao() returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.perfis
    where id = (select auth.uid()) and papel in ('gestao', 'admin')
  );
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.perfis
    where id = (select auth.uid()) and papel = 'admin'
  );
$$;

-- 3) Atribuição de funções: só o admin, só por esta função, com registro ----------------
create table if not exists public.papel_historico (
  id             bigint generated always as identity primary key,
  alvo           uuid not null references public.perfis (id) on delete cascade,
  papel_anterior text,
  papel_novo     text not null,
  alterado_por   uuid,
  alterado_em    timestamptz not null default now()
);
revoke all on public.papel_historico from anon;
alter table public.papel_historico enable row level security;
create policy papel_historico_admin on public.papel_historico for select to authenticated
  using (public.is_admin());

create or replace function public.definir_papel(alvo uuid, novo text) returns void
language plpgsql security definer set search_path = ''
as $$
declare atual text;
begin
  if not public.is_admin() then
    raise exception 'Somente o administrador pode atribuir funções.';
  end if;
  if novo not in ('atleta', 'gestao', 'admin') then
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
  update public.perfis set papel = novo where id = alvo;
  insert into public.papel_historico (alvo, papel_anterior, papel_novo, alterado_por)
  values (alvo, atual, novo, (select auth.uid()));
end;
$$;
revoke execute on function public.definir_papel(uuid, text) from public, anon;
grant execute on function public.definir_papel(uuid, text) to authenticated;

-- 4) Primeiro administrador (rode uma vez, trocando o e-mail) ------------------------------
-- update public.perfis set papel = 'admin'
-- where id = (select id from auth.users where email = 'admin@exemplo.com');

-- 5) TESTES (antes do piloto) ----------------------------------------------------------------
--  - Atleta e gestão chamam definir_papel e recebem erro; nenhum deles altera o próprio papel;
--  - Admin muda um atleta para gestão: a pessoa passa a ver a aba de gestão após entrar de novo;
--  - Rebaixar o único admin é bloqueado;
--  - Gestão continua sem ver a aba Usuários.
