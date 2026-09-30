var sb, me = null, prof = null, admin = false, P = [], ATL = [], R = [], REN = [], tab = 'cal', authMode = 'in', recovery = false;
var MES = ['janeiro','fevereiro','março','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro'];
var RTL = {pendente:'Pendente', aprovada:'Aprovada', recusada:'Recusada', cancelada:'Cancelada'};
var STL = {pendente:'Pendente', aprovado:'Aprovado', pago:'Pago', recusado:'Recusado', cancelado:'Cancelado'};
function $(s){return document.querySelector(s)}
function esc(s){return String(s==null?'':s).replace(/[&<>"]/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]})}
function today(){return new Date().toISOString().slice(0,10)}
function days(d){return Math.round((new Date(d+'T12:00')-new Date(today()+'T12:00'))/864e5)}
function br(d){var p=String(d).split('-');return p[2]+'/'+p[1]+'/'+p[0]}
function money(v){return Number(v).toLocaleString('pt-BR',{style:'currency',currency:'BRL'})}
function st(d){if(!d)return['Sem registro','b'];var n=days(d);if(n<0)return['Vencido há '+(-n)+' d','b'];if(n<=30)return['Vence em '+n+' d','w'];return['Válido até '+br(d),'']}
function tag(p){return'<span class="tag '+p[1]+'">'+p[0]+'</span>'}
function opts(a,f){return a.map(function(x){return'<option value="'+esc(x.id)+'">'+esc(f(x))+'</option>'}).join('')}
function fail(e){alert(e&&e.code==='23505' ? 'Você já tem uma solicitação pendente desse tipo.' : 'Não foi possível concluir: '+(e&&e.message||e))}
function msg(t){var m=$('#msg');if(m)m.textContent=t}

/* ---------- Acesso (login) ---------- */
function viewAuth(){
  var t = {in:'Entrar', up:'Criar conta', rs:'Recuperar senha'}, h = '<h2>' + t[authMode] + '</h2>';
  h += '<form id="f" style="max-width:420px;grid-template-columns:1fr">';
  if (authMode === 'up') h += '<label>Nome completo<input name="n" required autocomplete="name"></label>';
  h += '<label>E-mail<input type="email" name="e" required autocomplete="email"></label>';
  if (authMode !== 'rs') h += '<label>Senha (mínimo 8 caracteres)<input type="password" name="s" required minlength="8" autocomplete="' + (authMode === 'up' ? 'new-password' : 'current-password') + '"></label>';
  h += '<button class="btn">' + (authMode === 'in' ? 'Entrar' : authMode === 'up' ? 'Criar conta' : 'Enviar link') + '</button><p id="msg" class="sum"></p></form>';
  h += '<div class="acts">';
  if (authMode !== 'in') h += '<button class="btn s x" data-am="in">Já tenho conta</button>';
  if (authMode !== 'up') h += '<button class="btn s x" data-am="up">Criar conta</button>';
  if (authMode !== 'rs') h += '<button class="btn s x" data-am="rs">Esqueci a senha</button>';
  return h + '</div>';
}
function viewRecovery(){
  return '<h2>Nova senha</h2><form id="f" style="max-width:420px;grid-template-columns:1fr"><label>Nova senha (mínimo 8 caracteres)<input type="password" name="s" required minlength="8" autocomplete="new-password"></label><button class="btn">Salvar senha</button><p id="msg" class="sum"></p></form>';
}
function showAuth(){
  $('#nav').innerHTML = ''; $('#out').hidden = true; $('#role').textContent = 'Gestão da equipe de corrida';
  $('#app').innerHTML = recovery ? viewRecovery() : viewAuth();
  var f = $('#f');
  f.onsubmit = async function(e){
    e.preventDefault(); var d = new FormData(f), r; msg('Aguarde…');
    if (recovery) {
      r = await sb.auth.updateUser({password: d.get('s')});
      if (r.error) return msg(r.error.message);
      recovery = false; boot(); return;
    }
    if (authMode === 'in') { r = await sb.auth.signInWithPassword({email: d.get('e'), password: d.get('s')}); if (r.error) msg('E-mail ou senha incorretos.'); }
    if (authMode === 'up') {
      r = await sb.auth.signUp({email: d.get('e'), password: d.get('s'), options: {data: {nome: d.get('n')}, emailRedirectTo: location.origin + location.pathname}});
      if (r.error) return msg(r.error.message);
      msg(r.data.session ? 'Conta criada.' : 'Conta criada. Confirme pelo link enviado ao seu e-mail e depois entre.');
    }
    if (authMode === 'rs') {
      r = await sb.auth.resetPasswordForEmail(d.get('e'), {redirectTo: location.origin + location.pathname});
      msg(r.error ? r.error.message : 'Se o e-mail estiver cadastrado, você receberá um link para criar uma nova senha.');
    }
  };
}

/* ---------- Telas ---------- */
function viewCal(){
  var h = '<h2>Calendário de provas</h2>';
  if (admin) h += '<form id="f"><label>Prova<input name="n" required></label><label>Data<input type="date" name="d" required></label><label>Local<input name="l"></label><label>Distância<input name="k" placeholder="10 km"></label><label>Inscrição até<input type="date" name="i"></label><button class="btn">Adicionar prova</button></form>';
  var m = '';
  if (!P.length) h += '<p class="empty">Nenhuma prova cadastrada' + (admin ? '. Adicione a primeira acima.' : ' ainda.') + '</p>';
  P.forEach(function(p){
    var ym = p.data.slice(0,7);
    if (ym !== m) { m = ym; h += '<div class="mes">' + MES[+ym.slice(5)-1] + ' de ' + ym.slice(0,4) + '</div>'; }
    var n = days(p.data), ins = p.inscricao_ate ? (days(p.inscricao_ate) < 0 ? 'Inscrições encerradas' : 'Inscrição até ' + br(p.inscricao_ate)) : '';
    h += '<div class="item"><div class="date">' + p.data.slice(8) + '<small>' + MES[+p.data.slice(5,7)-1].slice(0,3) + '</small></div><div class="info"><b>' + esc(p.nome) + '</b><small>' + esc([p.local, p.distancia, ins].filter(Boolean).join(' • ')) + '</small></div>' + (n < 0 ? '<span class="tag">Realizada</span>' : '<span class="tag ' + (n <= 14 ? 'w' : '') + '">' + (n == 0 ? 'Hoje' : 'em ' + n + ' d') + '</span>') + (admin ? '<button class="btn s x" data-delp="' + esc(p.id) + '">Excluir</button>' : '') + '</div>';
  });
  return h;
}
function viewAth(){
  var h = '<h2>Registros dos atletas</h2>', al = [];
  ATL.forEach(function(a){[['atestado', a.atestado_validade], ['anuidade', a.anuidade_ate]].forEach(function(x){var s = st(x[1]); if (s[1]) al.push('<div class="al ' + (s[1] == 'b' ? 'bad' : '') + '"><b>' + esc(a.nome || 'Sem nome') + '</b>: ' + x[0] + ' · ' + s[0] + '</div>');});});
  if (al.length) h += '<div class="alerts">' + al.join('') + '</div>';
  if (!ATL.length) h += '<p class="empty">Nenhum atleta cadastrado ainda.</p>';
  ATL.slice().sort(function(a,b){return (a.nome||'').localeCompare(b.nome||'')}).forEach(function(a){
    h += '<div class="item"><div class="info"><b>' + esc(a.nome || 'Sem nome') + '</b><small>Atestado</small> ' + tag(st(a.atestado_validade)) + '<br><small>Anuidade</small> ' + tag(st(a.anuidade_ate)) + '</div></div>';
  });
  return h;
}
function viewMine(){
  var mine = REN.filter(function(x){return x.atleta_id === me.id});
  var h = '<h2>Meus dados</h2><form id="f"><label>Nome<input name="n" required value="' + esc(prof.nome) + '"></label><button class="btn">Salvar nome</button></form>';
  h += '<h2>Atestado e anuidade</h2><div class="item"><div class="info"><small>Atestado</small> ' + tag(st(prof.atestado_validade)) + '<br><small>Anuidade</small> ' + tag(st(prof.anuidade_ate)) + '</div></div>';
  h += '<p class="sum">A nova validade só passa a valer depois que a gestão validar a solicitação.</p>';
  h += '<form id="f2"><label>O que renovar<select name="tp"><option value="atestado">Atestado</option><option value="anuidade">Anuidade</option></select></label><label>Nova validade<input type="date" name="v" required min="' + today() + '"></label><button class="btn">Solicitar renovação</button></form>';
  if (!mine.length) h += '<p class="empty">Nenhuma solicitação de renovação.</p>';
  mine.forEach(function(x){
    var c = x.status == 'recusada' || x.status == 'cancelada' ? 'b' : x.status == 'pendente' ? 'w' : '';
    h += '<div class="item"><div class="info"><b>' + (x.tipo == 'atestado' ? 'Atestado' : 'Anuidade') + ' até ' + br(x.nova_validade) + '</b><small>Solicitada em ' + br(x.criado_em.slice(0,10)) + (x.status == 'recusada' && x.motivo_decisao ? ' • Motivo: ' + esc(x.motivo_decisao) : '') + '</small></div><span class="tag ' + c + '">' + RTL[x.status] + '</span>' + (x.status == 'pendente' ? '<div class="acts"><button class="btn s x" data-rn="cancelada|' + x.id + '">Cancelar</button></div>' : '') + '</div>';
  });
  return h;
}
function viewRen(){
  var pend = REN.filter(function(x){return x.status == 'pendente'}), done = REN.filter(function(x){return x.status != 'pendente'}).slice(0, 15);
  var h = '<h2>Renovações de atestado e anuidade</h2><p class="sum">Confira o comprovante fora do sistema e valide. A nova validade só é aplicada ao aprovar.</p>';
  if (!pend.length) h += '<p class="empty">Nenhuma renovação aguardando validação.</p>';
  pend.forEach(function(x){
    var a = ATL.filter(function(y){return y.id === x.atleta_id})[0], cur = a ? (x.tipo == 'atestado' ? a.atestado_validade : a.anuidade_ate) : null;
    h += '<div class="item"><div class="info"><b>' + esc(x.perfis && x.perfis.nome || 'Sem nome') + ' · ' + (x.tipo == 'atestado' ? 'Atestado' : 'Anuidade') + '</b><small>Nova validade ' + br(x.nova_validade) + ' • atual: ' + (cur ? br(cur) : 'sem registro') + '</small></div><div class="acts"><button class="btn s g" data-rn="aprovada|' + x.id + '">Aprovar</button><button class="btn s x" data-rn="recusada|' + x.id + '">Recusar</button></div></div>';
  });
  if (done.length) h += '<div class="mes">Últimas decisões</div>';
  done.forEach(function(x){
    var c = x.status == 'aprovada' ? '' : 'b';
    h += '<div class="item"><div class="info"><b>' + esc(x.perfis && x.perfis.nome || 'Sem nome') + ' · ' + (x.tipo == 'atestado' ? 'Atestado' : 'Anuidade') + ' até ' + br(x.nova_validade) + '</b><small>' + (x.motivo_decisao ? 'Motivo: ' + esc(x.motivo_decisao) : '') + '</small></div><span class="tag ' + c + '">' + RTL[x.status] + '</span></div>';
  });
  return h;
}
function viewReb(){
  var h = '<h2>' + (admin ? 'Solicitações de reembolso' : 'Meus reembolsos') + '</h2>';
  if (!admin) {
    if (!prof.nome) return h + '<p class="empty">Preencha seu nome em "Meus dados" antes de pedir reembolso.</p>';
    h += '<form id="f"><label>Prova<select name="p"><option value="">Sem prova</option>' + opts(P, function(x){return x.nome}) + '</select></label><label>Descrição<input name="t" placeholder="Inscrição, transporte…" required></label><label>Valor (R$)<input type="number" name="v" step="0.01" min="0.01" required></label><button class="btn">Solicitar reembolso</button></form>';
  } else {
    var tot = {pendente:0, aprovado:0, pago:0};
    R.forEach(function(r){ if (tot[r.status] !== undefined) tot[r.status] += Number(r.valor); });
    h += '<p class="sum">Pendente ' + money(tot.pendente) + ' · Aprovado a pagar ' + money(tot.aprovado) + ' · Pago ' + money(tot.pago) + '</p>';
  }
  if (!R.length) h += '<p class="empty">Nenhuma solicitação até agora.</p>';
  R.forEach(function(r){
    var c = r.status == 'recusado' || r.status == 'cancelado' ? 'b' : r.status == 'pendente' ? 'w' : '';
    var nome = r.perfis && r.perfis.nome ? r.perfis.nome : 'Sem nome';
    h += '<div class="item"><div class="info"><b>' + (admin ? esc(nome) + ' · ' : '') + money(r.valor) + '</b><small>' + esc(r.descricao) + (r.provas ? ' • ' + esc(r.provas.nome) : '') + ' • ' + br(r.criado_em.slice(0,10)) + (r.status == 'recusado' && r.motivo_decisao ? ' • Motivo: ' + esc(r.motivo_decisao) : '') + '</small></div><span class="tag ' + c + '">' + STL[r.status] + '</span><div class="acts">' +
      (admin && r.status == 'pendente' ? '<button class="btn s g" data-st="aprovado|' + r.id + '">Aprovar</button><button class="btn s x" data-st="recusado|' + r.id + '">Recusar</button>' : '') +
      (admin && r.status == 'aprovado' ? '<button class="btn s g" data-st="pago|' + r.id + '">Marcar como pago</button>' : '') +
      (!admin && r.status == 'pendente' ? '<button class="btn s x" data-st="cancelado|' + r.id + '">Cancelar</button>' : '') + '</div></div>';
  });
  return h;
}

/* ---------- Dados ---------- */
async function refresh(){
  var pr = await sb.from('perfis').select('*').eq('id', me.id).single();
  if (pr.error) return fail(pr.error);
  prof = pr.data; admin = prof.papel === 'gestao';
  var a = await Promise.all([
    sb.from('provas').select('*').order('data'),
    sb.from('reembolsos').select('*, perfis(nome), provas(nome)').order('criado_em', {ascending: false}),
    admin ? sb.from('perfis').select('*').eq('papel', 'atleta') : Promise.resolve({data: []}),
    sb.from('renovacoes').select('*, perfis(nome)').order('criado_em', {ascending: false})
  ]);
  for (var i = 0; i < a.length; i++) if (a[i].error) return fail(a[i].error);
  P = a[0].data; R = a[1].data; ATL = a[2].data; REN = a[3].data; render();
}
function render(){
  var np = REN.filter(function(x){return x.status == 'pendente'}).length, nr = R.filter(function(x){return x.status == 'pendente'}).length;
  var tabs = admin ? [['cal','Calendário'],['ath','Atletas'],['ren','Renovações' + (np ? ' (' + np + ')' : '')],['reb','Reembolsos' + (nr ? ' (' + nr + ')' : '')]] : [['cal','Calendário'],['me','Meus dados'],['reb','Reembolsos']];
  if (!tabs.some(function(t){return t[0] == tab})) tab = 'cal';
  $('#nav').innerHTML = tabs.map(function(t){return '<button data-t="' + t[0] + '"' + (t[0] == tab ? ' class="on"' : '') + '>' + t[1] + '</button>'}).join('');
  $('#role').textContent = (admin ? 'Acesso de gestão' : 'Acesso de atleta') + (prof.nome ? ' · ' + prof.nome : '');
  $('#out').hidden = false;
  $('#app').innerHTML = ({cal: viewCal, ath: viewAth, me: viewMine, ren: viewRen, reb: viewReb})[tab]();
  var f = $('#f');
  if (f) f.onsubmit = async function(e){
    e.preventDefault(); var d = new FormData(f), r;
    if (tab == 'cal') r = await sb.from('provas').insert({nome: d.get('n'), data: d.get('d'), local: d.get('l'), distancia: d.get('k'), inscricao_ate: d.get('i') || null});
    if (tab == 'me') r = await sb.from('perfis').update({nome: d.get('n').trim()}).eq('id', me.id);
    if (tab == 'reb') r = await sb.from('reembolsos').insert({atleta_id: me.id, prova_id: d.get('p') || null, descricao: d.get('t'), valor: Number(d.get('v')), status: 'pendente'});
    if (r && r.error) return fail(r.error);
    refresh();
  };
  var f2 = $('#f2');
  if (f2) f2.onsubmit = async function(e){
    e.preventDefault(); var d = new FormData(f2);
    var r = await sb.from('renovacoes').insert({atleta_id: me.id, tipo: d.get('tp'), nova_validade: d.get('v'), status: 'pendente'});
    if (r.error) return fail(r.error);
    refresh();
  };
}

document.addEventListener('click', async function(e){
  var b = e.target.closest('button'); if (!b) return;
  if (b.dataset.am) { authMode = b.dataset.am; showAuth(); return; }
  if (b.id === 'out') { await sb.auth.signOut(); return; }
  if (b.dataset.t) { tab = b.dataset.t; refresh(); return; }
  var r;
  if (b.dataset.delp) { if (!confirm('Excluir esta prova?')) return; r = await sb.from('provas').delete().eq('id', b.dataset.delp); }
  else if (b.dataset.st) {
    var p = b.dataset.st.split('|'), u = {status: p[0]};
    if (p[0] === 'recusado') { u.motivo_decisao = (prompt('Motivo da recusa (obrigatório):') || '').trim(); if (!u.motivo_decisao) return; }
    else if (p[0] === 'aprovado' && !confirm('Aprovar este reembolso?')) return;
    r = await sb.from('reembolsos').update(u).eq('id', p[1]);
  }
  else if (b.dataset.rn) {
    var q = b.dataset.rn.split('|'), w = {status: q[0]};
    if (q[0] === 'recusada') { w.motivo_decisao = (prompt('Motivo da recusa (obrigatório):') || '').trim(); if (!w.motivo_decisao) return; }
    else if (q[0] === 'aprovada' && !confirm('Confirma que o comprovante foi conferido? A nova validade passa a valer.')) return;
    r = await sb.from('renovacoes').update(w).eq('id', q[1]);
  }
  else return;
  if (r.error) return fail(r.error);
  refresh();
});

/* ---------- Início ---------- */
async function boot(){
  var s = await sb.auth.getSession();
  me = s.data.session ? s.data.session.user : null;
  if (recovery || !me) { prof = null; showAuth(); } else { await refresh(); }
}
(function(){
  if (typeof SUPABASE_URL === 'undefined' || SUPABASE_URL.indexOf('SEU-PROJETO') >= 0) {
    $('#app').innerHTML = '<p class="empty">Falta configurar o sistema: abra o arquivo config.js e cole a URL e a chave pública do seu projeto Supabase.</p>'; return;
  }
  sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  sb.auth.onAuthStateChange(function(ev, s){
    if (ev === 'PASSWORD_RECOVERY') recovery = true;
    if (['INITIAL_SESSION', 'SIGNED_IN', 'SIGNED_OUT', 'PASSWORD_RECOVERY'].indexOf(ev) < 0) return;
    if (ev === 'SIGNED_IN' && me && s && s.user.id === me.id) return;
    setTimeout(boot, 0);
  });
})();
