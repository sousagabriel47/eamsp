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


-- 4K) MELHORIAS V2
-- (mesmo conteúdo do migracao_v2.sql; idempotente)
-- V2.1) RENOVAÇÕES: data de emissão e de pagamento ---------------------------------------
alter table public.renovacoes add column if not exists emitido_em date;
alter table public.renovacoes add column if not exists pago_em date;

create table if not exists public.renovacao_emissao_historico (
  id            bigint generated always as identity primary key,
  renovacao_id  uuid not null references public.renovacoes (id) on delete cascade,
  anterior      date,
  novo          date not null,
  alterado_por  uuid,
  alterado_em   timestamptz not null default now()
);
revoke all on public.renovacao_emissao_historico from anon;
alter table public.renovacao_emissao_historico enable row level security;
drop policy if exists emissao_historico_gestao on public.renovacao_emissao_historico;
create policy emissao_historico_gestao on public.renovacao_emissao_historico
  for select to authenticated using (public.is_gestao());

-- Criação: mantém a regra de validade e ignora datas vindas do cliente (só a gestão as informa, na aprovação)
create or replace function public.validar_renovacao_nova() returns trigger
language plpgsql set search_path = ''
as $$
begin
  if new.nova_validade <= current_date or new.nova_validade > current_date + interval '2 years' then
    raise exception 'Informe uma validade futura, de até 2 anos.';
  end if;
  new.emitido_em := null;
  new.pago_em := null;
  return new;
end;
$$;

-- Gatilho de decisão: mantém as regras anteriores e acrescenta as datas.
create or replace function public.decidir_renovacao() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  -- correção de emissão feita pela função editar_emissao_renovacao (já valida e registra)
  if old.status = 'aprovada' and new.status = 'aprovada'
     and current_setting('eamsp.editando_emissao', true) = '1' and public.is_gestao() then
    return new;
  end if;
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
      if new.emitido_em is null then
        raise exception 'Informe a data de emissão.';
      end if;
      if new.emitido_em > current_date then
        raise exception 'A data de emissão não pode ser futura.';
      end if;
      if new.pago_em is not null and new.tipo <> 'anuidade' then
        raise exception 'A data de pagamento só vale para anuidade.';
      end if;
      if new.pago_em is not null and new.pago_em > current_date then
        raise exception 'A data de pagamento não pode ser futura.';
      end if;
      if new.tipo = 'atestado' then
        update public.perfis set atestado_validade = new.nova_validade where id = new.atleta_id;
      else
        update public.perfis set anuidade_ate = new.nova_validade where id = new.atleta_id;
      end if;
    end if;
  else
    raise exception 'Mudança de status inválida.';
  end if;
  if new.status in ('recusada', 'cancelada')
     and (new.emitido_em is distinct from old.emitido_em or new.pago_em is distinct from old.pago_em) then
    raise exception 'Datas só podem ser informadas na aprovação.';
  end if;
  return new;
end;
$$;

-- Correção da data de emissão de uma renovação já aprovada (só gestão, nunca a própria)
create or replace function public.editar_emissao_renovacao(p_id uuid, p_emissao date) returns void
language plpgsql security definer set search_path = ''
as $$
declare r public.renovacoes;
begin
  if not public.is_gestao() then
    raise exception 'Somente a gestão pode corrigir a emissão.';
  end if;
  select * into r from public.renovacoes where id = p_id for update;
  if not found then
    raise exception 'Renovação não encontrada.';
  end if;
  if r.status <> 'aprovada' then
    raise exception 'Só é possível corrigir a emissão de renovação aprovada.';
  end if;
  if r.atleta_id = (select auth.uid()) then
    raise exception 'Você não pode corrigir a sua própria renovação. Peça a outro gestor.';
  end if;
  if p_emissao is null or p_emissao > current_date then
    raise exception 'A data de emissão não pode ser futura.';
  end if;
  if r.emitido_em is not distinct from p_emissao then
    return;   -- mesma data: nada a corrigir, nada a registrar
  end if;
  perform set_config('eamsp.editando_emissao', '1', true);
  update public.renovacoes set emitido_em = p_emissao where id = p_id;
  perform set_config('eamsp.editando_emissao', '', true);
  insert into public.renovacao_emissao_historico (renovacao_id, anterior, novo, alterado_por)
  values (p_id, r.emitido_em, p_emissao, (select auth.uid()));
