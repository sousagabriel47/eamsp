-- O PostgREST (API do Supabase) só consegue fazer `perfis(nome)` numa consulta quando existe
-- EXATAMENTE UMA chave estrangeira entre as duas tabelas; com duas a consulta falha com
-- "Could not embed because more than one relationship was found". Este teste protege isso.
do $$
declare t text; n int;
begin
  for t in select unnest(array['reembolsos', 'renovacoes', 'prova_participantes', 'solicitacoes_senha']) loop
    select count(*) into n from pg_constraint c
     where c.contype = 'f' and c.conrelid = ('public.' || t)::regclass and c.confrelid = 'public.perfis'::regclass;
    assert n = 1, t || ' deve ter exatamente 1 chave estrangeira para perfis (tem ' || n || ')';
  end loop;

  select count(*) into n from pg_constraint c
   where c.contype = 'f' and c.conrelid = 'public.reembolsos'::regclass and c.confrelid = 'public.provas'::regclass;
  assert n = 1, 'reembolsos deve ter exatamente 1 chave estrangeira para provas (tem ' || n || ')';

  select count(*) into n from pg_constraint c
   where c.contype = 'f' and c.conrelid = 'public.provas'::regclass and c.confrelid = 'public.prova_distancias'::regclass;
  assert n = 0, 'provas não deve apontar para prova_distancias';
  select count(*) into n from pg_constraint c
   where c.contype = 'f' and c.conrelid = 'public.prova_distancias'::regclass and c.confrelid = 'public.provas'::regclass;
  assert n = 1, 'prova_distancias deve ter exatamente 1 chave estrangeira para provas (tem ' || n || ')';
end $$;

-- Quem já rodou a v3 antiga tem a FK extra: reaplicar a migração precisa removê-la.
begin;
alter table public.reembolsos
  add constraint reembolsos_pago_por_fkey foreign key (pago_por) references public.perfis (id) on delete set null;
\ir ../../migracao_v3.sql
do $$
declare n int;
begin
  select count(*) into n from pg_constraint c
   where c.contype = 'f' and c.conrelid = 'public.reembolsos'::regclass and c.confrelid = 'public.perfis'::regclass;
  assert n = 1, 'reaplicar a migração v3 deve remover a FK extra de pago_por (restam ' || n || ')';
end $$;
rollback;
