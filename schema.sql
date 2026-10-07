-- EAMSP · MVP · Esquema do banco e regras de segurança (Supabase / PostgreSQL)
-- Como usar: Supabase > SQL Editor > cole tudo > Run. Teste primeiro num projeto de teste.

-- 1) TABELAS -----------------------------------------------------------------

create table public.perfis (
  id                uuid primary key references auth.users (id) on delete cascade,
  nome              text not null default '',
  papel             text not null default 'atleta' check (papel in ('atleta', 'gestao')),
  atestado_validade date,
  anuidade_ate      date,
  criado_em         timestamptz not null default now()
);

create table public.provas (
  id             uuid primary key default gen_random_uuid(),
  nome           text not null,
  data           date not null,
  local          text,
  distancia      text,
  inscricao_ate  date,
  criado_em      timestamptz not null default now()
);

create table public.reembolsos (
  id            uuid primary key default gen_random_uuid(),
  atleta_id     uuid not null references public.perfis (id) on delete cascade,
  prova_id      uuid references public.provas (id) on delete set null,
  descricao     text not null,
  valor         numeric(10, 2) not null check (valor > 0),
  status        text not null default 'pendente'
                check (status in ('pendente', 'aprovado', 'pago', 'recusado', 'cancelado')),
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index on public.reembolsos (atleta_id);
create index on public.reembolsos (status);

-- Registro de quem mudou o status de cada reembolso
create table public.reembolso_historico (
  id              bigint generated always as identity primary key,
  reembolso_id    uuid not null references public.reembolsos (id) on delete cascade,
  status_anterior text,
  status_novo     text not null,
  alterado_por    uuid,
  alterado_em     timestamptz not null default now()
);

-- 2) FUNÇÕES E GATILHOS ------------------------------------------------------

-- Diz se quem está logado é da gestão
create function public.is_gestao() returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.perfis
    where id = (select auth.uid()) and papel = 'gestao'
  );
$$;

-- Cria o perfil automaticamente quando alguém se cadastra (nome vem do cadastro)
create function public.criar_perfil() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.perfis (id, nome)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'nome', ''));
  return new;
end;
$$;
create trigger ao_criar_usuario after insert on auth.users
  for each row execute function public.criar_perfil();

-- Atualiza a data e grava o histórico quando o status muda
create function public.registrar_mudanca_reembolso() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  new.atualizado_em := now();
  if new.status is distinct from old.status then
    insert into public.reembolso_historico (reembolso_id, status_anterior, status_novo, alterado_por)
    values (new.id, old.status, new.status, (select auth.uid()));
  end if;
  return new;
end;
$$;
create trigger ao_mudar_reembolso before update on public.reembolsos
  for each row execute function public.registrar_mudanca_reembolso();

-- 3) PERMISSÕES (o que cada papel pode escrever, coluna por coluna) ----------

revoke all on all tables in schema public from anon;

-- Atleta só edita o nome; as validades mudam só por renovação validada pela gestão
revoke update on public.perfis from authenticated;
grant update (nome) on public.perfis to authenticated;

-- Em reembolso, só o status muda depois de criado (valor e descrição ficam travados)
revoke update on public.reembolsos from authenticated;
grant update (status) on public.reembolsos to authenticated;

-- 4) SEGURANÇA POR LINHA (RLS) -----------------------------------------------

alter table public.perfis              enable row level security;
alter table public.provas              enable row level security;
alter table public.reembolsos          enable row level security;
alter table public.reembolso_historico enable row level security;

-- perfis: cada um vê e edita o próprio; a gestão vê todos
create policy perfis_ver on public.perfis for select to authenticated
  using (id = (select auth.uid()) or public.is_gestao());
create policy perfis_editar_proprio on public.perfis for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- provas: todos os logados veem; só a gestão cadastra, altera e apaga
create policy provas_ver on public.provas for select to authenticated using (true);
create policy provas_gestao_inserir on public.provas for insert to authenticated
  with check (public.is_gestao());
create policy provas_gestao_alterar on public.provas for update to authenticated
  using (public.is_gestao()) with check (public.is_gestao());