end;
$$;
revoke execute on function public.editar_emissao_renovacao(uuid, date) from public, anon;
grant execute on function public.editar_emissao_renovacao(uuid, date) to authenticated;

revoke update on public.renovacoes from authenticated;
grant update (status, motivo_decisao, emitido_em, pago_em) on public.renovacoes to authenticated;

-- V2.2) REEMBOLSO: valor da inscrição, reenvio de pedido recusado e histórico ------------
alter table public.provas add column if not exists valor_inscricao numeric(10,2)
  check (valor_inscricao is null or valor_inscricao >= 0);
alter table public.reembolsos add column if not exists valor_prova numeric(10,2);
alter table public.reembolso_historico add column if not exists motivo text;
alter table public.reembolso_historico add column if not exists valor numeric(10,2);

-- valor_prova é sempre o da prova escolhida; o que o cliente mandar é ignorado
create or replace function public.definir_valor_prova() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  new.valor_prova := (select p.valor_inscricao from public.provas p where p.id = new.prova_id);
  -- decisão nunca vem do cliente
  new.motivo_decisao := null;
  new.decidido_por := null;
  new.decidido_em := null;
  return new;
end;
$$;
drop trigger if exists antes_inserir_reembolso on public.reembolsos;
create trigger antes_inserir_reembolso before insert on public.reembolsos
  for each row execute function public.definir_valor_prova();

-- Gatilho de mudança: mantém as regras anteriores e acrescenta o reenvio (recusado -> pendente).
create or replace function public.registrar_mudanca_reembolso() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare reenvio boolean := false;
begin
  new.atualizado_em := now();
  new.valor_prova := old.valor_prova;
  if new.status is distinct from old.status then
    if not ((old.status = 'pendente' and new.status in ('aprovado', 'recusado', 'cancelado'))
         or (old.status = 'aprovado' and new.status = 'pago')
         or (old.status = 'recusado' and new.status = 'pendente')) then
      raise exception 'Mudança de status não permitida: % para %', old.status, new.status;
    end if;
    if old.status = 'recusado' and new.status = 'pendente' then
      if new.atleta_id is distinct from (select auth.uid()) then
        raise exception 'Só o dono do pedido pode reenviá-lo.';
      end if;
      reenvio := true;
      new.motivo_decisao := null;
      new.decidido_por := null;
      new.decidido_em := null;
      new.valor_prova := (select p.valor_inscricao from public.provas p where p.id = new.prova_id);
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
  end if;
  -- a prova apagada zera prova_id pela FK (on delete set null): isso não é edição do pedido
  if not reenvio and ((new.prova_id is distinct from old.prova_id
                       and not (new.prova_id is null
                                and not exists (select 1 from public.provas p where p.id = old.prova_id)))
                   or new.descricao is distinct from old.descricao
                   or new.valor is distinct from old.valor
                   or new.anexo_path is distinct from old.anexo_path) then
    raise exception 'Só é possível editar um pedido recusado ao reenviá-lo.';
  end if;
  if new.status is distinct from old.status then
    insert into public.reembolso_historico (reembolso_id, status_anterior, status_novo, alterado_por, motivo, valor)
    values (new.id, old.status, new.status, (select auth.uid()),
            case when new.status = 'recusado' then new.motivo_decisao end, new.valor);
  elsif new.motivo_decisao is distinct from old.motivo_decisao then
    raise exception 'O motivo só pode ser informado junto com a decisão.';
  end if;
  return new;
end;
$$;

