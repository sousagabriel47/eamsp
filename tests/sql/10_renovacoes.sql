-- V2.1: emissão e pagamento nas renovações
insert into auth.users (id, email, raw_user_meta_data) values
  ('a0000000-0000-4000-8000-000000000001', 'g1@t.com', '{"nome":"Gestor Um"}'),
  ('a0000000-0000-4000-8000-000000000002', 'g2@t.com', '{"nome":"Gestor Dois"}'),
  ('a0000000-0000-4000-8000-000000000003', 'at@t.com', '{"nome":"Atleta"}')
on conflict do nothing;
update public.perfis set papel = 'gestao', atleta = true where id in
  ('a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002');
update public.perfis set atleta = true where id = 'a0000000-0000-4000-8000-000000000003';

insert into public.renovacoes (id, atleta_id, tipo, nova_validade) values
  ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000003', 'atestado', current_date + 100),
  ('b0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000003', 'anuidade', current_date + 200),
  ('b0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000001', 'atestado', current_date + 100)
on conflict do nothing;

-- (a)(b)(c)(d)
do $$
declare ok boolean; msg text;
begin
  perform set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000002', true);
  set local role authenticated;

  -- (a) sem emissão
  begin
    update public.renovacoes set status = 'aprovada' where id = 'b0000000-0000-4000-8000-000000000001';
    assert false, 'a: deveria falhar sem emissão';
  exception when others then
    get stacked diagnostics msg = message_text;
    assert msg not like 'a:%', msg;
  end;
  -- (b) emissão futura
  begin
    update public.renovacoes set status = 'aprovada', emitido_em = current_date + 1
      where id = 'b0000000-0000-4000-8000-000000000001';
    assert false, 'b: deveria falhar com emissão futura';
  exception when others then
    get stacked diagnostics msg = message_text;
    assert msg not like 'b:%', msg;
  end;
  -- (c) atestado com pagamento
  begin
    update public.renovacoes set status = 'aprovada', emitido_em = current_date, pago_em = current_date
      where id = 'b0000000-0000-4000-8000-000000000001';
    assert false, 'c: deveria falhar com pago_em em atestado';
  exception when others then
    get stacked diagnostics msg = message_text;
    assert msg not like 'c:%', msg;
  end;
  -- (d) anuidade com emissão e pagamento
  update public.renovacoes set status = 'aprovada', emitido_em = current_date - 3, pago_em = current_date - 1
    where id = 'b0000000-0000-4000-8000-000000000002';
  reset role;
  assert (select status from public.renovacoes where id = 'b0000000-0000-4000-8000-000000000002') = 'aprovada';
  assert (select pago_em from public.renovacoes where id = 'b0000000-0000-4000-8000-000000000002') = current_date - 1;
  assert (select anuidade_ate from public.perfis where id = 'a0000000-0000-4000-8000-000000000003') = current_date + 200;
end $$;

-- (e) atleta tenta gravar emitido_em ao cancelar
do $$
declare msg text;
begin
  insert into public.renovacoes (id, atleta_id, tipo, nova_validade)
  values ('b0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000003', 'anuidade', current_date + 50);
  perform set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000003', true);
  set local role authenticated;
  begin
    update public.renovacoes set status = 'cancelada', emitido_em = current_date
      where id = 'b0000000-0000-4000-8000-000000000004';
    assert false, 'e: deveria falhar';
  exception when others then
    get stacked diagnostics msg = message_text;
    assert msg not like 'e:%', msg;
    assert msg like '%Datas só podem ser informadas na aprovação%', msg;
  end;
  reset role;
end $$;

-- (f) editar_emissao_renovacao
do $$
declare msg text; h record;
begin
  -- gestão 2 corrige a emissão da anuidade aprovada da atleta
  perform set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  perform public.editar_emissao_renovacao('b0000000-0000-4000-8000-000000000002', current_date - 10);
  select * into h from public.renovacao_emissao_historico
    where renovacao_id = 'b0000000-0000-4000-8000-000000000002';
  assert h.anterior = current_date - 3 and h.novo = current_date - 10 and h.alterado_por = 'a0000000-0000-4000-8000-000000000002', 'f: histórico';
  assert (select emitido_em from public.renovacoes where id = 'b0000000-0000-4000-8000-000000000002') = current_date - 10;
  -- futura
  begin
    perform public.editar_emissao_renovacao('b0000000-0000-4000-8000-000000000002', current_date + 1);
    assert false, 'f: futura deveria falhar';
  exception when others then
    get stacked diagnostics msg = message_text;
    assert msg not like 'f:%', msg;
  end;
  -- não aprovada
  begin
    perform public.editar_emissao_renovacao('b0000000-0000-4000-8000-000000000004', current_date);
    assert false, 'f: não aprovada deveria falhar';
  exception when others then
    get stacked diagnostics msg = message_text;
    assert msg not like 'f:%', msg;
  end;
  reset role;

  -- atleta
  perform set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000003', true);
  set local role authenticated;
  begin
    perform public.editar_emissao_renovacao('b0000000-0000-4000-8000-000000000002', current_date);
    assert false, 'f: atleta deveria falhar';
  exception when others then
    get stacked diagnostics msg = message_text;
    assert msg not like 'f:%', msg;
  end;
  -- histórico invisível ao atleta
  assert (select count(*) from public.renovacao_emissao_historico) = 0, 'f: atleta não lê histórico';
  reset role;

  -- própria renovação (gestor 1 aprova a sua via superusuário e tenta editar)
  perform set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000002', true);
  set local role authenticated;
  update public.renovacoes set status = 'aprovada', emitido_em = current_date
    where id = 'b0000000-0000-4000-8000-000000000003';
  reset role;
  perform set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000001', true);
  set local role authenticated;
  begin
    perform public.editar_emissao_renovacao('b0000000-0000-4000-8000-000000000003', current_date - 1);
    assert false, 'f: própria deveria falhar';
  exception when others then
    get stacked diagnostics msg = message_text;
    assert msg not like 'f:%', msg;
  end;
  reset role;
end $$;
