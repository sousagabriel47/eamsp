var HASH = location.hash || '';
var ENTRADA = /type=invite/.test(HASH) ? 'invite' : /type=signup/.test(HASH) ? 'signup' : /type=recovery/.test(HASH) ? 'recovery' : '';
var ERRO = /error(_code|_description)?=/.test(HASH);
var sb, me = null, prof = null, admin = false, sup = false, sim = '', realAdmin = false, realSup = false, eAtl = false, USR = [], P = [], ATL = [], R = [], REN = [], tab = 'cal', authMode = 'in', editId = '', SEN = [], loginMsg = '', IMP = {rows: [], erros: [], res: [], busy: false}, recovery = false, invite = (ENTRADA === 'invite'), aviso = '';
var MES = ['janeiro','fevereiro','março','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro'];
function dig(t){ return String(t == null ? '' : t).replace(/\D/g, ''); }
function cpfValido(c){
  if (!/^\d{11}$/.test(c) || /^(\d)\1{10}$/.test(c)) return false;
  function d(n){ var t = 0; for (var i = 0; i < n; i++) t += Number(c[i]) * (n + 1 - i); var r = (t * 10) % 11; return r === 10 ? 0 : r; }
  return d(9) === Number(c[9]) && d(10) === Number(c[10]);
}
function fmtCpf(c){ return c ? String(c).replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, '$1.$2.$3-$4') : ''; }
function maskCpf(c){ return c && c.length === 11 ? '***.' + c.slice(3, 6) + '.' + c.slice(6, 9) + '-**' : ''; }
function fmtTel(t){ t = dig(t); if (t.length === 11) return t.replace(/^(\d{2})(\d{5})(\d{4})$/, '($1) $2-$3'); if (t.length === 10) return t.replace(/^(\d{2})(\d{4})(\d{4})$/, '($1) $2-$3'); return t; }
function normTel(t){ t = dig(t); if ((t.length === 12 || t.length === 13) && t.indexOf('55') === 0) t = t.slice(2); return t; }
function parseData(x){
  x = String(x || '').trim(); if (!x) return {v: ''};
  var m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(x), iso = x;
  if (m) iso = m[3] + '-' + ('0' + m[2]).slice(-2) + '-' + ('0' + m[1]).slice(-2);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(iso)) return {erro: 'data inválida'};
  var dt = new Date(iso + 'T12:00:00Z');
  if (isNaN(dt.getTime()) || dt.toISOString().slice(0, 10) !== iso) return {erro: 'data inválida'};
  return {v: iso};
}
function lerCadastro(d, comAdesao){
  var nome = String(d.get('n') || '').trim(), cp = dig(d.get('cp')), tl = normTel(d.get('tl')), nc = d.get('nc') || '', ad = d.get('ad') || '';
  if (!nome) return {erro: 'Informe o nome.'};
  if (cp && !cpfValido(cp)) return {erro: 'CPF inválido.'};
  if (tl && !/^\d{10,11}$/.test(tl)) return {erro: 'Telefone inválido: informe DDD e número.'};
  if (nc && nc >= today()) return {erro: 'A data de nascimento deve ser anterior a hoje.'};
  if (comAdesao && ad && ad > today()) return {erro: 'A data de adesão não pode ser futura.'};
  if (comAdesao && ad && nc && ad < nc) return {erro: 'A adesão não pode ser anterior ao nascimento.'};
  var dados = {nome: nome, cpf: cp || null, telefone: tl || null, data_nascimento: nc || null};
  if (comAdesao) dados.data_adesao = ad || null;
  return {dados: dados};
}
function formCadastro(u, comAdesao){
  return '<form id="f"><label>Nome<input name="n" required value="' + esc(u.nome) + '"></label><label>CPF<input name="cp" inputmode="numeric" placeholder="000.000.000-00" value="' + esc(fmtCpf(u.cpf)) + '"></label><label>Telefone (com DDD)<input name="tl" inputmode="tel" placeholder="(11) 90000-0000" value="' + esc(fmtTel(u.telefone)) + '"></label><label>Data de nascimento<input type="date" name="nc" max="' + today() + '" value="' + esc(u.data_nascimento || '') + '"></label>' +
    (comAdesao ? '<label>Data de adesão à equipe<input type="date" name="ad" max="' + today() + '" value="' + esc(u.data_adesao || '') + '"></label>'
               : '<label>Data de adesão à equipe<input readonly value="' + esc(u.data_adesao ? br(u.data_adesao) : 'Definida pela gestão') + '"></label>') +
    '<button class="btn">Salvar</button>' + (comAdesao ? '<button type="button" class="btn x" data-edc="1">Cancelar</button>' : '') + '</form>';
}
function baixar(nome, texto){
  var a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob(['\uFEFF' + texto], {type: 'text/csv;charset=utf-8'}));
  a.download = nome; document.body.appendChild(a); a.click(); a.remove();
}
function parseCSV(t){
  t = String(t).replace(/^\uFEFF/, '');
  var first = t.split(/\r?\n/)[0] || '', sep = (first.match(/;/g) || []).length >= (first.match(/,/g) || []).length ? ';' : ',';
  var rows = [], row = [], cur = '', q = false;
  function fim(){ row.push(cur); cur = ''; if (row.some(function(x){return x.trim() !== ''})) rows.push(row); row = []; }
  for (var i = 0; i < t.length; i++) {
    var c = t[i];
    if (q) { if (c === '"') { if (t[i + 1] === '"') { cur += '"'; i++; } else q = false; } else cur += c; }
    else if (c === '"') q = true;
    else if (c === sep) { row.push(cur); cur = ''; }
    else if (c === '\n' || c === '\r') { if (c === '\r' && t[i + 1] === '\n') i++; fim(); }
    else cur += c;
  }
  if (cur !== '' || row.length) fim();
  return rows;
}
var ALIAS = {nome:'nome', email:'email', e_mail:'email', papel:'papel', funcao:'papel', atleta:'atleta', cpf:'cpf', telefone:'telefone', celular:'telefone', data_nascimento:'data_nascimento', data_de_nascimento:'data_nascimento', nascimento:'data_nascimento', data_adesao:'data_adesao', data_de_adesao:'data_adesao', adesao:'data_adesao'};
function hn(x){ return String(x).trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, ''); }
function validarCSV(m){
  var rows = [], erros = [];
  if (!m.length) return {rows: rows, erros: ['O arquivo está vazio.']};
  var cab = m[0].map(function(x){return ALIAS[hn(x)] || ''});
  if (cab.indexOf('nome') < 0 || cab.indexOf('email') < 0) return {rows: rows, erros: ['O cabeçalho precisa ter as colunas nome e email.']};
  if (m.length - 1 > 500) return {rows: rows, erros: ['O arquivo tem mais de 500 linhas. Divida em arquivos menores.']};
  var emails = {}, cpfs = {};
  m.slice(1).forEach(function(l, k){
    var o = {}; cab.forEach(function(c, j){ if (c) o[c] = (l[j] || '').trim(); });
    var n = k + 2, email = (o.email || '').toLowerCase(), papel = (o.papel || 'atleta').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, ''), at = (o.atleta || 'sim').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
    var cp = dig(o.cpf), tl = normTel(o.telefone), nc = parseData(o.data_nascimento), ad = parseData(o.data_adesao), er = '';
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) er = 'e-mail inválido';
    else if (emails[email]) er = 'e-mail repetido no arquivo';
    else if (!o.nome) er = 'nome vazio';
    else if (['atleta', 'gestao', 'admin'].indexOf(papel) < 0) er = 'papel inválido (' + papel + ')';
    else if (['sim', 's', 'true', '1', 'nao', 'n', 'false', '0'].indexOf(at) < 0) er = 'valor inválido em atleta';
    else if (cp && !cpfValido(cp)) er = 'CPF inválido';
    else if (cp && cpfs[cp]) er = 'CPF repetido no arquivo';
    else if (tl && !/^\d{10,11}$/.test(tl)) er = 'telefone inválido (DDD + número)';
    else if (nc.erro) er = 'data de nascimento inválida';
    else if (nc.v && nc.v >= today()) er = 'nascimento deve ser anterior a hoje';
    else if (ad.erro) er = 'data de adesão inválida';
    else if (ad.v && ad.v > today()) er = 'adesão não pode ser futura';
    else if (ad.v && nc.v && ad.v < nc.v) er = 'adesão anterior ao nascimento';
    if (er) { erros.push('linha ' + n + ': ' + er + (email ? ' (' + email + ')' : '')); return; }
    emails[email] = 1; if (cp) cpfs[cp] = 1;
    rows.push({nome: o.nome, email: email, papel: papel, atleta: papel === 'atleta' ? true : ['sim', 's', 'true', '1'].indexOf(at) >= 0, cpf: cp, telefone: tl, data_nascimento: nc.v, data_adesao: ad.v});
  });
  return {rows: rows, erros: erros};
}
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
var STT = {ativo:'Ativo', inativo:'Inativo', bloqueado:'Bloqueado'};
var PAP = {atleta:'Atleta', gestao:'Gestão', admin:'Administrador'};
var RTL = {pendente:'Pendente', aprovada:'Aprovada', recusada:'Recusada', cancelada:'Cancelada'};
var STL = {pendente:'Pendente', aprovado:'Aprovado', pago:'Pago', recusado:'Recusado', cancelado:'Cancelado'};
function $(s){return document.querySelector(s)}
function esc(s){return String(s==null?'':s).replace(/[&<>"]/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]})}
function today(){var d=new Date();return d.getFullYear()+'-'+('0'+(d.getMonth()+1)).slice(-2)+'-'+('0'+d.getDate()).slice(-2)}   // data LOCAL (não UTC)
function days(d){return Math.round((new Date(d+'T12:00')-new Date(today()+'T12:00'))/864e5)}
function br(d){var p=String(d).split('-');return p[2]+'/'+p[1]+'/'+p[0]}
function money(v){return Number(v).toLocaleString('pt-BR',{style:'currency',currency:'BRL'})}
function st(d){if(!d)return['Sem registro','b'];var n=days(d);if(n<0)return['Vencido há '+(-n)+' d','b'];if(n<=30)return['Vence em '+n+' d','w'];return['Válido até '+br(d),'']}
function tag(p){return'<span class="tag '+p[1]+'">'+p[0]+'</span>'}
function opts(a,f){return a.map(function(x){return'<option value="'+esc(x.id)+'">'+esc(f(x))+'</option>'}).join('')}
function fail(e){
  var m = (e && e.message) || String(e), c = e && e.code;
  if (c === '23505' && /perfis_cpf_unico/.test(m)) m = 'Este CPF já está cadastrado.';
  else if (c === '23505') m = 'Você já tem uma solicitação pendente desse tipo.';
  else if (/perfis_cpf_check/.test(m)) m = 'CPF inválido.';
  else if (/perfis_telefone_check/.test(m)) m = 'Telefone inválido (informe DDD e número).';
  alert('Não foi possível concluir: ' + m);
}
async function msgFuncao(err){
  try { var j = await err.context.json(); return j.erro || err.message; } catch (x) { return err.message || 'Falha ao falar com o servidor.'; }
}
function msg(t){var m=$('#msg');if(m)m.textContent=t}

/* ---------- Acesso (login) ---------- */
function viewAuth(){
  var t = {in:'Entrar', rs:'Recuperar senha'}, h = '<h2>' + t[authMode] + '</h2>';
  if (authMode === 'rs') h += '<p class="sum">A redefinição de senha precisa ser aprovada por um administrador. Informe seu e-mail para abrir a solicitação.</p>';
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
  if (loginMsg) { msg(loginMsg); loginMsg = ''; }
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
    if (authMode === 'in') {
      var lg = await sb.functions.invoke('entrar', {body: {email: d.get('e'), senha: d.get('s')}});
      if (lg.error) {
        var cj = null; try { cj = await lg.error.context.json(); } catch (x) {}
        return msg(((cj && cj.erro) || 'Não foi possível entrar agora. Tente de novo.') + (cj && cj.restantes ? ' Restam ' + cj.restantes + ' tentativa(s) antes do bloqueio.' : ''));
      }
      var ses = await sb.auth.setSession(lg.data.session);
      if (ses.error) msg(ses.error.message);
    }
    if (authMode === 'rs') {
      r = await sb.rpc('solicitar_reset_senha', {p_email: d.get('e')});
      msg(r.error ? r.error.message : 'Solicitação registrada. Um administrador vai analisar o pedido e, se aprovar, você receberá o link por e-mail.');
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
  ATL.forEach(function(a){[['atestado', a.atestado_validade], ['anuidade', a.anuidade_ate]].forEach(function(x){var t = st(x[1]); if (t[1]) al.push('<div class="al ' + (t[1] == 'b' ? 'bad' : '') + '"><b>' + esc(a.nome || 'Sem nome') + '</b>: ' + x[0] + ' · ' + t[0] + '</div>');});});
  if (al.length) h += '<div class="alerts">' + al.join('') + '</div>';
  var ed = editId ? ATL.filter(function(x){return x.id === editId})[0] : null;
  if (ed) h += '<h2>Cadastro de ' + esc(ed.nome || 'atleta') + '</h2>' + formCadastro(ed, true);
  if (!ATL.length) h += '<p class="empty">Nenhum atleta cadastrado ainda.</p>';
  ATL.slice().sort(function(a, b){return (a.nome || '').localeCompare(b.nome || '')}).forEach(function(a){
    var det = ['Adesão: ' + (a.data_adesao ? br(a.data_adesao) : '—'), 'Nasc.: ' + (a.data_nascimento ? br(a.data_nascimento) : '—'), 'Tel.: ' + (a.telefone ? fmtTel(a.telefone) : '—'), 'CPF: ' + (a.cpf ? maskCpf(a.cpf) : '—')].join(' • ');
    h += '<div class="item"><div class="info"><b>' + esc(a.nome || 'Sem nome') + '</b> ' + (a.status && a.status !== 'ativo' ? tag([STT[a.status], 'b']) : '') + '<small>' + esc(det) + '</small><small>Atestado</small> ' + tag(st(a.atestado_validade)) + ' <small>Anuidade</small> ' + tag(st(a.anuidade_ate)) + '</div><div class="acts"><button class="btn s x" data-ed="' + esc(a.id) + '">Cadastro</button></div></div>';
  });
  return h;
}
function viewMine(){
  var mine = REN.filter(function(x){return x.atleta_id === me.id});
  var h = '<h2>Meus dados</h2>' + formCadastro(prof, false);
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
  function sel(cls, op, atual, nomes){ return '<select class="' + cls + '">' + op.map(function(p){return '<option value="' + p + '"' + (p === atual ? ' selected' : '') + '>' + nomes[p] + '</option>'}).join('') + '</select>'; }
  l.slice(0, 100).forEach(function(u){
    h += '<div class="item"><div class="info"><b>' + esc(u.nome || 'Sem nome') + (u.id === me.id ? ' (você)' : '') + '</b><small>' + esc(u.email || 'sem e-mail') + '</small></div>' +
      sel('sp', ['atleta', 'gestao', 'admin'], u.papel, PAP) + sel('ss', ['ativo', 'inativo', 'bloqueado'], u.status || 'ativo', STT) +
      '<label style="flex-direction:row;align-items:center;gap:6px"><input type="checkbox"' + (u.atleta ? ' checked' : '') + '> Atleta</label><button class="btn s g" data-pp="' + esc(u.id) + '">Salvar</button></div>';
  });
  $('#ulist').innerHTML = h;
}
function initUsr(){ $('#uq').oninput = usrList; usrList(); }
function viewConta(){
  return '<h2>Minha conta</h2><div class="item"><div class="info"><b>' + esc(prof.nome || 'Sem nome') + '</b><small>' + esc(me.email) + ' · ' + PAP[prof.papel] + ' · ' + STT[prof.status || 'ativo'] + '</small></div></div><h2>Alterar senha</h2><p class="sum">Use pelo menos 8 caracteres. Ao trocar a senha, os outros aparelhos conectados são desconectados.</p><form id="f" style="max-width:420px;grid-template-columns:1fr"><label>Senha atual<input type="password" name="sa" required autocomplete="current-password"></label><label>Nova senha<input type="password" name="sn" required minlength="8" autocomplete="new-password"></label><label>Repita a nova senha<input type="password" name="sr" required minlength="8" autocomplete="new-password"></label><button class="btn">Alterar senha</button><p id="msg" class="sum"></p></form>';
}
function viewSen(){
  var pend = SEN.filter(function(x){return x.status == 'pendente'}), done = SEN.filter(function(x){return x.status != 'pendente'}).slice(0, 15);
  var h = '<h2>Redefinição de senha</h2><p class="sum">Aprovar envia o link de redefinição ao e-mail da pessoa (uso único). Contas bloqueadas por senhas incorretas são reativadas ao aprovar; contas inativas precisam ser reativadas antes.</p>';
  if (!pend.length) h += '<p class="empty">Nenhuma solicitação aguardando decisão.</p>';
  pend.forEach(function(x){
    var stc = x.perfis && x.perfis.status || 'ativo';
    h += '<div class="item"><div class="info"><b>' + esc(x.perfis && x.perfis.nome || 'Sem nome') + '</b><small>' + esc(x.email) + ' • solicitada em ' + br(x.criado_em.slice(0, 10)) + '</small></div>' + (stc != 'ativo' ? tag([STT[stc], 'b']) : '') + '<div class="acts"><button class="btn s g" data-sn="aprovar|' + x.id + '">Aprovar e enviar link</button><button class="btn s x" data-sn="recusar|' + x.id + '">Recusar</button></div></div>';
  });
  if (done.length) h += '<div class="mes">Últimas decisões</div>';
  done.forEach(function(x){
    h += '<div class="item"><div class="info"><b>' + esc(x.perfis && x.perfis.nome || 'Sem nome') + '</b><small>' + esc(x.email) + (x.motivo_decisao ? ' • Motivo: ' + esc(x.motivo_decisao) : '') + '</small></div><span class="tag ' + (x.status == 'aprovada' ? '' : 'b') + '">' + (x.status == 'aprovada' ? 'Aprovada' : 'Recusada') + '</span></div>';
  });
  return h;
}
function viewImp(){
  var h = '<h2>Importar usuários (CSV)</h2><p class="sum">Cada linha vira um convite por e-mail e já grava o cadastro. Colunas obrigatórias: nome e email. Opcionais: papel (atleta, gestao ou admin), atleta (sim ou nao), cpf, telefone, data_nascimento e data_adesao. Datas em dd/mm/aaaa ou aaaa-mm-dd. Até 500 linhas por arquivo.</p>';
  h += '<div class="acts"><button class="btn s x" data-impmod="1">Baixar modelo CSV</button></div>';
  h += '<label style="margin:10px 0">Arquivo CSV<input type="file" id="csvf" accept=".csv,text/csv"></label>';
  h += '<label style="flex-direction:row;align-items:center;gap:6px;margin-bottom:10px"><input type="checkbox" id="impupd"> Atualizar o cadastro de quem já tem conta (a função não é alterada)</label>';
  if (IMP.rows.length || IMP.erros.length) {
    h += '<p class="sum">' + IMP.rows.length + ' linha(s) válida(s) • ' + IMP.erros.length + ' com problema</p>';
    if (IMP.erros.length) h += '<div class="alerts">' + IMP.erros.slice(0, 30).map(function(e){return '<div class="al bad">' + esc(e) + '</div>'}).join('') + (IMP.erros.length > 30 ? '<div class="al">… e mais ' + (IMP.erros.length - 30) + '</div>' : '') + '</div>';
    IMP.rows.slice(0, 20).forEach(function(r){ h += '<div class="item"><div class="info"><b>' + esc(r.nome) + '</b><small>' + esc(r.email + ' • ' + PAP[r.papel] + (r.cpf ? ' • CPF ' + maskCpf(r.cpf) : '') + (r.data_adesao ? ' • adesão ' + br(r.data_adesao) : '')) + '</small></div></div>'; });
    if (IMP.rows.length > 20) h += '<p class="sum">… e mais ' + (IMP.rows.length - 20) + ' linha(s).</p>';
    if (IMP.rows.length) h += '<div class="acts" style="margin:10px 0"><button class="btn g" data-impgo="1"' + (IMP.busy ? ' disabled' : '') + '>Enviar convites (' + IMP.rows.length + ')</button></div>';
  }
  return h + '<div id="impprog"></div>';
}
function impProg(){
  var el = $('#impprog'); if (!el) return;
  if (!IMP.res.length && !IMP.busy) { el.innerHTML = ''; return; }
  var cont = {}; IMP.res.forEach(function(r){ cont[r.status] = (cont[r.status] || 0) + 1; });
  var h = '<h2>Resultado</h2><p class="sum">' + (IMP.busy ? 'Enviando… ' : 'Concluído. ') + IMP.res.length + ' de ' + IMP.rows.length + ' • ' + Object.keys(cont).map(function(k){return k.replace('_', ' ') + ': ' + cont[k]}).join(' • ') + '</p>';
  IMP.res.filter(function(r){return r.status != 'convidado' && r.status != 'atualizado'}).slice(0, 40).forEach(function(r){ h += '<div class="item"><div class="info"><b>' + esc(r.email) + '</b><small>' + esc(r.detalhe || '') + '</small></div><span class="tag b">' + esc(r.status.replace('_', ' ')) + '</span></div>'; });
  if (!IMP.busy) h += '<div class="acts"><button class="btn s x" data-impdl="1">Baixar resultado (CSV)</button></div>';
  el.innerHTML = h;
}
function initImp(){
  $('#csvf').onchange = async function(e){
    var f = e.target.files[0]; if (!f) return;
    var r = validarCSV(parseCSV(await f.text()));
    IMP = {rows: r.rows, erros: r.erros, res: [], busy: false}; render();
  };
  impProg();
}
async function enviarLote(){
  if (IMP.busy || !IMP.rows.length) return;
  var upd = !!($('#impupd') && $('#impupd').checked);
  if (!confirm('Enviar ' + IMP.rows.length + ' convite(s) por e-mail agora?')) return;
  IMP.busy = true; IMP.res = []; render();
  for (var i = 0; i < IMP.rows.length; i += 10) {
    var parte = IMP.rows.slice(i, i + 10);
    var r = await sb.functions.invoke('convidar-lote', {body: {usuarios: parte, atualizar_existentes: upd}});
    if (r.error) {
      var m = await msgFuncao(r.error);
      IMP.rows.slice(i).forEach(function(x){ IMP.res.push({email: x.email, status: 'nao_enviado', detalhe: m}); });
      break;
    }
    IMP.res = IMP.res.concat(r.data.resultados || []); impProg();
  }
  IMP.busy = false; render(); impProg();
}
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
  prof = pr.data;
  if (prof.status && prof.status !== 'ativo') { loginMsg = prof.status === 'bloqueado' ? 'Conta bloqueada. Procure um administrador.' : 'Conta inativa. Procure a gestão da equipe.'; await sb.auth.signOut(); return; }
  admin = prof.papel === 'gestao' || prof.papel === 'admin'; sup = prof.papel === 'admin'; realAdmin = admin; realSup = sup;
  var a = await Promise.all([
    sb.from('provas').select('*').order('data'),
    sb.from('reembolsos').select('*, perfis(nome), provas(nome)').order('criado_em', {ascending: false}),
    admin ? sb.from('perfis').select('*').eq('atleta', true) : Promise.resolve({data: []}),
    sb.from('renovacoes').select('*, perfis(nome)').order('criado_em', {ascending: false}),
    sup ? sb.from('perfis').select('*').order('nome') : Promise.resolve({data: []}),
    sup ? sb.from('solicitacoes_senha').select('*, perfis(nome,status)').order('criado_em', {ascending: false}).limit(100) : Promise.resolve({data: []})
  ]);
  for (var i = 0; i < a.length; i++) if (a[i].error) return fail(a[i].error);
  P = a[0].data; R = a[1].data; ATL = a[2].data; REN = a[3].data; USR = a[4].data; SEN = a[5].data; render();
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
  var ns = SEN.filter(function(x){return x.status == 'pendente'}).length;
  var tabs = (admin ? [['cal','Calendário'],['ath','Atletas'],['ren','Renovações' + (np ? ' (' + np + ')' : '')],['reb','Reembolsos' + (nr ? ' (' + nr + ')' : '')]].concat(eAtl ? [['me','Meus dados']] : []).concat(sup ? [['usr','Usuários'],['sen','Senhas' + (ns ? ' (' + ns + ')' : '')],['imp','Importar CSV']] : []) : [['cal','Calendário'],['me','Meus dados'],['reb','Reembolsos']]).concat([['conta','Minha conta']]);
  if (!tabs.some(function(t){return t[0] == tab})) tab = 'cal';
  $('#nav').innerHTML = tabs.map(function(t){return '<button data-t="' + t[0] + '"' + (t[0] == tab ? ' class="on"' : '') + '>' + t[1] + '</button>'}).join('');
  $('#role').textContent = (sim ? 'Simulando a visão de ' + (sim === 'gestao' ? 'gestão' : 'atleta') : realSup ? 'Acesso de administrador' : realAdmin ? 'Acesso de gestão' : 'Acesso de atleta') + (prof.nome ? ' · ' + prof.nome : '');
  $('#out').hidden = false; $('#sim').hidden = !realSup; $('#sim').value = sim;
  $('#app').innerHTML = (sim ? '<div class="al" role="status">Modo simulação: você está vendo a tela de ' + (sim === 'gestao' ? 'gestão' : 'atleta') + ', somente leitura.</div>' : '') + (aviso ? '<div class="al" role="status" style="border-color:#0B7A64">' + esc(aviso) + '</div>' : '') + ({cal: viewCal, ath: viewAth, me: viewMine, ren: viewRen, reb: viewReb, usr: viewUsr, conta: viewConta, sen: viewSen, imp: viewImp})[tab]();
  if (tab == 'usr') initUsr();
  if (tab == 'imp') initImp();
  R = _R; REN = _REN;
  var f = $('#f');
  if (f) f.onsubmit = async function(e){
    e.preventDefault(); if (sim) return alert(MSGSIM); var d = new FormData(f), r;
    if (tab == 'conta') {
      var sa = d.get('sa'), sn1 = d.get('sn'), sr = d.get('sr');
      if (sn1 !== sr) return msg('As senhas novas não conferem.');
      if (sn1.length < 8) return msg('A nova senha precisa ter pelo menos 8 caracteres.');
      if (sn1 === sa) return msg('A nova senha deve ser diferente da atual.');
      msg('Aguarde…');
      var ck = await sb.functions.invoke('entrar', {body: {email: me.email, senha: sa, verificar: true}});
      if (ck.error) { var mm = await msgFuncao(ck.error); msg(mm); if (/bloquead/i.test(mm)) setTimeout(refresh, 2500); return; }
      var up = await sb.auth.updateUser({password: sn1});
      if (up.error) return msg(up.error.message);
      await sb.auth.signOut({scope: 'others'});
      f.reset(); msg('Senha alterada. Os outros aparelhos foram desconectados.');
      return;
    }
    if (tab == 'cal') r = await sb.from('provas').insert({nome: d.get('n'), data: d.get('d'), local: d.get('l'), distancia: d.get('k'), inscricao_ate: d.get('i') || null, link_inscricao: d.get('u') || null});
    if (tab == 'me' || tab == 'ath') {
      var cd = lerCadastro(d, tab == 'ath');
      if (cd.erro) return alert(cd.erro);
      r = await sb.from('perfis').update(cd.dados).eq('id', tab == 'ath' ? editId : me.id);
      if (!r.error && tab == 'ath') editId = '';
    }
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
  if (b.dataset.t) { tab = b.dataset.t; aviso = ''; editId = ''; refresh(); return; }
  if (b.dataset.ed) { editId = b.dataset.ed; render(); window.scrollTo(0, 0); return; }
  if (b.dataset.edc) { editId = ''; render(); return; }
  if (b.dataset.impmod) { baixar('modelo_cadastro.csv', 'nome;email;papel;atleta;cpf;telefone;data_nascimento;data_adesao\nMaria Souza;maria@exemplo.com;atleta;sim;529.982.247-25;(11) 98888-7777;15/03/1990;01/02/2024\nJoão Lima;joao@exemplo.com;gestao;sim;;11977776666;1985-07-20;2023-05-10\n'); return; }
  if (b.dataset.impdl) { baixar('resultado_convites.csv', 'email;status;detalhe\n' + IMP.res.map(function(x){return [x.email, x.status, '"' + String(x.detalhe || '').replace(/"/g, '""') + '"'].join(';')}).join('\n')); return; }
  if (b.dataset.impgo) { await enviarLote(); return; }
  if (b.dataset.pdf) { await abrirAnexo(b.dataset.pdf); return; }
  if (sim && (b.dataset.delp || b.dataset.lk || b.dataset.st || b.dataset.rn || b.dataset.pp || b.dataset.sn)) { alert(MSGSIM); return; }
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
    var row = b.closest('.item'), sp = row.querySelector('select.sp'), ss = row.querySelector('select.ss'), chk = row.querySelector('input[type=checkbox]'), alvo = USR.filter(function(u){return u.id === b.dataset.pp})[0];
    if (!alvo) return;
    var mP = sp.value !== alvo.papel, mS = ss.value !== (alvo.status || 'ativo'), mA = chk.checked !== !!alvo.atleta;
    if (!mP && !mS && !mA) return;
    var txt = 'Salvar as alterações de ' + (alvo.nome || alvo.email) + '?' + (mP ? '\nFunção: ' + PAP[sp.value] : '') + (mS ? '\nStatus: ' + STT[ss.value] + (ss.value !== 'ativo' ? ' (a pessoa deixa de entrar no sistema)' : '') : '') + (mA ? '\nAtleta: ' + (chk.checked ? 'sim' : 'não') : '') + (alvo.id === me.id ? '\nAtenção: é a sua própria conta.' : '');
    if (!confirm(txt)) return;
    var mot = null;
    if (mS && ss.value !== 'ativo') { mot = prompt('Motivo (opcional):'); if (mot === null) return; }
    r = {};
    if (mP) r = await sb.rpc('definir_papel', {alvo: b.dataset.pp, novo: sp.value});
    if (!r.error && mS) r = await sb.rpc('definir_status', {alvo: b.dataset.pp, novo: ss.value, motivo: mot || null});
    if (!r.error && mA) r = await sb.rpc('definir_atleta', {alvo: b.dataset.pp, valor: chk.checked});
  }
  else if (b.dataset.sn) {
    var sn = b.dataset.sn.split('|'), mo = '';
    if (sn[0] === 'recusar') { mo = (prompt('Motivo da recusa (obrigatório):') || '').trim(); if (!mo) return; }
    else if (!confirm('Enviar o link de redefinição de senha para esta pessoa?')) return;
    var fr = await sb.functions.invoke('gerir-reset-senha', {body: {id: sn[1], acao: sn[0], motivo: mo, redirectTo: location.origin + location.pathname}});
    r = fr.error ? {error: {message: await msgFuncao(fr.error)}} : {};
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