-- O dono reenvia o próprio pedido recusado (o gatilho exige ser o dono e limpa a decisão)
drop policy if exists reembolsos_atleta_reenviar on public.reembolsos;
create policy reembolsos_atleta_reenviar on public.reembolsos for update to authenticated
  using (atleta_id = (select auth.uid()) and status = 'recusado' and public.is_ativo() and public.is_atleta())
  with check (atleta_id = (select auth.uid()) and status = 'pendente');

revoke update on public.reembolsos from authenticated;
grant update (status, motivo_decisao, prova_id, descricao, valor, anexo_path) on public.reembolsos to authenticated;

-- O dono também lê o histórico do próprio pedido; ninguém grava pelo cliente (só o gatilho)
drop policy if exists historico_dono on public.reembolso_historico;
create policy historico_dono on public.reembolso_historico for select to authenticated
  using (exists (select 1 from public.reembolsos r
                 where r.id = reembolso_id and r.atleta_id = (select auth.uid()) and public.is_ativo()));
revoke insert, update, delete on public.reembolso_historico from authenticated;

-- V2.3) CALENDÁRIO: distâncias por prova, participantes e lista de presença --------------
alter table public.provas add column if not exists tem_lista_presenca boolean not null default false;

create table if not exists public.prova_distancias (
  id        uuid primary key default gen_random_uuid(),
  prova_id  uuid not null references public.provas (id) on delete cascade,
  rotulo    text not null check (btrim(rotulo) <> ''),
  ordem     int not null default 0,
  unique (id, prova_id)
);
create table if not exists public.prova_participantes (
  prova_id      uuid not null references public.provas (id) on delete cascade,
  atleta_id     uuid not null references public.perfis (id) on delete cascade,
  distancia_id  uuid not null,
  criado_em     timestamptz not null default now(),
  primary key (prova_id, atleta_id),
  foreign key (distancia_id, prova_id) references public.prova_distancias (id, prova_id) on delete cascade
);

revoke all on public.prova_distancias from anon;
revoke all on public.prova_participantes from anon;
alter table public.prova_distancias enable row level security;
alter table public.prova_participantes enable row level security;

-- Distâncias: todos os ativos leem; só a gestão escreve
drop policy if exists prova_distancias_ver on public.prova_distancias;
create policy prova_distancias_ver on public.prova_distancias for select to authenticated
  using (public.is_ativo());
drop policy if exists prova_distancias_gestao_inserir on public.prova_distancias;
create policy prova_distancias_gestao_inserir on public.prova_distancias for insert to authenticated
  with check (public.is_gestao());
drop policy if exists prova_distancias_gestao_alterar on public.prova_distancias;
create policy prova_distancias_gestao_alterar on public.prova_distancias for update to authenticated
  using (public.is_gestao()) with check (public.is_gestao());
drop policy if exists prova_distancias_gestao_apagar on public.prova_distancias;
create policy prova_distancias_gestao_apagar on public.prova_distancias for delete to authenticated
  using (public.is_gestao());
revoke all on public.prova_distancias from authenticated;
grant select, insert, update, delete on public.prova_distancias to authenticated;

-- Participantes: leitura da própria linha ou gestão; o atleta escreve só a própria linha,
-- só em prova que ainda não passou (vale para insert, troca de distância e remoção).
-- A distância pertencer à prova é garantido pela FK composta.
drop policy if exists prova_participantes_ver on public.prova_participantes;
create policy prova_participantes_ver on public.prova_participantes for select to authenticated
  using (atleta_id = (select auth.uid()) or public.is_gestao());
drop policy if exists prova_participantes_inserir on public.prova_participantes;
create policy prova_participantes_inserir on public.prova_participantes for insert to authenticated
  with check (atleta_id = (select auth.uid()) and public.is_atleta()
    and exists (select 1 from public.provas p where p.id = prova_id and p.data >= (now() at time zone 'America/Sao_Paulo')::date));