create policy provas_gestao_apagar on public.provas for delete to authenticated
  using (public.is_gestao());

-- reembolsos: atleta vê e cria os próprios (sempre como pendente)
create policy reembolsos_ver on public.reembolsos for select to authenticated
  using (atleta_id = (select auth.uid()) or public.is_gestao());
create policy reembolsos_criar on public.reembolsos for insert to authenticated
  with check (atleta_id = (select auth.uid()) and status = 'pendente');
-- atleta só cancela pedido próprio que ainda está pendente
create policy reembolsos_atleta_cancelar on public.reembolsos for update to authenticated
  using (atleta_id = (select auth.uid()) and status = 'pendente')
  with check (atleta_id = (select auth.uid()) and status = 'cancelado');
-- gestão aprova, recusa e marca como pago
create policy reembolsos_gestao_status on public.reembolsos for update to authenticated
  using (public.is_gestao()) with check (public.is_gestao());

-- histórico: só a gestão consulta (quem grava é o gatilho)
create policy historico_gestao on public.reembolso_historico for select to authenticated
  using (public.is_gestao());

-- 4B) VALIDAÇÃO PELA GESTÃO · RENOVAÇÕES: o atleta pede, a gestão valida ---------------------------------

create table public.renovacoes (
  id             uuid primary key default gen_random_uuid(),
  atleta_id      uuid not null references public.perfis (id) on delete cascade,
  tipo           text not null check (tipo in ('atestado', 'anuidade')),
  nova_validade  date not null,
  status         text not null default 'pendente'
                 check (status in ('pendente', 'aprovada', 'recusada', 'cancelada')),
  motivo_decisao text,
  decidido_por   uuid,
  decidido_em    timestamptz,
  criado_em      timestamptz not null default now()
);
create index on public.renovacoes (atleta_id);
create index on public.renovacoes (status);
-- só uma solicitação pendente por atleta e tipo
create unique index renovacao_pendente_unica on public.renovacoes (atleta_id, tipo)
  where status = 'pendente';

-- Regras na criação: validade futura e no máximo 2 anos à frente
create function public.validar_renovacao_nova() returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.nova_validade <= current_date or new.nova_validade > current_date + interval '2 years' then
    raise exception 'Informe uma validade futura, de até 2 anos.';
  end if;
  return new;
end;
$$;
create trigger ao_criar_renovacao before insert on public.renovacoes
  for each row execute function public.validar_renovacao_nova();

-- Decisão: só a gestão aprova ou recusa; ao aprovar, a validade do perfil é atualizada
create function public.decidir_renovacao() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if old.status <> 'pendente' then
    raise exception 'Esta solicitação já foi decidida.';
  end if;
  if new.status = 'cancelada' then
    if new.atleta_id <> (select auth.uid()) then
      raise exception 'Somente o próprio atleta pode cancelar.';
    end if;
  elsif new.status in ('aprovada', 'recusada') then
    if not public.is_gestao() then
      raise exception 'Somente a gestão pode validar.';
    end if;
    if new.status = 'recusada' and coalesce(btrim(new.motivo_decisao), '') = '' then
      raise exception 'Informe o motivo da recusa.';
    end if;
    new.decidido_por := (select auth.uid());
    new.decidido_em  := now();
    if new.status = 'aprovada' then
      if new.tipo = 'atestado' then
        update public.perfis set atestado_validade = new.nova_validade where id = new.atleta_id;
      else
        update public.perfis set anuidade_ate = new.nova_validade where id = new.atleta_id;
      end if;
    end if;
  else
    raise exception 'Mudança de status inválida.';
  end if;
  return new;
end;
$$;
create trigger ao_decidir_renovacao before update on public.renovacoes
  for each row execute function public.decidir_renovacao();

revoke all on public.renovacoes from anon;
revoke update on public.renovacoes from authenticated;
grant update (status, motivo_decisao) on public.renovacoes to authenticated;

alter table public.renovacoes enable row level security;
create policy renovacoes_ver on public.renovacoes for select to authenticated
  using (atleta_id = (select auth.uid()) or public.is_gestao());
