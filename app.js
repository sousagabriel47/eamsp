var HASH = location.hash || '';
var ENTRADA = /type=invite/.test(HASH) ? 'invite' : /type=signup/.test(HASH) ? 'signup' : /type=recovery/.test(HASH) ? 'recovery' : '';
var ERRO = /error(_code|_description)?=/.test(HASH);
var sb, me = null, prof = null, admin = false, sup = false, sim = '', realAdmin = false, realSup = false, eAtl = false, USR = [], P = [], ATL = [], R = [], REN = [], tab = 'cal', authMode = 'in', recovery = false, invite = (ENTRADA === 'invite'), aviso = '';
var MES = ['janeiro','fevereiro','março','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro'];
var EXIGIR_ANEXO = false;          // true = o PDF passa a ser obrigatório em renovações e reembolsos
var MAX_PDF = 5 * 1024 * 1024;     // 5 MB (o mesmo limite está no bucket do Supabase)
async function validaPdf(f){
  if (!f || !f.size) return 'Arquivo vazio.';
  if (!/\.pdf$/i.test(f.name)) return 'O arquivo precisa ter a extensão .pdf.';
  if (f.type && f.type !== 'application/pdf') return 'O arquivo não é um PDF (tipo: ' + f.type + ').';
  if (f.size > MAX_PDF) return 'O PDF tem ' + (f.size / 1048576).toFixed(1).replace('.', ',') + ' MB; o máximo é 5 MB.';
  var cab = await f.slice(0, 5).text();
  if (cab !== '%PDF-') return 'O conteúdo do arquivo não é um PDF válido.';
  return '';
}
// devolve {path} (path nulo se não há arquivo) ou {err}
async function prepararAnexo(f){
  if (!f || !f.size) return EXIGIR_ANEXO ? {err: 'Anexe o PDF para continuar.'} : {path: null};
  var er = await validaPdf(f);
  if (er) return {err: er};
  var path = me.id + '/' + crypto.randomUUID() + '.pdf';
  var up = await sb.storage.from('anexos').upload(path, f, {contentType: 'application/pdf', upsert: false});
  return up.error ? {err: 'Falha no envio do PDF: ' + up.error.message} : {path: path};
}
async function abrirAnexo(path){
  var w = window.open('', '_blank');
  var r = await sb.storage.from('anexos').createSignedUrl(path, 120);
  if (r.error) { if (w) w.close(); return fail(r.error); }
  if (w) { w.opener = null; w.location = r.data.signedUrl; } else location.href = r.data.signedUrl;
}
function pdfBtn(x){ return x.anexo_path ? '<button class="btn s x" data-pdf="' + esc(x.anexo_path) + '">Ver PDF</button>' : ''; }
var MSGSIM = 'Modo simulação: as ações estão desativadas. Volte para "Minha visão" para agir.';
var PAP = {atleta:'Atleta', gestao:'Gestão', admin:'Administrador'};
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
  var t = {in:'Entrar', rs:'Recuperar senha'}, h = '<h2>' + t[authMode] + '</h2>';
  if (authMode === 'in') h += '<p class="sum">O acesso ao sistema é por convite. Se você ainda não recebeu o seu, fale com a gestão da equipe.</p>';
  h += '<form id="f" style="max-width:420px;grid-template-columns:1fr"><label>E-mail<input type="email" name="e" required autocomplete="email"></label>';
  if (authMode === 'in') h += '<label>Senha<input type="password" name="s" required autocomplete="current-password"></label>';
  h += '<button class="btn">' + (authMode === 'in' ? 'Entrar' : 'Enviar link') + '</button><p id="msg" class="sum"></p></form>';
  h += '<div class="acts">' + (authMode === 'rs' ? '<button class="btn s x" data-am="in">Voltar</button>' : '<button class="btn s x" data-am="rs">Esqueci a senha</button>') + '</div>';
  return h;
}
function viewRecovery(){
  return '<h2>Nova senha</h2><form id="f" style="max-width:420px;grid-template-columns:1fr"><label>Nova senha (mínimo 8 caracteres)<input type="password" name="s" required minlength="8" autocomplete="new-password"></label><button class="btn">Salvar senha</button><p id="msg" class="sum"></p></form>';
}
function viewInvite(){
  return '<h2>Aceitar convite</h2><p class="sum">Você foi convidado para o sistema da EAMSP. Informe seu nome e crie uma senha para ativar o acesso.</p><form id="f" style="max-width:420px;grid-template-columns:1fr"><label>Nome completo<input name="n" required autocomplete="name"></label><label>Senha (mínimo 8 caracteres)<input type="password" name="s" required minlength="8" autocomplete="new-password"></label><button class="btn">Ativar acesso</button><p id="msg" class="sum"></p></form>';
}
function showAuth(){
  $('#nav').innerHTML = ''; $('#out').hidden = true; $('#sim').hidden = true; $('#role').textContent = 'Gestão da equipe de corrida';
  if (invite && !me) invite = false;
  $('#app').innerHTML = invite ? viewInvite() : recovery ? viewRecovery() : viewAuth();
  if (ERRO && !me && !invite && !recovery) msg('Este link expirou ou já foi usado. Para recuperar o acesso, use "Esqueci a senha" ou peça um novo convite à gestão.'); ERRO = false;
  var f = $('#f');
  f.onsubmit = async function(e){
    e.preventDefault(); var d = new FormData(f), r; msg('Aguarde…');
    if (invite) {
      r = await sb.auth.updateUser({password: d.get('s'), data: {nome: d.get('n').trim()}});
      if (r.error) return msg(r.error.message);
      await sb.from('perfis').update({nome: d.get('n').trim()}).eq('id', me.id);
      invite = false; aviso = 'Acesso ativado. Bem-vindo(a) à EAMSP!'; boot(); return;
    }
    if (recovery) {
      r = await sb.auth.updateUser({password: d.get('s')});
      if (r.error) return msg(r.error.message);
      recovery = false; aviso = 'Senha alterada com sucesso.'; boot(); return;
    }
    if (authMode === 'in') { r = await sb.auth.signInWithPassword({email: d.get('e'), password: d.get('s')}); if (r.error) msg('E-mail ou senha incorretos.'); }
    if (authMode === 'rs') {
      r = await sb.auth.resetPasswordForEmail(d.get('e'), {redirectTo: location.origin + location.pathname});
      msg(r.error ? r.error.message : 'Se o e-mail estiver cadastrado, você receberá um link para criar uma nova senha.');
    }
  };
}