drop policy if exists prova_participantes_alterar on public.prova_participantes;
create policy prova_participantes_alterar on public.prova_participantes for update to authenticated
  using (atleta_id = (select auth.uid()) and public.is_atleta()
    and exists (select 1 from public.provas p where p.id = prova_id and p.data >= (now() at time zone 'America/Sao_Paulo')::date))
  with check (atleta_id = (select auth.uid()) and public.is_atleta()
    and exists (select 1 from public.provas p where p.id = prova_id and p.data >= (now() at time zone 'America/Sao_Paulo')::date));
drop policy if exists prova_participantes_apagar on public.prova_participantes;
create policy prova_participantes_apagar on public.prova_participantes for delete to authenticated
  using (atleta_id = (select auth.uid()) and public.is_atleta()
    and exists (select 1 from public.provas p where p.id = prova_id and p.data >= (now() at time zone 'America/Sao_Paulo')::date));
revoke all on public.prova_participantes from authenticated;
grant select, insert, delete on public.prova_participantes to authenticated;
grant update (distancia_id) on public.prova_participantes to authenticated;

-- Migração de dados: texto antigo de provas.distancia vira uma distância
insert into public.prova_distancias (prova_id, rotulo)
select p.id, btrim(p.distancia) from public.provas p
where coalesce(btrim(p.distancia), '') <> ''
  and not exists (select 1 from public.prova_distancias d where d.prova_id = p.id);

-- V2.4) AVISOS: notificações de decisão (reembolso e renovação) ---------------------------
create table if not exists public.avisos (
  id          bigint generated always as identity primary key,
  usuario_id  uuid not null references public.perfis (id) on delete cascade,
  tipo        text not null,
  texto       text not null,
  ref_id      uuid,
  lido_em     timestamptz,
  criado_em   timestamptz not null default now()
);
create index if not exists avisos_usuario_lido_idx on public.avisos (usuario_id, lido_em);

revoke all on public.avisos from anon;
alter table public.avisos enable row level security;
drop policy if exists avisos_ver on public.avisos;
create policy avisos_ver on public.avisos for select to authenticated
  using (usuario_id = (select auth.uid()));
drop policy if exists avisos_marcar_lido on public.avisos;
create policy avisos_marcar_lido on public.avisos for update to authenticated
  using (usuario_id = (select auth.uid()))
  with check (usuario_id = (select auth.uid()));
revoke all on public.avisos from authenticated;
grant select on public.avisos to authenticated;
grant update (lido_em) on public.avisos to authenticated;

-- Só os gatilhos (security definer) criam avisos
create or replace function public.avisar_decisao_reembolso() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare v text := 'R$ ' || replace(replace(replace(to_char(new.valor, 'FM999,999,990.00'), ',', '#'), '.', ','), '#', '.');
begin
  if new.status is not distinct from old.status then
    return new;
  end if;
  if new.status = 'aprovado' then
    insert into public.avisos (usuario_id, tipo, texto, ref_id)
    values (new.atleta_id, 'reembolso_aprovado',
            'Seu pedido de reembolso de ' || v || ' foi aprovado.', new.id);
  elsif new.status = 'recusado' then
    insert into public.avisos (usuario_id, tipo, texto, ref_id)
    values (new.atleta_id, 'reembolso_recusado',
            'Seu pedido de reembolso de ' || v || ' foi recusado. Motivo: ' || coalesce(new.motivo_decisao, '-'), new.id);
  elsif new.status = 'pago' then
    insert into public.avisos (usuario_id, tipo, texto, ref_id)
    values (new.atleta_id, 'reembolso_pago',
            'Seu reembolso de ' || v || ' foi pago.', new.id);
  end if;
  return new;
end;
$$;
drop trigger if exists depois_decidir_reembolso on public.reembolsos;
create trigger depois_decidir_reembolso after update on public.reembolsos
  for each row execute function public.avisar_decisao_reembolso();