create policy renovacoes_criar on public.renovacoes for insert to authenticated
  with check (atleta_id = (select auth.uid()) and status = 'pendente'
              and motivo_decisao is null and decidido_por is null and decidido_em is null);
create policy renovacoes_atleta_cancelar on public.renovacoes for update to authenticated
  using (atleta_id = (select auth.uid()) and status = 'pendente')
  with check (atleta_id = (select auth.uid()) and status = 'cancelada');
create policy renovacoes_gestao_decidir on public.renovacoes for update to authenticated
  using (public.is_gestao() and status = 'pendente') with check (public.is_gestao());

-- 4C) PERFIL: o atleta deixa de editar as validades diretamente (só o nome) -------

revoke update on public.perfis from authenticated;
grant update (nome) on public.perfis to authenticated;

-- 4D) REEMBOLSOS: decisão só pela gestão, com fluxo de estados e motivo de recusa -

alter table public.reembolsos
  add column if not exists motivo_decisao text,
  add column if not exists decidido_por uuid,
  add column if not exists decidido_em timestamptz;

revoke update on public.reembolsos from authenticated;
grant update (status, motivo_decisao) on public.reembolsos to authenticated;

create or replace function public.registrar_mudanca_reembolso() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  new.atualizado_em := now();
  if new.status is distinct from old.status then
    if not ((old.status = 'pendente' and new.status in ('aprovado', 'recusado', 'cancelado'))
         or (old.status = 'aprovado' and new.status = 'pago')) then
      raise exception 'Mudança de status não permitida: % para %', old.status, new.status;
    end if;
    if new.status in ('aprovado', 'recusado', 'pago') then
      if not public.is_gestao() then
        raise exception 'Somente a gestão pode validar reembolsos.';
      end if;
      if new.status = 'recusado' and coalesce(btrim(new.motivo_decisao), '') = '' then
        raise exception 'Informe o motivo da recusa.';
      end if;
      new.decidido_por := (select auth.uid());
      new.decidido_em  := now();
    end if;
    insert into public.reembolso_historico (reembolso_id, status_anterior, status_novo, alterado_por)
    values (new.id, old.status, new.status, (select auth.uid()));
  elsif new.motivo_decisao is distinct from old.motivo_decisao then
    raise exception 'O motivo só pode ser informado junto com a decisão.';
  end if;
  return new;
end;
$$;


-- 4E) NÍVEIS DE ACESSO · atleta, gestao e admin
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


-- 4F) GESTÃO/ADMIN QUE TAMBÉM SÃO ATLETAS
-- 1) Marca de atleta no perfil ---------------------------------------------------------
alter table public.perfis add column if not exists atleta boolean not null default true;

create or replace function public.is_atleta() returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.perfis
    where id = (select auth.uid()) and atleta
  );
$$;

-- Só o admin altera a marca (o atleta continua podendo editar só o nome)
create or replace function public.definir_atleta(alvo uuid, valor boolean) returns void
language plpgsql security definer set search_path = ''
as $$
declare p text;
begin
  if not public.is_admin() then
    raise exception 'Somente o administrador pode alterar esta marcação.';
  end if;
  select papel into p from public.perfis where id = alvo;
  if p is null then
    raise exception 'Usuário não encontrado.';
  end if;
  if p = 'atleta' and not valor then
    raise exception 'Quem tem a função Atleta é sempre atleta.';
  end if;
  update public.perfis set atleta = valor where id = alvo;
end;
$$;
revoke execute on function public.definir_atleta(uuid, boolean) from public, anon;
grant execute on function public.definir_atleta(uuid, boolean) to authenticated;

-- Ao virar "atleta" como função, a marca volta a ser verdadeira
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
  update public.perfis set papel = novo, atleta = (atleta or novo = 'atleta') where id = alvo;
  insert into public.papel_historico (alvo, papel_anterior, papel_novo, alterado_por)
  values (alvo, atual, novo, (select auth.uid()));
end;
$$;