/* ---------- Telas ---------- */
function reembProva(p){
  if (!admin) return '';
  var rs = R.filter(function(r){return r.prova_id === p.id});
  if (!rs.length) return '<div style="flex-basis:100%"><small style="color:var(--mu)">Nenhum reembolso solicitado para esta prova.</small></div>';
  var tot = 0, ids = {};
  rs.forEach(function(r){ tot += Number(r.valor); ids[r.atleta_id] = 1; });
  var h = '<details style="flex-basis:100%"><summary style="cursor:pointer;color:var(--g);font-weight:600">' + Object.keys(ids).length + ' atleta(s) pediram reembolso · ' + money(tot) + '</summary>';
  rs.slice().sort(function(a, b){return ((a.perfis && a.perfis.nome) || '').localeCompare((b.perfis && b.perfis.nome) || '')}).forEach(function(r){
    var c = r.status == 'recusado' || r.status == 'cancelado' ? 'b' : r.status == 'pendente' ? 'w' : '';
    h += '<div class="rw" style="display:flex;gap:8px;align-items:center;padding:4px 0;font-size:14px"><span style="flex:1">' + esc((r.perfis && r.perfis.nome) || 'Sem nome') + ' · ' + money(r.valor) + ' <small style="color:var(--mu)">' + esc(r.descricao) + '</small></span><span class="tag ' + c + '">' + STL[r.status] + '</span></div>';
  });
  return h + '</details>';
}
function viewCal(){
  var h = '<h2>Calendário de provas</h2>';
  if (admin) h += '<form id="f"><label>Prova<input name="n" required></label><label>Data<input type="date" name="d" required></label><label>Local<input name="l"></label><label>Distância<input name="k" placeholder="10 km"></label><label>Inscrição até<input type="date" name="i"></label><label>Link de inscrição<input type="url" name="u" placeholder="https://..." pattern="https?://.+"></label><button class="btn">Adicionar prova</button></form>';
  var m = '';
  if (!P.length) h += '<p class="empty">Nenhuma prova cadastrada' + (admin ? '. Adicione a primeira acima.' : ' ainda.') + '</p>';
  P.forEach(function(p){
    var ym = p.data.slice(0,7);
    if (ym !== m) { m = ym; h += '<div class="mes">' + MES[+ym.slice(5)-1] + ' de ' + ym.slice(0,4) + '</div>'; }
    var n = days(p.data), ins = p.inscricao_ate ? (days(p.inscricao_ate) < 0 ? 'Inscrições encerradas' : 'Inscrição até ' + br(p.inscricao_ate)) : '';
    h += '<div class="item"><div class="date">' + p.data.slice(8) + '<small>' + MES[+p.data.slice(5,7)-1].slice(0,3) + '</small></div><div class="info"><b>' + esc(p.nome) + '</b><small>' + esc([p.local, p.distancia, ins].filter(Boolean).join(' • ')) + '</small></div>' + (n < 0 ? '<span class="tag">Realizada</span>' : '<span class="tag ' + (n <= 14 ? 'w' : '') + '">' + (n == 0 ? 'Hoje' : 'em ' + n + ' d') + '</span>') + (n >= 0 && p.link_inscricao && /^https?:\/\//i.test(p.link_inscricao) ? '<a class="btn s" href="' + esc(p.link_inscricao) + '" target="_blank" rel="noopener noreferrer" style="text-decoration:none;display:inline-block">Inscrever-se</a>' : '') + (admin ? '<button class="btn s x" data-lk="' + esc(p.id) + '">Link</button><button class="btn s x" data-delp="' + esc(p.id) + '">Excluir</button>' : '') + reembProva(p) + '</div>';
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
  h += '<form id="f2"><label>O que renovar<select name="tp"><option value="atestado">Atestado</option><option value="anuidade">Anuidade</option></select></label><label>Nova validade<input type="date" name="v" required min="' + today() + '"></label><label>Comprovante em PDF (até 5 MB)<input type="file" name="a" accept="application/pdf,.pdf"' + (EXIGIR_ANEXO ? ' required' : '') + '></label><button class="btn">Solicitar renovação</button></form>';
  if (!mine.length) h += '<p class="empty">Nenhuma solicitação de renovação.</p>';
  mine.forEach(function(x){
    var c = x.status == 'recusada' || x.status == 'cancelada' ? 'b' : x.status == 'pendente' ? 'w' : '';
    h += '<div class="item"><div class="info"><b>' + (x.tipo == 'atestado' ? 'Atestado' : 'Anuidade') + ' até ' + br(x.nova_validade) + '</b><small>Solicitada em ' + br(x.criado_em.slice(0,10)) + (x.status == 'recusada' && x.motivo_decisao ? ' • Motivo: ' + esc(x.motivo_decisao) : '') + '</small></div><span class="tag ' + c + '">' + RTL[x.status] + '</span>' + (x.anexo_path || x.status == 'pendente' ? '<div class="acts">' + pdfBtn(x) + (x.status == 'pendente' ? '<button class="btn s x" data-rn="cancelada|' + x.id + '">Cancelar</button>' : '') + '</div>' : '') + '</div>';
  });
  return h;
}
function viewRen(){
  var pend = REN.filter(function(x){return x.status == 'pendente'}), done = REN.filter(function(x){return x.status != 'pendente'}).slice(0, 15);
  var h = '<h2>Renovações de atestado e anuidade</h2><p class="sum">Confira o comprovante fora do sistema e valide. A nova validade só é aplicada ao aprovar.</p>';
  if (!pend.length) h += '<p class="empty">Nenhuma renovação aguardando validação.</p>';
  pend.forEach(function(x){
    var a = ATL.filter(function(y){return y.id === x.atleta_id})[0], cur = a ? (x.tipo == 'atestado' ? a.atestado_validade : a.anuidade_ate) : null;
    h += '<div class="item"><div class="info"><b>' + esc(x.perfis && x.perfis.nome || 'Sem nome') + ' · ' + (x.tipo == 'atestado' ? 'Atestado' : 'Anuidade') + '</b><small>Nova validade ' + br(x.nova_validade) + ' • atual: ' + (cur ? br(cur) : 'sem registro') + '</small></div><div class="acts">' + pdfBtn(x) + (x.atleta_id === me.id ? '<span class="tag w">Aguarda outro gestor</span><button class="btn s x" data-rn="cancelada|' + x.id + '">Cancelar</button>' : '<button class="btn s g" data-rn="aprovada|' + x.id + '">Aprovar</button><button class="btn s x" data-rn="recusada|' + x.id + '">Recusar</button>') + '</div></div>';
  });
  if (done.length) h += '<div class="mes">Últimas decisões</div>';
  done.forEach(function(x){
    var c = x.status == 'aprovada' ? '' : 'b';
    h += '<div class="item"><div class="info"><b>' + esc(x.perfis && x.perfis.nome || 'Sem nome') + ' · ' + (x.tipo == 'atestado' ? 'Atestado' : 'Anuidade') + ' até ' + br(x.nova_validade) + '</b><small>' + (x.motivo_decisao ? 'Motivo: ' + esc(x.motivo_decisao) : '') + '</small></div><span class="tag ' + c + '">' + RTL[x.status] + '</span>' + (x.anexo_path ? '<div class="acts">' + pdfBtn(x) + '</div>' : '') + '</div>';
  });
  return h;
}
function viewUsr(){
  return '<h2>Usuários e funções</h2><p class="sum">Atleta: usa os próprios dados. Gestão: valida renovações e reembolsos e cadastra provas. Administrador: tudo isso e atribui as funções. A pessoa precisa sair e entrar de novo para a nova função valer.</p><label style="margin-bottom:10px">Buscar por nome ou e-mail<input id="uq" autocomplete="off"></label><div id="ulist"></div>';
}
function usrList(){
  var q = ($('#uq').value || '').trim().toLowerCase();
  var l = USR.filter(function(u){return !q || (u.nome || '').toLowerCase().indexOf(q) >= 0 || (u.email || '').toLowerCase().indexOf(q) >= 0});
  var h = '<p class="sum">' + l.length + ' usuário(s)' + (l.length > 100 ? ' (mostrando 100)' : '') + '</p>';
  l.slice(0, 100).forEach(function(u){
    h += '<div class="item"><div class="info"><b>' + esc(u.nome || 'Sem nome') + (u.id === me.id ? ' (você)' : '') + '</b><small>' + esc(u.email || 'sem e-mail') + '</small></div><select aria-label="Função de ' + esc(u.nome || 'usuário') + '">' +
      ['atleta', 'gestao', 'admin'].map(function(p){return '<option value="' + p + '"' + (p === u.papel ? ' selected' : '') + '>' + PAP[p] + '</option>'}).join('') +
      '</select><label style="flex-direction:row;align-items:center;gap:6px"><input type="checkbox"' + (u.atleta ? ' checked' : '') + '> Atleta</label><button class="btn s g" data-pp="' + esc(u.id) + '">Salvar</button></div>';
  });
  $('#ulist').innerHTML = h;
}
function initUsr(){ $('#uq').oninput = usrList; usrList(); }
function viewReb(){
  var h = '<h2>' + (admin ? 'Solicitações de reembolso' : 'Meus reembolsos') + '</h2>';
  if (eAtl) {
    if (!prof.nome) h += '<p class="empty">Preencha seu nome em "Meus dados" antes de pedir reembolso.</p>';
    else {
      h += '<form id="f"><label>Prova<select name="p"><option value="">Sem prova</option>' + opts(P, function(x){return x.nome}) + '</select></label><label>Descrição<input name="t" placeholder="Inscrição, transporte…" required></label><label>Valor (R$)<input type="number" name="v" step="0.01" min="0.01" required></label><label>Comprovante em PDF (até 5 MB)<input type="file" name="c" accept="application/pdf,.pdf"' + (EXIGIR_ANEXO ? ' required' : '') + '></label><button class="btn">Solicitar reembolso</button></form>';
    }
  }
  if (admin) {
    var tot = {pendente:0, aprovado:0, pago:0};
    R.forEach(function(r){ if (tot[r.status] !== undefined) tot[r.status] += Number(r.valor); });
    h += '<p class="sum">Pendente ' + money(tot.pendente) + ' · Aprovado a pagar ' + money(tot.aprovado) + ' · Pago ' + money(tot.pago) + '</p>';
  }
  if (!R.length) h += '<p class="empty">Nenhuma solicitação até agora.</p>';
  R.forEach(function(r){
    var c = r.status == 'recusado' || r.status == 'cancelado' ? 'b' : r.status == 'pendente' ? 'w' : '';
    var nome = r.perfis && r.perfis.nome ? r.perfis.nome : 'Sem nome', own = r.atleta_id === me.id;
    h += '<div class="item"><div class="info"><b>' + (admin ? esc(nome) + (own ? ' (você)' : '') + ' · ' : '') + money(r.valor) + '</b><small>' + esc(r.descricao) + (r.provas ? ' • ' + esc(r.provas.nome) : '') + ' • ' + br(r.criado_em.slice(0,10)) + (r.status == 'recusado' && r.motivo_decisao ? ' • Motivo: ' + esc(r.motivo_decisao) : '') + '</small></div><span class="tag ' + c + '">' + STL[r.status] + '</span><div class="acts">' + pdfBtn(r) +
      (admin && !own && r.status == 'pendente' ? '<button class="btn s g" data-st="aprovado|' + r.id + '">Aprovar</button><button class="btn s x" data-st="recusado|' + r.id + '">Recusar</button>' : '') +
      (admin && !own && r.status == 'aprovado' ? '<button class="btn s g" data-st="pago|' + r.id + '">Marcar como pago</button>' : '') +
      (own && r.status == 'pendente' ? '<span class="tag w">Aguarda outro gestor</span>' : '') + (own && r.status == 'pendente' ? '<button class="btn s x" data-st="cancelado|' + r.id + '">Cancelar</button>' : '') + '</div></div>';
  });
  return h;
}

/* ---------- Dados ---------- */
async function refresh(){
  var pr = await sb.from('perfis').select('*').eq('id', me.id).single();
  if (pr.error) return fail(pr.error);
  prof = pr.data; admin = prof.papel === 'gestao' || prof.papel === 'admin'; sup = prof.papel === 'admin'; realAdmin = admin; realSup = sup;
  var a = await Promise.all([
    sb.from('provas').select('*').order('data'),
    sb.from('reembolsos').select('*, perfis(nome), provas(nome)').order('criado_em', {ascending: false}),
    admin ? sb.from('perfis').select('*').eq('atleta', true) : Promise.resolve({data: []}),
    sb.from('renovacoes').select('*, perfis(nome)').order('criado_em', {ascending: false}),
    sup ? sb.from('perfis').select('*').order('nome') : Promise.resolve({data: []})
  ]);
  for (var i = 0; i < a.length; i++) if (a[i].error) return fail(a[i].error);
  P = a[0].data; R = a[1].data; ATL = a[2].data; REN = a[3].data; USR = a[4].data; render();
}
function render(){
  admin = realAdmin; sup = realSup; eAtl = !!prof.atleta;
  if (!realSup) sim = '';
  var _R = R, _REN = REN;
  if (sim) {
    sup = false; admin = sim === 'gestao';
    if (sim === 'atleta') { eAtl = true; R = R.filter(function(x){return x.atleta_id === me.id}); REN = REN.filter(function(x){return x.atleta_id === me.id}); }
  }
  var np = REN.filter(function(x){return x.status == 'pendente'}).length, nr = R.filter(function(x){return x.status == 'pendente'}).length;
  var tabs = admin ? [['cal','Calendário'],['ath','Atletas'],['ren','Renovações' + (np ? ' (' + np + ')' : '')],['reb','Reembolsos' + (nr ? ' (' + nr + ')' : '')]].concat(eAtl ? [['me','Meus dados']] : []).concat(sup ? [['usr','Usuários']] : []) : [['cal','Calendário'],['me','Meus dados'],['reb','Reembolsos']];
  if (!tabs.some(function(t){return t[0] == tab})) tab = 'cal';
  $('#nav').innerHTML = tabs.map(function(t){return '<button data-t="' + t[0] + '"' + (t[0] == tab ? ' class="on"' : '') + '>' + t[1] + '</button>'}).join('');
  $('#role').textContent = (sim ? 'Simulando a visão de ' + (sim === 'gestao' ? 'gestão' : 'atleta') : realSup ? 'Acesso de administrador' : realAdmin ? 'Acesso de gestão' : 'Acesso de atleta') + (prof.nome ? ' · ' + prof.nome : '');
  $('#out').hidden = false; $('#sim').hidden = !realSup; $('#sim').value = sim;
  $('#app').innerHTML = (sim ? '<div class="al" role="status">Modo simulação: você está vendo a tela de ' + (sim === 'gestao' ? 'gestão' : 'atleta') + ', somente leitura.</div>' : '') + (aviso ? '<div class="al" role="status" style="border-color:#0B7A64">' + esc(aviso) + '</div>' : '') + ({cal: viewCal, ath: viewAth, me: viewMine, ren: viewRen, reb: viewReb, usr: viewUsr})[tab]();
  if (tab == 'usr') initUsr();
  R = _R; REN = _REN;
  var f = $('#f');
  if (f) f.onsubmit = async function(e){
    e.preventDefault(); if (sim) return alert(MSGSIM); var d = new FormData(f), r;
    if (tab == 'cal') r = await sb.from('provas').insert({nome: d.get('n'), data: d.get('d'), local: d.get('l'), distancia: d.get('k'), inscricao_ate: d.get('i') || null, link_inscricao: d.get('u') || null});
    if (tab == 'me') r = await sb.from('perfis').update({nome: d.get('n').trim()}).eq('id', me.id);
    if (tab == 'reb') {
      var an = await prepararAnexo(d.get('c'));
      if (an.err) return alert(an.err);
      r = await sb.from('reembolsos').insert({atleta_id: me.id, prova_id: d.get('p') || null, descricao: d.get('t'), valor: Number(d.get('v')), status: 'pendente', anexo_path: an.path});
      if (r.error && an.path) await sb.storage.from('anexos').remove([an.path]);
    }
    if (r && r.error) return fail(r.error);
    refresh();
  };
  var f2 = $('#f2');
  if (f2) f2.onsubmit = async function(e){
    e.preventDefault(); if (sim) return alert(MSGSIM); var d = new FormData(f2);
    var an = await prepararAnexo(d.get('a'));
    if (an.err) return alert(an.err);
    var r = await sb.from('renovacoes').insert({atleta_id: me.id, tipo: d.get('tp'), nova_validade: d.get('v'), status: 'pendente', anexo_path: an.path});
    if (r.error) { if (an.path) await sb.storage.from('anexos').remove([an.path]); return fail(r.error); }
    refresh();
  };
}

document.addEventListener('click', async function(e){
  var b = e.target.closest('button'); if (!b) return;
  if (b.dataset.am) { authMode = b.dataset.am; showAuth(); return; }
  if (b.id === 'out') { await sb.auth.signOut(); return; }
  if (b.dataset.t) { tab = b.dataset.t; aviso = ''; refresh(); return; }
  if (b.dataset.pdf) { await abrirAnexo(b.dataset.pdf); return; }
  if (sim && (b.dataset.delp || b.dataset.lk || b.dataset.st || b.dataset.rn || b.dataset.pp)) { alert(MSGSIM); return; }
  var r;
  if (b.dataset.delp) { if (!confirm('Excluir esta prova?')) return; r = await sb.from('provas').delete().eq('id', b.dataset.delp); }
  else if (b.dataset.st) {
    var p = b.dataset.st.split('|'), u = {status: p[0]};
    if (p[0] === 'recusado') { u.motivo_decisao = (prompt('Motivo da recusa (obrigatório):') || '').trim(); if (!u.motivo_decisao) return; }
    else if (p[0] === 'aprovado' && !confirm('Aprovar este reembolso?')) return;
    r = await sb.from('reembolsos').update(u).eq('id', p[1]);
  }
  else if (b.dataset.lk) {
    var pv = P.filter(function(x){return x.id === b.dataset.lk})[0];
    var lk = prompt('Link de inscrição (começa com https://). Deixe em branco para remover:', pv && pv.link_inscricao || '');
    if (lk === null) return;
    lk = lk.trim();
    if (lk && !/^https?:\/\/\S+$/i.test(lk)) { alert('Informe um link que comece com http:// ou https://'); return; }
    r = await sb.from('provas').update({link_inscricao: lk || null}).eq('id', b.dataset.lk);
  }
  else if (b.dataset.pp) {
    var row = b.closest('.item'), sel = row.querySelector('select'), chk = row.querySelector('input[type=checkbox]'), alvo = USR.filter(function(u){return u.id === b.dataset.pp})[0];
    if (!alvo) return;
    var mudaPapel = sel.value !== alvo.papel, mudaAtleta = chk.checked !== !!alvo.atleta;
    if (!mudaPapel && !mudaAtleta) return;
    var txt = 'Salvar as alterações de ' + (alvo.nome || alvo.email) + '?' + (mudaPapel ? '\nFunção: ' + PAP[sel.value] + (sel.value === 'admin' ? ' (administradores atribuem funções a qualquer usuário)' : '') : '') + (mudaAtleta ? '\nAtleta: ' + (chk.checked ? 'sim' : 'não') : '') + (alvo.id === me.id ? '\nAtenção: é a sua própria conta.' : '');
    if (!confirm(txt)) return;
    r = mudaPapel ? await sb.rpc('definir_papel', {alvo: b.dataset.pp, novo: sel.value}) : {};
    if (!r.error && mudaAtleta) r = await sb.rpc('definir_atleta', {alvo: b.dataset.pp, valor: chk.checked});
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
  if (HASH) { history.replaceState(null, '', location.pathname + location.search); HASH = ''; }
  if (ENTRADA === 'signup' && me) { aviso = 'E-mail confirmado! Bem-vindo(a) à EAMSP. Complete seus dados na aba "Meus dados".'; tab = 'me'; ENTRADA = ''; }
  if (recovery || invite || !me) { prof = null; showAuth(); } else { await refresh(); }
}
(function(){
  if (typeof SUPABASE_URL === 'undefined' || SUPABASE_URL.indexOf('SEU-PROJETO') >= 0) {
    $('#app').innerHTML = '<p class="empty">Falta configurar o sistema: abra o arquivo config.js e cole a URL e a chave pública do seu projeto Supabase.</p>'; return;
  }
  sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  $('#sim').onchange = function(){ sim = this.value; render(); };
  sb.auth.onAuthStateChange(function(ev, s){
    if (ev === 'PASSWORD_RECOVERY') recovery = true;
    if (['INITIAL_SESSION', 'SIGNED_IN', 'SIGNED_OUT', 'PASSWORD_RECOVERY'].indexOf(ev) < 0) return;
    if (ev === 'SIGNED_IN' && me && s && s.user.id === me.id) return;
    setTimeout(boot, 0);
  });
})();
