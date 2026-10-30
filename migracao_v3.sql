-- migracao_v3.sql — dashboard financeiro, pagamento em lote e função patrocinador.
-- Para quem já tem a v2 instalada; instalações novas usam apenas o schema.sql.
-- Rode depois da migracao_v2.sql. Idempotente.
-- ATENÇÃO: depois de rodar a migracao_v2.sql de novo, rode esta migracao_v3.sql novamente
-- (a v2 recria o gatilho de reembolsos sem as regras daqui).

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