-- 2) Só quem é atleta cria renovações e reembolsos -------------------------------------
drop policy if exists reembolsos_criar on public.reembolsos;
create policy reembolsos_criar on public.reembolsos for insert to authenticated
  with check (atleta_id = (select auth.uid()) and status = 'pendente' and public.is_atleta());

drop policy if exists renovacoes_criar on public.renovacoes;
create policy renovacoes_criar on public.renovacoes for insert to authenticated
  with check (atleta_id = (select auth.uid()) and status = 'pendente' and public.is_atleta()
              and motivo_decisao is null and decidido_por is null and decidido_em is null);

-- 3) Ninguém valida a própria solicitação (outro gestor ou admin precisa decidir) -------
create or replace function public.decidir_renovacao() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if old.status <> 'pendente' then
    raise exception 'Esta solicitação já foi decidida.';
  end if;
  if new.status = 'cancelada' then
    if new.atleta_id <> (select auth.uid()) then
      raise exception 'Somente o próprio atleta pode cancelar.';
    end if;
  elsif new.status in ('aprovada', 'recusada') then
    if not public.is_gestao() then
      raise exception 'Somente a gestão pode validar.';
    end if;
    if new.atleta_id = (select auth.uid()) then
      raise exception 'Você não pode validar a sua própria solicitação. Peça a outro gestor.';
    end if;
    if new.status = 'recusada' and coalesce(btrim(new.motivo_decisao), '') = '' then
      raise exception 'Informe o motivo da recusa.';
    end if;
    new.decidido_por := (select auth.uid());
    new.decidido_em  := now();
    if new.status = 'aprovada' then
      if new.tipo = 'atestado' then
        update public.perfis set atestado_validade = new.nova_validade where id = new.atleta_id;
      else
        update public.perfis set anuidade_ate = new.nova_validade where id = new.atleta_id;
      end if;
    end if;
  else
    raise exception 'Mudança de status inválida.';
  end if;
  return new;
end;
$$;

create or replace function public.registrar_mudanca_reembolso() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  new.atualizado_em := now();
  if new.status is distinct from old.status then
    if not ((old.status = 'pendente' and new.status in ('aprovado', 'recusado', 'cancelado'))
         or (old.status = 'aprovado' and new.status = 'pago')) then
      raise exception 'Mudança de status não permitida: % para %', old.status, new.status;
    end if;
    if new.status in ('aprovado', 'recusado', 'pago') then
      if not public.is_gestao() then
        raise exception 'Somente a gestão pode validar reembolsos.';
      end if;
      if new.atleta_id = (select auth.uid()) then
        raise exception 'Você não pode validar o seu próprio reembolso. Peça a outro gestor.';
      end if;
      if new.status = 'recusado' and coalesce(btrim(new.motivo_decisao), '') = '' then
        raise exception 'Informe o motivo da recusa.';
      end if;
      new.decidido_por := (select auth.uid());
      new.decidido_em  := now();
    end if;
    insert into public.reembolso_historico (reembolso_id, status_anterior, status_novo, alterado_por)
    values (new.id, old.status, new.status, (select auth.uid()));
  elsif new.motivo_decisao is distinct from old.motivo_decisao then
    raise exception 'O motivo só pode ser informado junto com a decisão.';
  end if;
  return new;
end;
$$;


-- 4G) LINK DE INSCRIÇÃO NAS PROVAS
alter table public.provas add column if not exists link_inscricao text;
alter table public.provas drop constraint if exists provas_link_inscricao_check;
alter table public.provas add constraint provas_link_inscricao_check
  check (link_inscricao is null or link_inscricao ~* '^https?://[^[:space:]]+$');

-- 4H) ANEXOS EM PDF
-- 1) Bucket privado: só PDF, até 5 MB (o servidor recusa outros tipos e tamanhos) --------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('anexos', 'anexos', false, 5242880, array['application/pdf'])
on conflict (id) do update
  set public = false, file_size_limit = 5242880, allowed_mime_types = array['application/pdf'];

-- 2) Caminho do arquivo no pedido (sempre dentro da pasta do próprio atleta) -------------
alter table public.renovacoes add column if not exists anexo_path text;
alter table public.reembolsos add column if not exists anexo_path text;