create or replace function public.avisar_decisao_renovacao() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare d text := to_char(new.nova_validade, 'DD/MM/YYYY');
begin
  if new.status is not distinct from old.status then
    return new;
  end if;
  if new.status = 'aprovada' then
    insert into public.avisos (usuario_id, tipo, texto, ref_id)
    values (new.atleta_id, 'renovacao_aprovada',
            'Sua renovação de ' || new.tipo || ' foi aprovada. Nova validade: ' || d || '.', new.id);
  elsif new.status = 'recusada' then
    insert into public.avisos (usuario_id, tipo, texto, ref_id)
    values (new.atleta_id, 'renovacao_recusada',
            'Sua renovação de ' || new.tipo || ' (validade ' || d || ') foi recusada. Motivo: '
              || coalesce(new.motivo_decisao, '-'), new.id);
  end if;
  return new;
end;
$$;
drop trigger if exists depois_decidir_renovacao on public.renovacoes;
create trigger depois_decidir_renovacao after update on public.renovacoes
  for each row execute function public.avisar_decisao_renovacao();

-- Faz a API do Supabase (PostgREST) reconhecer as tabelas e relações novas sem esperar o cache expirar
notify pgrst, 'reload schema';


-- 4L) DASHBOARD, PAGAMENTO EM LOTE E PATROCINADOR
-- V3.1) FUNÇÃO PATROCINADOR ---------------------------------------------------------------
-- Novo valor de papel. O patrocinador não ganha nenhuma permissão nova: não lê reembolsos,
-- renovações, perfis de outras pessoas, históricos nem avisos alheios. Só lê o calendário
-- não pessoal (provas e prova_distancias), que todo usuário ativo já lê.
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


-- V3.2) PAGAMENTO EM LOTE -----------------------------------------------------------------
alter table public.reembolsos add column if not exists pago_em date;
alter table public.reembolsos add column if not exists pago_por uuid references public.perfis (id) on delete set null;

-- Backfill idempotente: pagos antes desta migração usam a data da decisão (ou da última atualização; fuso de São Paulo)
update public.reembolsos
   set pago_em = (coalesce(decidido_em, atualizado_em) at time zone 'America/Sao_Paulo')::date,
       pago_por = decidido_por
 where status = 'pago' and pago_em is null;

-- pago_em/pago_por NÃO entram no grant de update: só o gatilho e pagar_reembolsos os gravam
revoke update on public.reembolsos from authenticated;
grant update (status, motivo_decisao, prova_id, descricao, valor, anexo_path) on public.reembolsos to authenticated;

-- Gatilho de mudança: mesmas regras da V2.2 + preenche pago_em/pago_por ao virar "pago"
create or replace function public.registrar_mudanca_reembolso() returns trigger
language plpgsql security definer set search_path = ''
as $$
declare reenvio boolean := false;
begin
  new.atualizado_em := now();
  new.valor_prova := old.valor_prova;
  if new.status is distinct from old.status then
    if not ((old.status = 'pendente' and new.status in ('aprovado', 'recusado', 'cancelado'))
         or (old.status = 'aprovado' and new.status = 'pago')
         or (old.status = 'recusado' and new.status = 'pendente')) then
      raise exception 'Mudança de status não permitida: % para %', old.status, new.status;
    end if;
    if old.status = 'recusado' and new.status = 'pendente' then
      if new.atleta_id is distinct from (select auth.uid()) then
        raise exception 'Só o dono do pedido pode reenviá-lo.';
      end if;
      reenvio := true;
      new.motivo_decisao := null;
      new.decidido_por := null;
      new.decidido_em := null;
      new.valor_prova := (select p.valor_inscricao from public.provas p where p.id = new.prova_id);
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
    -- data/autor do pagamento (o lote já traz os dois; o botão individual cai aqui)
    if new.status = 'pago' and old.status <> 'pago' and new.pago_em is null then
      new.pago_em  := (now() at time zone 'America/Sao_Paulo')::date;
      new.pago_por := coalesce(new.pago_por, (select auth.uid()));
    end if;
  end if;
  -- a prova apagada zera prova_id pela FK (on delete set null): isso não é edição do pedido
  if not reenvio and ((new.prova_id is distinct from old.prova_id
                       and not (new.prova_id is null
                                and not exists (select 1 from public.provas p where p.id = old.prova_id)))
                   or new.descricao is distinct from old.descricao
                   or new.valor is distinct from old.valor
                   or new.anexo_path is distinct from old.anexo_path) then
    raise exception 'Só é possível editar um pedido recusado ao reenviá-lo.';
  end if;
  if new.status is distinct from old.status then
    insert into public.reembolso_historico (reembolso_id, status_anterior, status_novo, alterado_por, motivo, valor)
    values (new.id, old.status, new.status, (select auth.uid()),
            case when new.status = 'recusado' then new.motivo_decisao end, new.valor);
  elsif new.motivo_decisao is distinct from old.motivo_decisao then
    raise exception 'O motivo só pode ser informado junto com a decisão.';
  end if;
  return new;
