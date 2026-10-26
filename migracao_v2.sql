-- migracao_v2.sql — melhorias EAMSP (v2). Idempotente: pode ser rodada mais de uma vez.
-- Rode no SQL Editor do Supabase DEPOIS do schema.sql. Cada seção abaixo é independente.

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
  if not reenvio and (new.prova_id is distinct from old.prova_id
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
  using (atleta_id = (select auth.uid()) and status = 'recusado' and public.is_ativo())
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
    and exists (select 1 from public.provas p where p.id = prova_id and p.data >= current_date));
drop policy if exists prova_participantes_alterar on public.prova_participantes;
create policy prova_participantes_alterar on public.prova_participantes for update to authenticated
  using (atleta_id = (select auth.uid()) and public.is_atleta()
    and exists (select 1 from public.provas p where p.id = prova_id and p.data >= current_date))
  with check (atleta_id = (select auth.uid()) and public.is_atleta()
    and exists (select 1 from public.provas p where p.id = prova_id and p.data >= current_date));
drop policy if exists prova_participantes_apagar on public.prova_participantes;
create policy prova_participantes_apagar on public.prova_participantes for delete to authenticated
  using (atleta_id = (select auth.uid()) and public.is_atleta()
    and exists (select 1 from public.provas p where p.id = prova_id and p.data >= current_date));
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
revoke insert, update, delete on public.avisos from authenticated;
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