alter table public.renovacoes drop constraint if exists renovacoes_anexo_check;
alter table public.renovacoes add constraint renovacoes_anexo_check
  check (anexo_path is null or anexo_path ~ ('^' || atleta_id::text || '/[0-9a-f-]{36}\.pdf$'));
alter table public.reembolsos drop constraint if exists reembolsos_anexo_check;
alter table public.reembolsos add constraint reembolsos_anexo_check
  check (anexo_path is null or anexo_path ~ ('^' || atleta_id::text || '/[0-9a-f-]{36}\.pdf$'));

-- 3) Quem pode enviar, ver e apagar arquivos --------------------------------------------
-- enviar: só atleta, só na própria pasta (pasta = id do usuário)
drop policy if exists anexos_enviar on storage.objects;
create policy anexos_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'anexos' and public.is_atleta()
              and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ver: o dono e a gestão/admin
drop policy if exists anexos_ver on storage.objects;
create policy anexos_ver on storage.objects for select to authenticated
  using (bucket_id = 'anexos'
         and ((storage.foldername(name))[1] = (select auth.uid())::text or public.is_gestao()));

-- apagar: só o dono (usado para desfazer um envio quando o pedido falha)
drop policy if exists anexos_apagar on storage.objects;
create policy anexos_apagar on storage.objects for delete to authenticated
  using (bucket_id = 'anexos' and (storage.foldername(name))[1] = (select auth.uid())::text);


-- 4I) DADOS CADASTRAIS DO ATLETA
-- 1) Colunas -------------------------------------------------------------------------
alter table public.perfis
  add column if not exists cpf text,              -- somente os 11 dígitos
  add column if not exists telefone text,         -- somente dígitos, com DDD (10 ou 11)
  add column if not exists data_nascimento date,
  add column if not exists data_adesao date;      -- quando entrou na equipe (definida pela gestão)

-- 2) Validação do CPF (dígitos verificadores) e formatos ------------------------------
create or replace function public.cpf_valido(c text) returns boolean
language plpgsql immutable set search_path = ''
as $$
declare s int; i int; d1 int; d2 int;
begin
  if c is null or c !~ '^[0-9]{11}$' or c ~ '^(.)\1{10}$' then return false; end if;
  s := 0;
  for i in 1..9 loop s := s + substr(c, i, 1)::int * (11 - i); end loop;
  d1 := (s * 10) % 11; if d1 = 10 then d1 := 0; end if;
  if d1 <> substr(c, 10, 1)::int then return false; end if;
  s := 0;
  for i in 1..10 loop s := s + substr(c, i, 1)::int * (12 - i); end loop;
  d2 := (s * 10) % 11; if d2 = 10 then d2 := 0; end if;
  return d2 = substr(c, 11, 1)::int;
end;
$$;

alter table public.perfis drop constraint if exists perfis_cpf_check;
alter table public.perfis add constraint perfis_cpf_check
  check (cpf is null or public.cpf_valido(cpf));
alter table public.perfis drop constraint if exists perfis_telefone_check;
alter table public.perfis add constraint perfis_telefone_check
  check (telefone is null or telefone ~ '^[0-9]{10,11}$');
create unique index if not exists perfis_cpf_unico on public.perfis (cpf) where cpf is not null;

-- 3) Regras de datas e quem define a adesão --------------------------------------------
create or replace function public.validar_cadastro() returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.data_nascimento is not null
     and (new.data_nascimento >= current_date or new.data_nascimento < date '1900-01-01') then
    raise exception 'Data de nascimento inválida.';
  end if;
  if new.data_adesao is not null then
    if new.data_adesao > current_date or new.data_adesao < date '1950-01-01' then
      raise exception 'Data de adesão inválida (não pode ser futura).';
    end if;
    if new.data_nascimento is not null and new.data_adesao < new.data_nascimento then
      raise exception 'A adesão não pode ser anterior ao nascimento.';
    end if;
  end if;
  -- só a gestão altera a adesão (SQL Editor e funções de servidor não têm auth.uid())
  if tg_op = 'UPDATE' and new.data_adesao is distinct from old.data_adesao
     and (select auth.uid()) is not null and not public.is_gestao() then
    raise exception 'A data de adesão é definida pela gestão.';
  end if;
  return new;