end;
$$;

create or replace function public.pagar_reembolsos(p_ids uuid[], p_data date) returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  ids uuid[];
  achados int;
  n int;
begin
  if not public.is_gestao() then
    raise exception 'Somente a gestão pode pagar reembolsos.';
  end if;
  select coalesce(array_agg(distinct x), '{}') into ids from unnest(p_ids) as x where x is not null;
  if coalesce(array_length(ids, 1), 0) = 0 then
    raise exception 'Selecione ao menos um reembolso.';
  end if;
  if p_data is null or p_data > (now() at time zone 'America/Sao_Paulo')::date then
    raise exception 'A data do pagamento não pode ser futura.';
  end if;
  -- trava as linhas: tudo ou nada
  perform 1 from public.reembolsos r where r.id = any (ids) order by r.id for update;
  select count(*) into achados from public.reembolsos r where r.id = any (ids);
  if achados <> array_length(ids, 1) then
    raise exception 'Reembolso não encontrado.';
  end if;
  if exists (select 1 from public.reembolsos r where r.id = any (ids) and r.status <> 'aprovado') then
    raise exception 'Só reembolsos aprovados podem ser pagos.';
  end if;
  if exists (select 1 from public.reembolsos r where r.id = any (ids) and r.atleta_id = uid) then
    raise exception 'Você não pode pagar o seu próprio reembolso. Peça a outro gestor.';
  end if;
  update public.reembolsos set status = 'pago', pago_em = p_data, pago_por = uid
   where id = any (ids);
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke execute on function public.pagar_reembolsos(uuid[], date) from public, anon;
grant execute on function public.pagar_reembolsos(uuid[], date) to authenticated;

-- V3.3) DASHBOARD FINANCEIRO --------------------------------------------------------------
-- Devolve só agregados. O patrocinador nunca recebe reembolsos individuais, nomes de atletas
-- nem descrições; a chave "atletas" só existe para gestão/admin. O período (p_de/p_ate, nulos =
-- sem limite) vale para a data de solicitação (criado_em em São Paulo): situações, provas, atletas,
-- solicitado por mês e tempo médio. Só a série "pago" por mês usa a data do pagamento (pago_em).
create or replace function public.dashboard_reembolsos(p_de date, p_ate date) returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  gestao boolean := public.is_gestao();
  res jsonb;
  atl jsonb;
