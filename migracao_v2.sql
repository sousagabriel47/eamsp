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