end;
$$;
drop trigger if exists ao_validar_cadastro on public.perfis;
create trigger ao_validar_cadastro before insert or update on public.perfis
  for each row execute function public.validar_cadastro();

-- 4) Quem edita o quê ---------------------------------------------------------------------
-- Colunas liberadas para edição (papel, marca de atleta e validades continuam protegidas)
revoke update on public.perfis from authenticated;
grant update (nome, cpf, telefone, data_nascimento, data_adesao) on public.perfis to authenticated;

-- A gestão pode corrigir o cadastro de qualquer atleta (o atleta edita só o próprio: política já existente)
drop policy if exists perfis_gestao_editar on public.perfis;
create policy perfis_gestao_editar on public.perfis for update to authenticated
  using (public.is_gestao()) with check (public.is_gestao());


-- 4J) STATUS DO PERFIL, BLOQUEIO POR SENHA E REDEFINIÇÃO COM APROVAÇÃO
-- 1) Status do perfil: ativo, inativo ou bloqueado (só o admin altera) -------------------
alter table public.perfis add column if not exists status text not null default 'ativo';
alter table public.perfis drop constraint if exists perfis_status_check;
alter table public.perfis add constraint perfis_status_check
  check (status in ('ativo', 'inativo', 'bloqueado'));

create table if not exists public.status_historico (
  id              bigint generated always as identity primary key,
  alvo            uuid not null references public.perfis (id) on delete cascade,
  status_anterior text,
  status_novo     text not null,
  motivo          text,
  alterado_por    uuid,                -- nulo quando o sistema bloqueia sozinho
  alterado_em     timestamptz not null default now()
);
revoke all on public.status_historico from anon;
alter table public.status_historico enable row level security;
drop policy if exists status_historico_admin on public.status_historico;
create policy status_historico_admin on public.status_historico for select to authenticated
  using (public.is_admin());

-- Só perfil ATIVO tem permissões: as funções de apoio passam a exigir status = 'ativo'
create or replace function public.is_ativo() returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.perfis where id = (select auth.uid()) and status = 'ativo');
$$;
create or replace function public.is_gestao() returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.perfis
    where id = (select auth.uid()) and papel in ('gestao', 'admin') and status = 'ativo');
$$;
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.perfis
    where id = (select auth.uid()) and papel = 'admin' and status = 'ativo');
$$;
create or replace function public.is_atleta() returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.perfis
    where id = (select auth.uid()) and atleta and status = 'ativo');
$$;

-- Políticas que valiam só pelo "dono" agora também exigem perfil ativo
drop policy if exists perfis_editar_proprio on public.perfis;
create policy perfis_editar_proprio on public.perfis for update to authenticated
  using (id = (select auth.uid()) and public.is_ativo()) with check (id = (select auth.uid()));
drop policy if exists provas_ver on public.provas;
create policy provas_ver on public.provas for select to authenticated using (public.is_ativo());
drop policy if exists reembolsos_ver on public.reembolsos;
create policy reembolsos_ver on public.reembolsos for select to authenticated
  using ((atleta_id = (select auth.uid()) and public.is_ativo()) or public.is_gestao());
drop policy if exists reembolsos_atleta_cancelar on public.reembolsos;
create policy reembolsos_atleta_cancelar on public.reembolsos for update to authenticated
  using (atleta_id = (select auth.uid()) and status = 'pendente' and public.is_ativo())
  with check (atleta_id = (select auth.uid()) and status = 'cancelado');
drop policy if exists renovacoes_ver on public.renovacoes;
create policy renovacoes_ver on public.renovacoes for select to authenticated
  using ((atleta_id = (select auth.uid()) and public.is_ativo()) or public.is_gestao());
drop policy if exists renovacoes_atleta_cancelar on public.renovacoes;
create policy renovacoes_atleta_cancelar on public.renovacoes for update to authenticated
  using (atleta_id = (select auth.uid()) and status = 'pendente' and public.is_ativo())
  with check (atleta_id = (select auth.uid()) and status = 'cancelada');