begin
  if not (gestao or public.is_patrocinador()) then
    raise exception 'Sem permissão para ver o dashboard.';
  end if;

  with base as (
    select r.*, (r.criado_em at time zone 'America/Sao_Paulo')::date as dia
      from public.reembolsos r
     where (p_de is null or (r.criado_em at time zone 'America/Sao_Paulo')::date >= p_de)
       and (p_ate is null or (r.criado_em at time zone 'America/Sao_Paulo')::date <= p_ate)
  ),
  pagos as (
    select r.valor, r.pago_em
      from public.reembolsos r
     where r.status = 'pago' and r.pago_em is not null
       and (p_de is null or r.pago_em >= p_de)
       and (p_ate is null or r.pago_em <= p_ate)
  ),
  sit as (
    select s.s,
           jsonb_build_object('qtd', count(b.id), 'valor', coalesce(sum(b.valor), 0)) as v
      from unnest(array['pendente', 'aprovado', 'pago', 'recusado', 'cancelado']) as s(s)
      left join base b on b.status = s.s
     group by s.s
  ),
  meses as (
    select m.mes,
           coalesce((select sum(b.valor) from base b
                      where b.status <> 'cancelado' and to_char(b.dia, 'YYYY-MM') = m.mes), 0) as solicitado,
           coalesce((select sum(p.valor) from pagos p
                      where to_char(p.pago_em, 'YYYY-MM') = m.mes), 0) as pago
      from (select to_char(b.dia, 'YYYY-MM') as mes from base b where b.status <> 'cancelado'
            union
            select to_char(p.pago_em, 'YYYY-MM') from pagos p) m
  ),
  prov as (
    select coalesce(p.nome, 'Sem prova') as prova, count(*) as qtd, sum(b.valor) as valor
      from base b left join public.provas p on p.id = b.prova_id
     where b.status in ('pendente', 'aprovado', 'pago')
     group by coalesce(p.nome, 'Sem prova')
  )
  select jsonb_build_object(
    'situacoes', (select jsonb_object_agg(s, v) from sit),
    'meses', coalesce((select jsonb_agg(jsonb_build_object('mes', mes, 'solicitado', solicitado, 'pago', pago)
                                        order by mes) from meses), '[]'::jsonb),
    'provas', coalesce((select jsonb_agg(jsonb_build_object('prova', prova, 'qtd', qtd, 'valor', valor)
                                         order by valor desc, prova) from prov), '[]'::jsonb),
    'tempo_medio_dias', (select to_jsonb(round(avg(b.pago_em - b.dia), 1)) from base b where b.status = 'pago' and b.pago_em is not null)
  ) into res;

  if gestao then
    select coalesce(jsonb_agg(jsonb_build_object('nome', t.nome, 'pediu', t.pediu,
                                                 'recebeu', t.recebeu, 'a_receber', t.a_receber)
                              order by t.nome, t.atleta_id), '[]'::jsonb)
      into atl
      from (
        select r.atleta_id, pf.nome,
               coalesce(sum(r.valor) filter (where r.status <> 'cancelado'), 0) as pediu,
               coalesce(sum(r.valor) filter (where r.status = 'pago'), 0) as recebeu,
               coalesce(sum(r.valor) filter (where r.status = 'aprovado'), 0) as a_receber
          from public.reembolsos r
          join public.perfis pf on pf.id = r.atleta_id
         where (p_de is null or (r.criado_em at time zone 'America/Sao_Paulo')::date >= p_de)
           and (p_ate is null or (r.criado_em at time zone 'America/Sao_Paulo')::date <= p_ate)
         group by r.atleta_id, pf.nome
      ) t;
    res := res || jsonb_build_object('atletas', atl);
  end if;
  return res;
end;
$$;
revoke execute on function public.dashboard_reembolsos(date, date) from public, anon;
grant execute on function public.dashboard_reembolsos(date, date) to authenticated;

-- faz a API do Supabase reconhecer as novas funções/colunas sem esperar o cache
notify pgrst, 'reload schema';


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
--  - A não lê avisos nem participações ("Vou correr") de B;
--  - só o dono reenvia um reembolso recusado (e o histórico do pedido fica preservado);
--  - só a gestão informa a data de emissão e de pagamento de uma renovação;
--  - o atleta só se marca em prova futura e com distância que pertence à própria prova.
--  - o patrocinador não lê reembolsos, renovações nem perfis de outras pessoas, e o dashboard dele não traz nome nem descrição;
--  - só gestão/admin pagam em lote, e ninguém paga o próprio reembolso;
--  - pago_em e pago_por não mudam por update direto;
--  - atleta comum não executa o dashboard.