drop policy if exists anexos_ver on storage.objects;
create policy anexos_ver on storage.objects for select to authenticated
  using (bucket_id = 'anexos'
         and (((storage.foldername(name))[1] = (select auth.uid())::text and public.is_ativo()) or public.is_gestao()));
drop policy if exists anexos_apagar on storage.objects;
create policy anexos_apagar on storage.objects for delete to authenticated
  using (bucket_id = 'anexos' and (storage.foldername(name))[1] = (select auth.uid())::text and public.is_ativo());

-- Alterar o status: só o admin, nunca o próprio, e sempre sobra um admin ativo
create or replace function public.definir_status(alvo uuid, novo text, motivo text default null) returns void
language plpgsql security definer set search_path = ''
as $$
declare atual text; papel_alvo text;
begin
  if not public.is_admin() then
    raise exception 'Somente o administrador pode alterar o status.';
  end if;
  if novo not in ('ativo', 'inativo', 'bloqueado') then
    raise exception 'Status inválido.';
  end if;
  if alvo = (select auth.uid()) then
    raise exception 'Você não pode alterar o seu próprio status.';
  end if;
  select status, papel into atual, papel_alvo from public.perfis where id = alvo for update;
  if atual is null then
    raise exception 'Usuário não encontrado.';
  end if;
  if atual = novo then
    return;
  end if;
  if papel_alvo = 'admin' and novo <> 'ativo'
     and (select count(*) from public.perfis where papel = 'admin' and status = 'ativo' and id <> alvo) < 1 then
    raise exception 'Mantenha pelo menos um administrador ativo.';
  end if;
  update public.perfis set status = novo where id = alvo;
  insert into public.status_historico (alvo, status_anterior, status_novo, motivo, alterado_por)
  values (alvo, atual, novo, nullif(btrim(motivo), ''), (select auth.uid()));
end;
$$;
revoke execute on function public.definir_status(uuid, text, text) from public, anon;
grant execute on function public.definir_status(uuid, text, text) to authenticated;

-- Inativo e bloqueado também não conseguem entrar (bloqueio no Auth); ativo libera de novo
create or replace function public.sincronizar_banimento() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  update auth.users
     set banned_until = case when new.status = 'ativo' then null else now() + interval '100 years' end
   where id = new.id;
  return null;
end;
$$;
drop trigger if exists ao_mudar_status on public.perfis;
create trigger ao_mudar_status after update of status on public.perfis
  for each row when (new.status is distinct from old.status)
  execute function public.sincronizar_banimento();

-- 2) Bloqueio após 3 senhas incorretas em 1 hora (usado pela função "entrar") --------------
create table if not exists public.tentativas_senha (
  id      bigint generated always as identity primary key,
  user_id uuid not null references public.perfis (id) on delete cascade,
  em      timestamptz not null default now()
);
create index if not exists tentativas_senha_idx on public.tentativas_senha (user_id, em);
revoke all on public.tentativas_senha from anon, authenticated;
alter table public.tentativas_senha enable row level security;   -- sem políticas: só o servidor acessa

create or replace function public.bloquear_por_tentativas(alvo uuid) returns void
language plpgsql security definer set search_path = ''
as $$
declare atual text;
begin
  select status into atual from public.perfis where id = alvo for update;
  if atual = 'ativo' then
    update public.perfis set status = 'bloqueado' where id = alvo;
    insert into public.status_historico (alvo, status_anterior, status_novo, motivo, alterado_por)
    values (alvo, 'ativo', 'bloqueado', '3 tentativas de senha incorretas em 1 hora', null);
  end if;
  delete from public.tentativas_senha where user_id = alvo;
end;
$$;
revoke execute on function public.bloquear_por_tentativas(uuid) from public, anon, authenticated;
grant execute on function public.bloquear_por_tentativas(uuid) to service_role;

-- 3) Redefinição de senha só com aprovação do admin ---------------------------------------------
create table if not exists public.solicitacoes_senha (
  id             uuid primary key default gen_random_uuid(),
  atleta_id      uuid not null references public.perfis (id) on delete cascade,
  email          text not null,
  status         text not null default 'pendente' check (status in ('pendente', 'aprovada', 'recusada')),
  motivo_decisao text,
  decidido_por   uuid,
  decidido_em    timestamptz,
  liberado_ate   timestamptz,     -- janela em que o e-mail de redefinição pode ser enviado
  usada_em       timestamptz,
  criado_em      timestamptz not null default now()
);
create unique index if not exists solicitacao_senha_pendente_unica
  on public.solicitacoes_senha (atleta_id) where status = 'pendente';
revoke all on public.solicitacoes_senha from anon;
revoke insert, update, delete on public.solicitacoes_senha from authenticated;
alter table public.solicitacoes_senha enable row level security;
drop policy if exists solicitacoes_senha_admin on public.solicitacoes_senha;
create policy solicitacoes_senha_admin on public.solicitacoes_senha for select to authenticated
  using (public.is_admin());

-- Qualquer pessoa (mesmo sem login) pode ABRIR o pedido; a resposta é sempre a mesma,
-- exista ou não o e-mail, para não revelar quem tem conta.
create or replace function public.solicitar_reset_senha(p_email text) returns void
language plpgsql security definer set search_path = ''
as $$
declare pid uuid; em text := lower(btrim(coalesce(p_email, '')));
begin
  select id into pid from public.perfis where lower(email) = em;
  if pid is not null then
    insert into public.solicitacoes_senha (atleta_id, email) values (pid, em)
    on conflict (atleta_id) where status = 'pendente' do nothing;
  end if;
end;
$$;
revoke execute on function public.solicitar_reset_senha(text) from public;
grant execute on function public.solicitar_reset_senha(text) to anon, authenticated;

-- Trava: o Auth só consegue gravar um novo link de recuperação se houver aprovação vigente.
-- Assim, chamar a API de recuperação direto (sem passar pelo portal) também é barrado.
create or replace function public.exigir_aprovacao_reset() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare sid uuid;
begin
  select id into sid from public.solicitacoes_senha
   where atleta_id = new.id and status = 'aprovada' and usada_em is null and liberado_ate > now()
   order by liberado_ate desc limit 1 for update;
  if sid is null then
    raise exception 'A redefinição de senha precisa ser aprovada por um administrador.';
  end if;
  update public.solicitacoes_senha set usada_em = now() where id = sid;
  return new;
end;
$$;
drop trigger if exists exigir_aprovacao_reset on auth.users;
create trigger exigir_aprovacao_reset before update on auth.users
  for each row when (new.recovery_sent_at is not null and new.recovery_sent_at is distinct from old.recovery_sent_at)
  execute function public.exigir_aprovacao_reset();

-- 4) (Opcional, só planos Teams/Enterprise) bloqueio nativo no Auth ------------------------------
-- O "Password Verification Hook" do Supabase só existe nesses planos. Com ele, o bloqueio
-- valeria também para chamadas diretas à API. Nos demais planos, o bloqueio é feito pela
-- função de servidor "entrar" (veja o Manual do desenvolvedor).


-- 5) PRIMEIRO ACESSO DE ADMINISTRADOR ------------------------------------------
-- Cadastre-se no sistema, depois rode (trocando o e-mail). Os demais níveis
-- (gestao e atleta) o próprio administrador atribui pela aba "Usuários".
--
-- update public.perfis set papel = 'admin'
-- where id = (select id from auth.users where email = 'admin@exemplo.com');

-- 6) TESTE DE PERMISSÕES (faça antes do piloto) --------------------------------
-- Com duas contas de atleta (A e B) e uma de gestão, confirme que:
--  - A não enxerga perfil, atestado nem reembolso de B;
--  - A não consegue mudar o próprio papel, as validades, o valor ou o status (exceto cancelar pendente);
--  - a renovação pedida por A só vale depois que a gestão aprova;
--  - A e B não conseguem criar, alterar ou apagar provas;
--  - a gestão vê todos e consegue aprovar, recusar e marcar como pago.
