var HASH = location.hash || '';
var ENTRADA = /type=invite/.test(HASH) ? 'invite' : /type=signup/.test(HASH) ? 'signup' : /type=recovery/.test(HASH) ? 'recovery' : '';
var ERRO = /error(_code|_description)?=/.test(HASH);
var PART = [], sb, me = null, prof = null, admin = false, sup = false, sim = '', realAdmin = false, realSup = false, eAtl = false, USR = [], P = [], ATL = [], R = [], REN = [], tab = 'cal', authMode = 'in', editId = '', SEN = [], tabIni = true, loginMsg = '', IMP = {rows: [], erros: [], res: [], busy: false}, recovery = false, invite = (ENTRADA === 'invite'), aviso = '';
var SEL = {}, LOTE_DATA = '';
var DASH = null, dashPer = 'mes', DASH_LOADING = false, DASH_ERRO = false, DASH_SEQ = 0, spons = false;
var AV = [], HR = [], previa = null, editRb = '', rbRasc = null;
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
function formCadastro(u, comAdesao, semCancelar){
  return '<form id="f"><label>Nome<input name="n" required value="' + esc(u.nome) + '"></label><label>CPF<input name="cp" inputmode="numeric" placeholder="000.000.000-00" value="' + esc(fmtCpf(u.cpf)) + '"></label><label>Telefone (com DDD)<input name="tl" inputmode="tel" placeholder="(11) 90000-0000" value="' + esc(fmtTel(u.telefone)) + '"></label><label>Data de nascimento<input type="date" name="nc" max="' + today() + '" value="' + esc(u.data_nascimento || '') + '"></label>' +
    (comAdesao ? '<label>Data de adesão à equipe<input type="date" name="ad" max="' + today() + '" value="' + esc(u.data_adesao || '') + '"></label>'
               : '<label>Data de adesão à equipe<input readonly value="' + esc(u.data_adesao ? br(u.data_adesao) : 'Definida pela gestão') + '"></label>') +
    '<button class="btn">Salvar</button>' + (comAdesao && !semCancelar ? '<button type="button" class="btn x" data-edc="1">Cancelar</button>' : '') + '</form>';
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
var PAP = {atleta:'Atleta', gestao:'Gestão', admin:'Administrador', patrocinador:'Patrocinador'};
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
  tabIni = true;
  $('#nav').innerHTML = ''; $('#out').hidden = true; $('#sino').hidden = true; $('#sim').hidden = true; $('#role').textContent = 'Gestão da equipe de corrida';
  if (invite && !me) invite = false;
  $('#app').innerHTML = invite ? viewInvite() : recovery ? viewRecovery() : viewAuth();
  if (loginMsg) { msg(loginMsg); loginMsg = ''; }
  if (ERRO && !me && !invite && !recovery) msg('Este link expirou ou já foi usado. Para recuperar o acesso, use "Esqueci a senha" ou peça um novo convite à gestão.'); ERRO = false;
  var f = $('#f');
  f.onsubmit = async function(e){
    e.preventDefault(); var d = new FormData(f), r; msg('Aguarde…');
    if (invite) {
      r = await sb.auth.updateUser({password: d.get('s'), data: {nome: d.get('n').trim()}});
      if (r.error) return msg(/session/i.test(r.error.message) ? 'O link do convite expirou ou já foi usado. Peça um novo convite à gestão.' : r.error.message);
      await sb.from('perfis').update({nome: d.get('n').trim()}).eq('id', me.id);
      invite = false; aviso = 'Acesso ativado. Bem-vindo(a) à EAMSP!'; boot(); return;
    }
    if (recovery) {
      r = await sb.auth.updateUser({password: d.get('s')});
      if (r.error) return msg(/session/i.test(r.error.message) ? 'O link de redefinição expirou ou já foi usado. Peça uma nova redefinição de senha.' : r.error.message);
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

/* ---------- Funções puras ---------- */
// Pagamento em lote: só aprovado de outro atleta pode ser selecionado.
function lotePodeSelecionar(r, meId){return !!r && r.status === 'aprovado' && r.atleta_id !== meId}
function loteResumo(sel, rs, meId){
  var o = {n: 0, total: 0, ids: []};
  (rs || []).forEach(function(r){ if (sel && sel[r.id] && lotePodeSelecionar(r, meId)) { o.n++; o.total += Number(r.valor); o.ids.push(r.id); } });
  o.total = Math.round(o.total * 100) / 100;
  return o;
}
function loteBarraHtml(resumo, data){
  if (!resumo || !resumo.n) return '';
  return '<div class="lotebar"><b>' + resumo.n + (resumo.n === 1 ? ' selecionado' : ' selecionados') + ' · ' + money(resumo.total) + '</b><label>Data do pagamento<input type="date" id="lotedata" max="' + today() + '" value="' + esc(data) + '"></label><div class="acts"><button class="btn s g" data-lote="1">Marcar como pagos</button><button class="btn s x" data-lotelimpa="1">Limpar seleção</button></div></div>';
}
// Dashboard financeiro de reembolsos.
function periodoDash(chave, hoje){
  var a = Number(hoje.slice(0, 4)), m = Number(hoje.slice(5, 7));
  function ym(y, mm){ return y + '-' + ('0' + mm).slice(-2) + '-01'; }
  if (chave == 'mes') return {de: ym(a, m), ate: hoje};
  if (chave == '3m') { m -= 2; if (m < 1) { m += 12; a--; } return {de: ym(a, m), ate: hoje}; }
  if (chave == 'ano') return {de: a + '-01-01', ate: hoje};
  return {de: null, ate: null};
}
var DASH_SIT = [['pendente', 'Pendente'], ['aprovado', 'A pagar'], ['pago', 'Pago'], ['recusado', 'Recusado']];
function cartoesDash(d){
  var s = (d && d.situacoes) || {};
  return '<div class="dgrid">' + DASH_SIT.map(function(x){
    var v = s[x[0]] || {qtd: 0, valor: 0};
    return '<div class="dcard' + (x[0] == 'aprovado' ? ' hi' : '') + '"><small>' + x[1] + '</small><b>' + money(v.valor) + '</b><span>' + Number(v.qtd) + (Number(v.qtd) == 1 ? ' pedido' : ' pedidos') + '</span></div>';
  }).join('') + '</div>';
}
function mesRotulo(m){ var p = String(m).split('-'); return (MES[Number(p[1]) - 1] || p[1]).slice(0, 3) + '/' + p[0]; }
function barrasMesDash(d){
  var ms = (d && d.meses) || [], mx = 0;
  ms.forEach(function(x){ mx = Math.max(mx, Number(x.solicitado) || 0, Number(x.pago) || 0); });
  function w(v){ v = Number(v) || 0; return mx > 0 && v > 0 ? Math.max(1, Math.round(v / mx * 1000) / 10) : 0; }
  if (!ms.length) return '';
  return '<h3>Por mês</h3><p class="leg"><i class="sw s"></i> Solicitado <i class="sw p"></i> Pago</p>' + ms.map(function(x){
    return '<div class="dmes"><b>' + esc(mesRotulo(x.mes)) + '</b><div class="bar"><span class="s" style="width:' + w(x.solicitado) + '%"></span></div><small>' + money(x.solicitado) + '</small><div class="bar"><span class="p" style="width:' + w(x.pago) + '%"></span></div><small>' + money(x.pago) + '</small></div>';
  }).join('');
}
function rankingProvaDash(d){
  var ps = (d && d.provas) || [];
  if (!ps.length) return '';
  return '<h3>Por prova</h3>' + ps.map(function(x){
    return '<div class="item"><div class="info"><b>' + esc(x.prova || 'Sem prova') + '</b><small>' + Number(x.qtd) + (Number(x.qtd) == 1 ? ' pedido' : ' pedidos') + '</small></div><b>' + money(x.valor) + '</b></div>';
  }).join('');
}
function tempoMedioDash(d){
  var t = d && d.tempo_medio_dias;
  return '<p class="sum">Tempo médio até o pagamento: ' + (t == null ? '—' : String(Math.round(Number(t) * 10) / 10).replace('.', ',') + ' dias') + '</p>';
}
function atletasDash(d){
  if (!d || !d.atletas) return '';
  return '<h3>Por atleta</h3>' + (d.atletas.length ? d.atletas.map(function(x){
    return '<div class="item"><div class="info"><b>' + esc(x.nome || 'Sem nome') + '</b><small>Pediu ' + money(x.pediu) + ' · Recebeu ' + money(x.recebeu) + ' · A receber ' + money(x.a_receber) + '</small></div></div>';
  }).join('') : '<p class="empty">Nenhum atleta no período.</p>');
}
function dashVazio(d){
  var s = (d && d.situacoes) || {};
  return !Object.keys(s).some(function(k){ return Number(s[k] && s[k].qtd) > 0; });
}
function dashEstado(o){
  if (o.loading) return 'carregando';
  if (o.erro) return 'erro';
  if (o.dash == null) return 'carregando';
  return dashVazio(o.dash) ? 'vazio' : 'ok';
}
function dashReset(){ DASH = null; DASH_ERRO = false; DASH_LOADING = false; DASH_SEQ++; }
// Patrocinador que não é atleta não tem provas, reembolsos, renovações, avisos, histórico nem participações próprios: pula essas consultas.
function consultasUsuario(o){ return {dados: !(o.spons && !o.atleta)}; }
function rotuloAcesso(o){
  if (o.sim) return 'Simulando a visão de ' + (o.sim === 'patrocinador' ? 'patrocinador' : o.sim === 'gestao' ? 'gestão' : 'atleta');
  return o.spons ? 'Acesso de patrocinador' : o.realSup ? 'Acesso de administrador' : o.realAdmin ? 'Acesso de gestão' : 'Acesso de atleta';
}
function dashParaPapel(d, simPatro){
  if (!d || !simPatro) return d;
  var o = {}, k;
  for (k in d) if (Object.prototype.hasOwnProperty.call(d, k) && k !== 'atletas') o[k] = d[k];
  return o;
}
function montarAbas(o){
  var ab;
  if (o.admin) {
    ab = [['cal', 'Calendário'], ['ath', 'Atletas'], ['ren', 'Renovações' + (o.np ? ' (' + o.np + ')' : '')], ['reb', 'Reembolsos' + (o.nr ? ' (' + o.nr + ')' : '')], ['dash', 'Dashboard']]
      .concat(o.eAtl ? [['me', 'Atestado e anuidade']] : [])
      .concat(o.sup ? [['usr', 'Usuários'], ['sen', 'Senhas' + (o.ns ? ' (' + o.ns + ')' : '')], ['imp', 'Importar CSV']] : []);
  } else if (o.spons) {
    ab = [['dash', 'Dashboard']].concat(o.eAtl ? [['cal', 'Calendário'], ['me', 'Atestado e anuidade'], ['reb', 'Reembolsos']] : []);
  } else ab = [['cal', 'Calendário'], ['me', 'Atestado e anuidade'], ['reb', 'Reembolsos']];
  return ab.concat([['conta', 'Minha conta']]);
}
// Avisos calculados na hora (vencimentos e pendências). 'texto' já é HTML seguro (nomes escapados).
function avisosCalculados(o){
  var out = [];
  function venc(rot, d, nome){
    var t = st(d); if (!t[1]) return;
    out.push({sev: t[1], texto: (nome ? esc(nome) + ': ' : '') + rot + ' — ' + t[0].charAt(0).toLowerCase() + t[0].slice(1)});
  }
  function alheios(l){return (l || []).filter(function(x){return x.status == 'pendente' && x.atleta_id !== o.meId}).length}
  if (o.eAtl && o.prof) { venc('Atestado', o.prof.atestado_validade); venc('Anuidade', o.prof.anuidade_ate); }
  if (o.admin) {
    var nn = alheios(o.REN), nr = alheios(o.R);
    if (nn) out.push({sev: '', texto: nn + (nn == 1 ? ' renovação pendente' : ' renovações pendentes')});
    if (nr) out.push({sev: '', texto: nr + (nr == 1 ? ' reembolso pendente' : ' reembolsos pendentes')});
    (o.ATL || []).forEach(function(a){
      if (o.eAtl && a.id === o.meId) return;
      venc('Atestado', a.atestado_validade, a.nome || 'Sem nome'); venc('Anuidade', a.anuidade_ate, a.nome || 'Sem nome');
    });
  }
  return out;
}
function avisosAtuais(){return avisosCalculados({prof: prof, eAtl: eAtl, admin: admin, ATL: ATL, R: R, REN: REN, meId: me && me.id})}
function totalAvisos(){return avisosAtuais().length + AV.filter(function(x){return !x.lido_em}).length}

function datasRenovacao(x){
  if (!x || !x.emitido_em) return '';
  return 'Emitido em ' + br(x.emitido_em) + (x.pago_em ? ' • Pago em ' + br(x.pago_em) : '');
}

function valorProva(provaId){
  if (!provaId) return null;
  var p = P.filter(function(x){return x.id === provaId})[0];
  return p && p.valor_inscricao != null ? Number(p.valor_inscricao) : null;
}
// Valor digitado (vírgula ou ponto): {ok, valor}; vazio = remover (valor null)
function lerValorInscricao(t){
  t = String(t == null ? '' : t).trim();
  if (!t) return {ok: true, valor: null};
  if (!/^\d+([.,]\d+)?$/.test(t)) return {ok: false, valor: null};
  var v = Number(t.replace(',', '.'));
  return isFinite(v) && v >= 0 ? {ok: true, valor: v} : {ok: false, valor: null};
}
// Rótulos novos de distância: sem vazios, sem repetidos e sem os que já existem (ignora caixa)
function novasDistancias(txt, existentes){
  var vistos = {}, out = [];
  (existentes || []).forEach(function(x){vistos[String(x).trim().toLowerCase()] = 1});
  String(txt || '').split(',').forEach(function(x){
    x = x.trim();
    if (x && !vistos[x.toLowerCase()]) { vistos[x.toLowerCase()] = 1; out.push(x); }
  });
  return out;
}
function previaReembolso(d){
  var h = '<div class="item"><div class="info"><b>Confira antes de enviar</b>';
  h += '<small>Prova: ' + esc(d.prova || 'Sem prova') + '</small><br><small>Descrição: ' + esc(d.descricao) + '</small>';
  if (d.valorProva != null) h += '<br><small>Valor da inscrição: ' + esc(money(d.valorProva)) + '</small>';
  h += '<br><small>Valor solicitado: ' + esc(money(d.valor)) + '</small>';
  if (d.valorProva != null) {
    var df = Math.round((d.valor - d.valorProva) * 100) / 100;
    h += '<br><small>Diferença: ' + (df > 0 ? '+ ' : df < 0 ? '- ' : '') + esc(money(Math.abs(df))) + '</small>';
  }
  h += '<br><small>Comprovante: ' + esc(d.anexo || (d.mantido ? 'mantido o comprovante anterior' : 'nenhum')) + '</small></div></div>';
  return h;
}
function historicoReembolso(r, hr){
  var rows = (hr || []).filter(function(x){return x.reembolso_id === r.id}).sort(function(a, b){return String(a.alterado_em).localeCompare(String(b.alterado_em))});
  if (!rows.length) return '';
  var h = '<details style="flex-basis:100%"><summary style="cursor:pointer;color:var(--g);font-weight:600">Histórico (' + rows.length + ')</summary>';
  rows.forEach(function(x){
    var quem = x.alterado_por === r.atleta_id ? 'Atleta' : 'Gestão';
    h += '<div style="font-size:14px;padding:2px 0">' + esc((STL[x.status_anterior] || x.status_anterior || '—') + ' → ' + (STL[x.status_novo] || x.status_novo) + ' · ' + quem + ' · ' + br(String(x.alterado_em).slice(0,10)) + (x.motivo ? ' · Motivo: ' + x.motivo : '')) + '</div>';
  });
  return h + '</details>';
}

function distanciasProva(p){
  return ((p && p.prova_distancias) || []).slice().sort(function(a, b){return (a.ordem || 0) - (b.ordem || 0)});
}
function listaTendaHtml(p, parts){
  var h = '<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><title>Lista da tenda - ' + esc(p.nome) + '</title><style>body{font-family:Arial,sans-serif;margin:24px;color:#000}h1{font-size:20px;margin:0 0 4px}h2{font-size:16px;margin:20px 0 6px}p{margin:0}table{border-collapse:collapse;width:100%}th,td{border:1px solid #444;padding:6px 8px;text-align:left;font-size:14px}th:first-child,td:first-child{width:48px;text-align:center}td.as{width:40%;height:28px}</style></head><body>';
  h += '<h1>' + esc(p.nome) + '</h1><p>' + esc(br(p.data) + (p.local ? ' - ' + p.local : '')) + '</p>';
  distanciasProva(p).forEach(function(d){
    var nomes = (parts || []).filter(function(x){return x.distancia_id === d.id}).map(function(x){return (x.perfis && x.perfis.nome) || 'Sem nome'}).sort(function(a, b){return a.localeCompare(b, 'pt-BR')});
    h += '<h2>' + esc(d.rotulo) + '</h2>';
    if (!nomes.length) { h += '<p>Nenhum atleta marcado</p>'; return; }
    h += '<table><thead><tr><th>Nº</th><th>Nome</th><th>Assinatura</th></tr></thead><tbody>';
    nomes.forEach(function(n, i){ h += '<tr><td>' + (i + 1) + '</td><td>' + esc(n) + '</td><td class="as"></td></tr>'; });
    h += '</tbody></table>';
  });
  return h + '<script>window.onload=function(){window.print()}<\/script></body></html>';
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
    h += '<div class="rw" style="display:flex;gap:8px;align-items:center;padding:4px 0;font-size:14px"><span style="flex:1">' + esc((r.perfis && r.perfis.nome) || 'Sem nome') + ' · ' + money(r.valor) + ' <small style="color:var(--mu)">' + esc(r.descricao) + '</small></span><span class="tag ' + c + '">' + STL[r.status] + '</span>' + pdfBtn(r) + '</div>';
  });
  return h + '</details>';
}
function provaDist(p){
  var ds = distanciasProva(p), h = '';
  if (ds.length || p.tem_lista_presenca) {
    h += '<div style="margin-top:4px">';
    ds.forEach(function(d){ h += '<span class="tag">' + esc(d.rotulo) + '</span> '; });
    if (p.tem_lista_presenca) h += '<span class="tag w">Lista de presença</span>';
    h += '</div>';
  }
  if (!p.tem_lista_presenca) return h;
  if (!ds.length) return h + (admin ? '<div style="margin-top:6px"><small>sem distâncias cadastradas</small></div>' : '');
  var mine = PART.filter(function(x){return x.prova_id === p.id && x.atleta_id === me.id})[0];
  if (eAtl && days(p.data) >= 0) {
    if (mine) {
      var dm = ds.filter(function(d){return d.id === mine.distancia_id})[0];
      h += '<div style="margin-top:6px"><small>Marcado: ' + esc(dm ? dm.rotulo : '—') + '</small> <button class="btn s x" data-vs="' + esc(p.id) + '">Sair</button></div>';
    } else {
      h += '<div style="margin-top:6px"><select class="dsel" aria-label="Distância">' + ds.map(function(d){return '<option value="' + esc(d.id) + '">' + esc(d.rotulo) + '</option>'}).join('') + '</select> <button class="btn s g" data-vc="' + esc(p.id) + '">Vou correr</button></div>';
    }
  }
  if (admin) {
    var n = PART.filter(function(x){return x.prova_id === p.id}).length;
    h += '<div style="margin-top:6px"><small>' + n + ' marcado(s)</small> <button class="btn s x" data-lt="' + esc(p.id) + '">Lista da tenda</button></div>';
  }
  return h;
}
function viewCal(){
  var h = '<h2>Calendário de provas</h2>';
  if (admin) h += '<form id="f"><label>Prova<input name="n" required></label><label>Data<input type="date" name="d" required></label><label>Local<input name="l"></label><label>Distâncias (separadas por vírgula)<input name="k" placeholder="5 km, 10 km"></label><label style="flex-direction:row;align-items:center;gap:8px"><input type="checkbox" name="lp" style="width:auto"> Tem lista de presença</label><label>Inscrição até<input type="date" name="i"></label><label>Valor da inscrição (R$)<input type="number" name="v" step="0.01" min="0"></label><label>Link de inscrição<input type="url" name="u" placeholder="https://..." pattern="https?://.+"></label><button class="btn">Adicionar prova</button></form>';
  var m = '';
  if (!P.length) h += '<p class="empty">Nenhuma prova cadastrada' + (admin ? '. Adicione a primeira acima.' : ' ainda.') + '</p>';
  P.forEach(function(p){
    var ym = p.data.slice(0,7);
    if (ym !== m) { m = ym; h += '<div class="mes">' + MES[+ym.slice(5)-1] + ' de ' + ym.slice(0,4) + '</div>'; }
    var n = days(p.data), ins = p.inscricao_ate ? (days(p.inscricao_ate) < 0 ? 'Inscrições encerradas' : 'Inscrição até ' + br(p.inscricao_ate)) : '';
    h += '<div class="item"><div class="date">' + p.data.slice(8) + '<small>' + MES[+p.data.slice(5,7)-1].slice(0,3) + '</small></div><div class="info"><b>' + esc(p.nome) + '</b><small>' + esc([p.local, ins].filter(Boolean).join(' • ')) + '</small>' + provaDist(p) + '</div>' + (n < 0 ? '<span class="tag">Realizada</span>' : '<span class="tag ' + (n <= 14 ? 'w' : '') + '">' + (n == 0 ? 'Hoje' : 'em ' + n + ' d') + '</span>') + (n >= 0 && p.link_inscricao && /^https?:\/\//i.test(p.link_inscricao) ? '<a class="btn s" href="' + esc(p.link_inscricao) + '" target="_blank" rel="noopener noreferrer" style="text-decoration:none;display:inline-block">Inscrever-se</a>' : '') + (admin ? '<button class="btn s x" data-ep="' + esc(p.id) + '">Editar</button><button class="btn s x" data-lk="' + esc(p.id) + '">Link</button><button class="btn s x" data-delp="' + esc(p.id) + '">Excluir</button>' : '') + reembProva(p) + '</div>';
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
  var h = '<h2>Atestado e anuidade</h2><div class="item"><div class="info"><small>Atestado</small> ' + tag(st(prof.atestado_validade)) + '<br><small>Anuidade</small> ' + tag(st(prof.anuidade_ate)) + '</div></div>';
  h += '<p class="sum">A nova validade só passa a valer depois que a gestão validar a solicitação.</p>';
  h += '<form id="f2"><label>O que renovar<select name="tp"><option value="atestado">Atestado</option><option value="anuidade">Anuidade</option></select></label><label>Nova validade<input type="date" name="v" required min="' + today() + '"></label><label>Comprovante em PDF (até 5 MB)<input type="file" name="a" accept="application/pdf,.pdf"' + (EXIGIR_ANEXO ? ' required' : '') + '></label><button class="btn">Solicitar renovação</button></form>';
  if (!mine.length) h += '<p class="empty">Nenhuma solicitação de renovação.</p>';
  mine.forEach(function(x){
    var c = x.status == 'recusada' || x.status == 'cancelada' ? 'b' : x.status == 'pendente' ? 'w' : '';
    h += '<div class="item"><div class="info"><b>' + (x.tipo == 'atestado' ? 'Atestado' : 'Anuidade') + ' até ' + br(x.nova_validade) + '</b><small>Solicitada em ' + br(x.criado_em.slice(0,10)) + (x.status == 'recusada' && x.motivo_decisao ? ' • Motivo: ' + esc(x.motivo_decisao) : '') + (x.status == 'aprovada' && datasRenovacao(x) ? ' • ' + esc(datasRenovacao(x)) : '') + '</small></div><span class="tag ' + c + '">' + RTL[x.status] + '</span>' + (x.anexo_path || x.status == 'pendente' ? '<div class="acts">' + pdfBtn(x) + (x.status == 'pendente' ? '<button class="btn s x" data-rn="cancelada|' + x.id + '">Cancelar</button>' : '') + '</div>' : '') + '</div>';
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
    h += '<div class="item"><div class="info"><b>' + esc(x.perfis && x.perfis.nome || 'Sem nome') + ' · ' + (x.tipo == 'atestado' ? 'Atestado' : 'Anuidade') + ' até ' + br(x.nova_validade) + '</b><small>' + (x.motivo_decisao ? 'Motivo: ' + esc(x.motivo_decisao) : '') + (x.status == 'aprovada' ? esc(datasRenovacao(x)) : '') + '</small></div><span class="tag ' + c + '">' + RTL[x.status] + '</span>' + (x.anexo_path || x.status == 'aprovada' ? '<div class="acts">' + pdfBtn(x) + (x.status == 'aprovada' && x.atleta_id !== me.id ? '<button class="btn s" data-em="' + x.id + '">Corrigir emissão</button>' : '') + '</div>' : '') + '</div>';
  });
  return h;
}
function viewUsr(){
  return '<h2>Usuários e funções</h2><p class="sum">Atleta: usa os próprios dados. Gestão: valida renovações e reembolsos e cadastra provas. Administrador: tudo isso e atribui as funções. Patrocinador: vê apenas o dashboard com totais, sem dados pessoais; pode ser também atleta. A pessoa precisa sair e entrar de novo para a nova função valer.</p><label style="margin-bottom:10px">Buscar por nome ou e-mail<input id="uq" autocomplete="off"></label><div id="ulist"></div>';
}
function usrList(){
  var q = ($('#uq').value || '').trim().toLowerCase();
  var l = USR.filter(function(u){return !q || (u.nome || '').toLowerCase().indexOf(q) >= 0 || (u.email || '').toLowerCase().indexOf(q) >= 0});
  var h = '<p class="sum">' + l.length + ' usuário(s)' + (l.length > 100 ? ' (mostrando 100)' : '') + '</p>';
  function sel(cls, op, atual, nomes){ return '<select class="' + cls + '">' + op.map(function(p){return '<option value="' + p + '"' + (p === atual ? ' selected' : '') + '>' + nomes[p] + '</option>'}).join('') + '</select>'; }
  l.slice(0, 100).forEach(function(u){
    h += '<div class="item"><div class="info"><b>' + esc(u.nome || 'Sem nome') + (u.id === me.id ? ' (você)' : '') + '</b><small>' + esc(u.email || 'sem e-mail') + '</small></div>' +
      sel('sp', ['atleta', 'gestao', 'admin', 'patrocinador'], u.papel, PAP) + sel('ss', ['ativo', 'inativo', 'bloqueado'], u.status || 'ativo', STT) +
      '<label style="flex-direction:row;align-items:center;gap:6px"><input type="checkbox"' + (u.atleta ? ' checked' : '') + '> Atleta</label><button class="btn s g" data-pp="' + esc(u.id) + '">Salvar</button></div>';
  });
  $('#ulist').innerHTML = h;
}
function initUsr(){ $('#uq').oninput = usrList; usrList(); }
function viewAvisos(){
  var calc = avisosAtuais(), nl = AV.filter(function(x){return !x.lido_em}).length;
  var h = '<h2>Avisos</h2>';
  if (!calc.length && !AV.length) return h + '<p class="empty">Nenhum aviso.</p>';
  calc.forEach(function(x){h += '<div class="al ' + (x.sev == 'b' ? 'bad' : '') + '">' + x.texto + '</div> '});
  if (AV.length) h += '<h2>Histórico</h2>' + (nl ? '<p><button class="btn s x" data-lidot="1">Marcar todos como lidos</button></p>' : '');
  AV.forEach(function(x){
    h += '<div class="item"' + (x.lido_em ? ' style="opacity:.6"' : '') + '><div class="info"><b>' + esc(x.texto) + '</b><small>' + br(String(x.criado_em).slice(0, 10)) + '</small></div>' +
      (x.lido_em ? '' : '<button class="btn s x" data-lido="' + esc(x.id) + '">Marcar como lido</button>') + '</div>';
  });
  return h;
}
function viewConta(){
  return '<h2>Minha conta</h2><div class="item"><div class="info"><b>' + esc(prof.nome || 'Sem nome') + '</b><small>' + esc(me.email) + ' · ' + PAP[prof.papel] + ' · ' + STT[prof.status || 'ativo'] + '</small></div></div>' +
    '<h2>Meus dados cadastrais</h2><p class="sum">Mantenha nome, CPF, telefone e data de nascimento atualizados. A data de adesão à equipe é definida pela gestão.</p>' + formCadastro(prof, realAdmin, true) +
    '<h2>Alterar senha</h2><p class="sum">Use pelo menos 8 caracteres. Ao trocar a senha, os outros aparelhos conectados são desconectados.</p><form id="f3" style="max-width:420px;grid-template-columns:1fr"><label>Senha atual<input type="password" name="sa" required autocomplete="current-password"></label><label>Nova senha<input type="password" name="sn" required minlength="8" autocomplete="new-password"></label><label>Repita a nova senha<input type="password" name="sr" required minlength="8" autocomplete="new-password"></label><button class="btn">Alterar senha</button><p id="msg" class="sum"></p></form>';
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
    if (!prof.nome) h += '<p class="empty">Preencha seu nome em "Minha conta" antes de pedir reembolso.</p>';
    else {
      if (previa) {
        h += previaReembolso(previa) + '<div class="acts"><button class="btn" data-rbok="1">Confirmar envio</button><button class="btn s x" data-rbno="1">Voltar</button></div>';
      } else {
        var er = editRb ? R.filter(function(x){return x.id === editRb})[0] : null;
        if (editRb && !er) editRb = '';
        h += (er ? '<h2>Reenviar reembolso</h2>' : '') + '<form id="f"><label>Prova<select name="p" onchange="var f=this.form.v,v=valorProva(this.value);if(v!=null){f.value=v;f.dataset.auto=v}else if(f.dataset.auto&&f.value===f.dataset.auto){f.value=\'\';f.dataset.auto=\'\'}"><option value="">Sem prova</option>' + opts(P, function(x){return x.nome}) + '</select></label><label>Descrição<input name="t" placeholder="Inscrição, transporte…" required></label><label>Valor (R$)<input type="number" name="v" step="0.01" min="0.01" required></label><label>Comprovante em PDF (até 5 MB)<input type="file" name="c" accept="application/pdf,.pdf"' + (EXIGIR_ANEXO && !(er && er.anexo_path) ? ' required' : '') + '></label><button class="btn">' + (er ? 'Revisar e reenviar' : 'Solicitar reembolso') + '</button>' + (er ? '<button type="button" class="btn s x" data-rbno="1">Cancelar</button>' : '') + '</form>';
      }
    }
  }
  if (admin) {
    var tot = {pendente:0, aprovado:0, pago:0};
    R.forEach(function(r){ if (tot[r.status] !== undefined) tot[r.status] += Number(r.valor); });
    h += '<p class="sum">Pendente ' + money(tot.pendente) + ' · Aprovado a pagar ' + money(tot.aprovado) + ' · Pago ' + money(tot.pago) + '</p>';
  }
  if (!R.length) h += '<p class="empty">Nenhuma solicitação até agora.</p>';
  var elegiveis = admin ? R.filter(function(r){return lotePodeSelecionar(r, me.id)}) : [];
  if (elegiveis.length) h += '<label style="flex-direction:row;align-items:center;gap:8px;margin:4px 0"><input type="checkbox" data-selall="1"' + (elegiveis.every(function(r){return SEL[r.id]}) ? ' checked' : '') + '> Selecionar todos os aprovados</label>';
  R.forEach(function(r){
    var c = r.status == 'recusado' || r.status == 'cancelado' ? 'b' : r.status == 'pendente' ? 'w' : '';
    var nome = r.perfis && r.perfis.nome ? r.perfis.nome : 'Sem nome', own = r.atleta_id === me.id;
    h += '<div class="item">' + (admin && lotePodeSelecionar(r, me.id) ? '<input type="checkbox" data-sel="' + esc(r.id) + '"' + (SEL[r.id] ? ' checked' : '') + ' aria-label="Selecionar">' : '') + '<div class="info"><b>' + (admin ? esc(nome) + (own ? ' (você)' : '') + ' · ' : '') + money(r.valor) + '</b><small>' + esc(r.descricao) + (r.provas ? ' • ' + esc(r.provas.nome) : '') + ' • ' + br(r.criado_em.slice(0,10)) + (r.status == 'recusado' && r.motivo_decisao ? ' • Motivo: ' + esc(r.motivo_decisao) : '') + '</small></div><span class="tag ' + c + '">' + STL[r.status] + '</span><div class="acts">' + pdfBtn(r) +
      (own && r.status == 'recusado' ? '<button class="btn s g" data-rv="' + esc(r.id) + '">Corrigir e reenviar</button>' : '') +
      (admin && !own && r.status == 'pendente' ? '<button class="btn s g" data-st="aprovado|' + r.id + '">Aprovar</button><button class="btn s x" data-st="recusado|' + r.id + '">Recusar</button>' : '') +
      (admin && !own && r.status == 'aprovado' ? '<button class="btn s g" data-st="pago|' + r.id + '">Marcar como pago</button>' : '') +
      (own && r.status == 'pendente' ? '<span class="tag w">Aguarda outro gestor</span>' : '') + (admin && own && r.status == 'aprovado' ? '<span class="tag w">outro gestor precisa pagar</span>' : '') + (own && r.status == 'pendente' ? '<button class="btn s x" data-st="cancelado|' + r.id + '">Cancelar</button>' : '') + '</div>' + historicoReembolso(r, HR) + '</div>';
  });
  if (admin) h += loteBarraHtml(loteResumo(SEL, R, me.id), LOTE_DATA || today());
  return h;
}

function viewDash(){
  var h = '<h2>Dashboard</h2><label class="dper">Período<select id="dashper">' + [['mes', 'Mês atual'], ['3m', 'Últimos 3 meses'], ['ano', 'Ano'], ['tudo', 'Tudo']].map(function(x){ return '<option value="' + x[0] + '"' + (x[0] == dashPer ? ' selected' : '') + '>' + x[1] + '</option>'; }).join('') + '</select></label>';
  var est = dashEstado({dash: DASH, loading: DASH_LOADING, erro: DASH_ERRO});
  if (est == 'carregando') return h + '<p class="empty">Carregando…</p>';
  if (est == 'erro') return h + '<p class="empty">Não foi possível carregar o dashboard. Tente de novo.</p><button class="btn s g" data-dashretry="1">Tentar de novo</button>';
  if (est == 'vazio') return h + '<p class="empty">Sem dados no período.</p>';
  return h + cartoesDash(DASH) + barrasMesDash(DASH) + rankingProvaDash(DASH) + tempoMedioDash(DASH) + atletasDash(DASH);
}
async function carregarDash(){
  var seq = ++DASH_SEQ, p = periodoDash(dashPer, today());
  DASH_LOADING = true; DASH_ERRO = false;
  var r;
  try { r = await sb.rpc('dashboard_reembolsos', {p_de: p.de, p_ate: p.ate}); }
  catch (x) { r = {error: x}; }
  if (seq !== DASH_SEQ) return;  // resposta de um pedido já substituído
  DASH_LOADING = false;
  if (r.error) { DASH = null; DASH_ERRO = true; fail(r.error); render(); return; }
  DASH = r.data; render();
}

/* ---------- Dados ---------- */
async function refresh(){
  var pr = await sb.from('perfis').select('*').eq('id', me.id).single();
  if (pr.error) return fail(pr.error);
  prof = pr.data;
  if (prof.status && prof.status !== 'ativo') { loginMsg = prof.status === 'bloqueado' ? 'Conta bloqueada. Procure um administrador.' : 'Conta inativa. Procure a gestão da equipe.'; await sb.auth.signOut(); return; }
  admin = prof.papel === 'gestao' || prof.papel === 'admin'; sup = prof.papel === 'admin'; realAdmin = admin; realSup = sup;
  spons = prof.papel === 'patrocinador';
  if (tabIni) { tabIni = false; if (spons && tab === 'cal') tab = 'dash'; }
  var q = consultasUsuario({spons: spons, atleta: !!prof.atleta}), vazio = Promise.resolve({data: []});
  var a = await Promise.all([
    q.dados ? sb.from('provas').select('*, prova_distancias(id,rotulo,ordem)').order('data') : vazio,
    q.dados ? sb.from('reembolsos').select('*, perfis(nome), provas(nome)').order('criado_em', {ascending: false}) : vazio,
    admin ? sb.from('perfis').select('*').eq('atleta', true) : Promise.resolve({data: []}),
    q.dados ? sb.from('reembolso_historico').select('*').order('alterado_em') : vazio,
    q.dados ? sb.from('renovacoes').select('*, perfis(nome)').order('criado_em', {ascending: false}) : vazio,
    sup ? sb.from('perfis').select('*').order('nome') : Promise.resolve({data: []}),
    sup ? sb.from('solicitacoes_senha').select('*, perfis(nome,status)').order('criado_em', {ascending: false}).limit(100) : Promise.resolve({data: []}),
    q.dados ? sb.from('prova_participantes').select(admin ? '*, perfis(nome)' : '*') : vazio,
    q.dados ? sb.from('avisos').select('*').order('criado_em', {ascending: false}).limit(50) : vazio
  ]);
  for (var i = 0; i < a.length; i++) if (a[i].error) return fail(a[i].error);
  P = a[0].data; R = a[1].data; ATL = a[2].data; HR = a[3].data; REN = a[4].data; USR = a[5].data; SEN = a[6].data; PART = a[7].data || []; AV = a[8].data || []; render();
}
function render(){
  admin = realAdmin; sup = realSup; eAtl = !!prof.atleta; spons = prof.papel === 'patrocinador';
  if (!realSup) sim = '';
  var _R = R, _REN = REN, _DASH = DASH;
  if (sim) {
    sup = false; admin = sim === 'gestao';
    if (sim === 'patrocinador') { admin = false; eAtl = false; spons = true; DASH = dashParaPapel(DASH, true); }
    if (sim === 'atleta') { eAtl = true; R = R.filter(function(x){return x.atleta_id === me.id}); REN = REN.filter(function(x){return x.atleta_id === me.id}); }
  }
  var np = REN.filter(function(x){return x.status == 'pendente'}).length, nr = R.filter(function(x){return x.status == 'pendente'}).length;
  var ns = SEN.filter(function(x){return x.status == 'pendente'}).length;
  var tabs = montarAbas({admin: admin, sup: sup, spons: spons, eAtl: eAtl, np: np, nr: nr, ns: ns});
  if ((tab != 'avi' || (spons && !eAtl)) && !tabs.some(function(t){return t[0] == tab})) tab = tabs[0][0];
  var na = totalAvisos(); $('#sino').hidden = spons && !eAtl; $('#sino').textContent = 'Avisos (' + na + ')';
  $('#nav').innerHTML = tabs.map(function(t){return '<button data-t="' + t[0] + '"' + (t[0] == tab ? ' class="on"' : '') + '>' + t[1] + '</button>'}).join('');
  $('#role').textContent = rotuloAcesso({sim: sim, realSup: realSup, realAdmin: realAdmin, spons: spons}) + (prof.nome ? ' · ' + prof.nome : '');
  $('#out').hidden = false; $('#sim').hidden = !realSup; $('#sim').value = sim;
  $('#app').innerHTML = (sim ? '<div class="al" role="status">Modo simulação: você está vendo a tela de ' + (sim === 'gestao' ? 'gestão' : sim === 'patrocinador' ? 'patrocinador' : 'atleta') + ', somente leitura.</div>' : '') + (aviso ? '<div class="al" role="status" style="border-color:#0B7A64">' + esc(aviso) + '</div>' : '') + ({cal: viewCal, ath: viewAth, me: viewMine, ren: viewRen, reb: viewReb, usr: viewUsr, conta: viewConta, dash: viewDash, sen: viewSen, imp: viewImp, avi: viewAvisos})[tab]();
  if (tab == 'dash' && DASH === null && !DASH_LOADING && !DASH_ERRO) carregarDash();
  if (tab == 'usr') initUsr();
  if (tab == 'imp') initImp();
  R = _R; REN = _REN; DASH = _DASH;
  var f = $('#f');
  if (f && tab == 'reb') {
    var er2 = editRb ? R.filter(function(x){return x.id === editRb})[0] : null, src = rbRasc || (er2 ? {pid: er2.prova_id || '', descricao: er2.descricao, valor: er2.valor} : null);
    if (src) {
      f.p.value = src.pid; f.t.value = src.descricao; f.v.value = src.valor;
      if (src.arquivo) { try { var dt = new DataTransfer(); dt.items.add(src.arquivo); f.c.files = dt.files; } catch (x) {} }
    }
    rbRasc = null;
  }
  if (f) f.onsubmit = async function(e){
    e.preventDefault(); if (sim) return alert(MSGSIM); var d = new FormData(f), r;
    if (tab == 'cal') {
      var rots = String(d.get('k') || '').split(',').map(function(x){return x.trim()}).filter(Boolean), lp = !!d.get('lp');
      if (lp && !rots.length) return alert('Cadastre ao menos uma distância para usar a lista de presença.');
      r = await sb.from('provas').insert({nome: d.get('n'), data: d.get('d'), local: d.get('l'), inscricao_ate: d.get('i') || null, link_inscricao: d.get('u') || null, valor_inscricao: d.get('v') === '' ? null : Number(d.get('v')), tem_lista_presenca: lp}).select('id').single();
      if (!r.error && rots.length) {
        var nid = r.data.id;
        r = await sb.from('prova_distancias').insert(rots.map(function(x, i){return {prova_id: nid, rotulo: x, ordem: i}}));
        if (r.error) { try { await sb.from('provas').delete().eq('id', nid); } catch (x) {} }
      }
    }
    if (tab == 'ath' || tab == 'conta') {
      var cd = lerCadastro(d, tab == 'ath' || realAdmin);
      if (cd.erro) return alert(cd.erro);
      r = await sb.from('perfis').update(cd.dados).eq('id', tab == 'ath' ? editId : me.id);
      if (!r.error) { if (tab == 'ath') editId = ''; else aviso = 'Dados salvos.'; }
    }
    if (tab == 'reb') {
      var pid = d.get('p') || '', pvr = P.filter(function(x){return x.id === pid})[0], fa = d.get('c');
      previa = {pid: pid, prova: pvr ? pvr.nome : '', descricao: d.get('t'), valor: Number(d.get('v')), valorProva: valorProva(pid), anexo: fa && fa.size ? fa.name : '', mantido: !!(editRb && !(fa && fa.size) && (R.filter(function(x){return x.id === editRb})[0] || {}).anexo_path), arquivo: fa && fa.size ? fa : null};
      render(); window.scrollTo(0, 0); return;
    }
    if (r && r.error) return fail(r.error);
    refresh();
  };
  var f3 = $('#f3');
  if (f3) f3.onsubmit = async function(e){
    e.preventDefault(); if (sim) return alert(MSGSIM); var d3 = new FormData(f3);
      var sa = d3.get('sa'), sn1 = d3.get('sn'), sr = d3.get('sr');
      if (sn1 !== sr) return msg('As senhas novas não conferem.');
      if (sn1.length < 8) return msg('A nova senha precisa ter pelo menos 8 caracteres.');
      if (sn1 === sa) return msg('A nova senha deve ser diferente da atual.');
      msg('Aguarde…');
      // confere a senha atual (conta como tentativa) e recebe uma sessão nova para trocar a senha
      var ck = await sb.functions.invoke('entrar', {body: {email: me.email, senha: sa}});
      if (ck.error) { var mm = await msgFuncao(ck.error); msg(mm); if (/bloquead/i.test(mm)) setTimeout(refresh, 2500); return; }
      var ss2 = await sb.auth.setSession(ck.data.session);
      if (ss2.error) return msg('Sua sessão expirou. Saia, entre de novo e repita a troca de senha.');
      var up = await sb.auth.updateUser({password: sn1});
      if (up.error) return msg(/session/i.test(up.error.message) ? 'Sua sessão expirou. Saia, entre de novo e repita a troca de senha.' : up.error.message);
      await sb.auth.signOut({scope: 'others'});
      f3.reset(); msg('Senha alterada. Os outros aparelhos foram desconectados.');
      return;
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

document.addEventListener('change', function(e){
  var t = e.target; if (!t || !t.dataset) return;
  if (t.dataset.sel) { if (t.checked) SEL[t.dataset.sel] = true; else delete SEL[t.dataset.sel]; render(); }
  else if (t.dataset.selall) {
    R.forEach(function(r){ if (lotePodeSelecionar(r, me.id)) { if (t.checked) SEL[r.id] = true; else delete SEL[r.id]; } });
    render();
  }
  else if (t.id === 'lotedata') { LOTE_DATA = t.value; }
  else if (t.id === 'dashper') { dashPer = t.value; dashReset(); render(); }
});

document.addEventListener('click', async function(e){
  var b = e.target.closest('button'); if (!b) return;
  if (b.dataset.am) { authMode = b.dataset.am; showAuth(); return; }
  if (b.id === 'out') { await sb.auth.signOut(); return; }
  if (b.dataset.dashretry) { dashReset(); render(); return; }
  if (b.dataset.t) { if (b.dataset.t == 'dash') dashReset(); tab = b.dataset.t; aviso = ''; SEL = {}; LOTE_DATA = ''; editId = ''; editRb = ''; previa = null; rbRasc = null; refresh(); return; }
  if (b.dataset.rbno) { if (previa) rbRasc = {pid: previa.pid, descricao: previa.descricao, valor: previa.valor, arquivo: previa.arquivo}; else editRb = ''; previa = null; render(); return; }
  if (b.dataset.ed) { editId = b.dataset.ed; render(); window.scrollTo(0, 0); return; }
  if (b.dataset.edc) { editId = ''; render(); return; }
  if (b.dataset.impmod) { baixar('modelo_cadastro.csv', 'nome;email;papel;atleta;cpf;telefone;data_nascimento;data_adesao\nMaria Souza;maria@exemplo.com;atleta;sim;529.982.247-25;(11) 98888-7777;15/03/1990;01/02/2024\nJoão Lima;joao@exemplo.com;gestao;sim;;11977776666;1985-07-20;2023-05-10\n'); return; }
  if (b.dataset.impdl) { baixar('resultado_convites.csv', 'email;status;detalhe\n' + IMP.res.map(function(x){return [x.email, x.status, '"' + String(x.detalhe || '').replace(/"/g, '""') + '"'].join(';')}).join('\n')); return; }
  if (b.dataset.impgo) { await enviarLote(); return; }
  if (b.dataset.pdf) { await abrirAnexo(b.dataset.pdf); return; }
  if (sim && (b.dataset.delp || b.dataset.lk || b.dataset.ep || b.dataset.st || b.dataset.lote || b.dataset.lotelimpa || b.dataset.rn || b.dataset.em || b.dataset.pp || b.dataset.sn || b.dataset.rbok || b.dataset.rv || b.dataset.vc || b.dataset.vs || b.dataset.lido || b.dataset.lidot !== undefined)) { alert(MSGSIM); return; }
  if (b.dataset.lt) {
    var pl = P.filter(function(x){return x.id === b.dataset.lt})[0];
    if (pl) { var url = URL.createObjectURL(new Blob([listaTendaHtml(pl, PART.filter(function(x){return x.prova_id === pl.id}))], {type: 'text/html'})); window.open(url, '_blank'); setTimeout(function(){ URL.revokeObjectURL(url); }, 60000); }
    return;
  }
  var r;
  if (b.dataset.vc) {
    var sel = b.closest('.info').querySelector('select.dsel');
    r = await sb.from('prova_participantes').insert({prova_id: b.dataset.vc, atleta_id: me.id, distancia_id: sel.value});
  }
  else if (b.dataset.lido) { r = await sb.from('avisos').update({lido_em: new Date().toISOString()}).eq('id', b.dataset.lido); }
  else if (b.dataset.lidot !== undefined) { r = await sb.from('avisos').update({lido_em: new Date().toISOString()}).is('lido_em', null); }
  else if (b.dataset.vs) { r = await sb.from('prova_participantes').delete().eq('prova_id', b.dataset.vs).eq('atleta_id', me.id); }
  else if (b.dataset.delp) { if (!confirm('Excluir esta prova?')) return; r = await sb.from('provas').delete().eq('id', b.dataset.delp); }
  else if (b.dataset.st) {
    var p = b.dataset.st.split('|'), u = {status: p[0]};
    if (p[0] === 'recusado') { u.motivo_decisao = (prompt('Motivo da recusa (obrigatório):') || '').trim(); if (!u.motivo_decisao) return; }
    else if (p[0] === 'aprovado' && !confirm('Aprovar este reembolso?')) return;
    r = await sb.from('reembolsos').update(u).eq('id', p[1]);
  }
  else if (b.dataset.lotelimpa) { SEL = {}; render(); return; }
  else if (b.dataset.lote) {
    var rl = loteResumo(SEL, R, me.id), dl = ($('#lotedata') || {}).value || today();
    if (!rl.n) return;
    if (!confirm(rl.n + ' reembolso(s) · ' + money(rl.total) + ' · pagos em ' + br(dl))) return;
    b.disabled = true;
    r = await sb.rpc('pagar_reembolsos', {p_ids: rl.ids, p_data: dl});
    b.disabled = false;
    if (!r.error) { SEL = {}; aviso = rl.n + (rl.n === 1 ? ' reembolso marcado como pago.' : ' reembolsos marcados como pagos.'); }
  }
  else if (b.dataset.rv) { editRb = b.dataset.rv; previa = null; rbRasc = null; render(); window.scrollTo(0, 0); return; }
  else if (b.dataset.rbok) {
    if (!previa) return;
    var pv2 = previa;
    b.disabled = true;
    var er3 = editRb ? R.filter(function(x){return x.id === editRb})[0] : null;
    var an = er3 && er3.anexo_path && !pv2.arquivo ? {path: null} : await prepararAnexo(pv2.arquivo);
    if (an.err) { b.disabled = false; return alert(an.err); }
    if (er3) r = await sb.from('reembolsos').update({prova_id: pv2.pid || null, descricao: pv2.descricao, valor: pv2.valor, anexo_path: an.path || er3.anexo_path || null, status: 'pendente'}).eq('id', er3.id);
    else r = await sb.from('reembolsos').insert({atleta_id: me.id, prova_id: pv2.pid || null, descricao: pv2.descricao, valor: pv2.valor, status: 'pendente', anexo_path: an.path});
    if (r.error && an.path) await sb.storage.from('anexos').remove([an.path]);
    b.disabled = false;
    if (!r.error) {
      if (er3 && er3.anexo_path && an.path) await sb.storage.from('anexos').remove([er3.anexo_path]);
      if (previa === pv2) { previa = null; editRb = ''; }
    }
  }
  else if (b.dataset.ep) {
    var pe = P.filter(function(x){return x.id === b.dataset.ep})[0];
    if (!pe) return;
    var vt = prompt('Valor da inscrição (R$). Deixe em branco para remover:', pe.valor_inscricao != null ? String(pe.valor_inscricao).replace('.', ',') : '');
    if (vt === null) return;
    var vl = lerValorInscricao(vt);
    if (!vl.ok) { alert('Informe um valor válido, como 150,00.'); return; }
    var lpt = prompt('Esta prova terá lista de presença? Responda sim ou não (situação atual: ' + (pe.tem_lista_presenca ? 'sim' : 'não') + '):', pe.tem_lista_presenca ? 'sim' : 'não');
    if (lpt === null) return;
    lpt = lpt.trim().toLowerCase();
    if (['sim', 's', 'não', 'nao', 'n'].indexOf(lpt) < 0) { alert('Responda sim ou não.'); return; }
    var lpNovo = lpt.charAt(0) === 's';
    var dExist = distanciasProva(pe), dt2 = prompt('Novas distâncias a acrescentar (separadas por vírgula; deixe em branco para não alterar):', '');
    if (dt2 === null) return;
    var dNovas = novasDistancias(dt2, dExist.map(function(x){return x.rotulo}));
    if (lpNovo && !dExist.length && !dNovas.length) { alert('Cadastre ao menos uma distância para usar a lista de presença.'); return; }
    r = await sb.from('provas').update({valor_inscricao: vl.valor, tem_lista_presenca: lpNovo}).eq('id', pe.id);
    if (!r.error && dNovas.length) {
      var ordem0 = dExist.reduce(function(m, x){return Math.max(m, x.ordem || 0)}, -1) + 1;
      r = await sb.from('prova_distancias').insert(dNovas.map(function(x, i){return {prova_id: pe.id, rotulo: x, ordem: ordem0 + i}}));
    }
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
    else if (q[0] === 'aprovada') {
      var rx = REN.filter(function(y){return y.id === q[1]})[0], ea = prompt('Data de emissão do comprovante (dd/mm/aaaa) — obrigatória:');
      if (ea === null) return;
      var pe = parseData(ea);
      if (pe.erro || !pe.v) { alert(pe.erro ? 'Data de emissão inválida.' : 'Informe a data de emissão.'); return; }
      if (pe.v > today()) { alert('A data de emissão não pode ser futura.'); return; }
      w.emitido_em = pe.v;
      if (rx && rx.tipo == 'anuidade') {
        var pg = prompt('Data de pagamento da anuidade (dd/mm/aaaa) — opcional, deixe em branco se não houver:');
        if (pg === null) return;
        var pp2 = parseData(pg);
        if (pp2.erro) { alert('Data de pagamento inválida.'); return; }
        if (pp2.v > today()) { alert('A data de pagamento não pode ser futura.'); return; }
        if (pp2.v) w.pago_em = pp2.v;
      }
    }
    r = await sb.from('renovacoes').update(w).eq('id', q[1]);
  }
  else if (b.dataset.em) {
    var ne = prompt('Nova data de emissão (dd/mm/aaaa):');
    if (ne === null) return;
    var pn = parseData(ne);
    if (pn.erro || !pn.v) { alert('Data de emissão inválida.'); return; }
    if (pn.v > today()) { alert('A data de emissão não pode ser futura.'); return; }
    r = await sb.rpc('editar_emissao_renovacao', {p_id: b.dataset.em, p_emissao: pn.v});
  }
  else return;
  if (r.error) return fail(r.error);
  refresh();
});

/* ---------- Início ---------- */
async function boot(){
  dashReset();
  var s = await sb.auth.getSession();
  me = s.data.session ? s.data.session.user : null;
  if (HASH) { history.replaceState(null, '', location.pathname + location.search); HASH = ''; }
  if (ENTRADA === 'signup' && me) { aviso = 'E-mail confirmado! Bem-vindo(a) à EAMSP. Complete seu cadastro na aba "Minha conta".'; tab = 'conta'; ENTRADA = ''; }
  if (recovery || invite || !me) { prof = null; showAuth(); } else { await refresh(); }
}
function temaAtual(){
  var t = document.documentElement.getAttribute('data-theme');
  if (t === 'light' || t === 'dark') return t;
  return window.matchMedia && matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}
function aplicaTema(t){
  if (t) document.documentElement.setAttribute('data-theme', t);
  var b = $('#tema'); if (!b) return;
  var escuro = temaAtual() === 'dark';
  b.textContent = escuro ? 'Modo claro' : 'Modo escuro';
  b.setAttribute('aria-label', escuro ? 'Mudar para o tema claro' : 'Mudar para o tema escuro');
}
function initTema(){
  if (!document.documentElement) return;
  var salvo = null; try { salvo = localStorage.getItem('eamsp-tema'); } catch (x) {}
  aplicaTema(salvo === 'light' || salvo === 'dark' ? salvo : null);
  var b = $('#tema');
  if (b) b.onclick = function(){
    var n = temaAtual() === 'dark' ? 'light' : 'dark';
    try { localStorage.setItem('eamsp-tema', n); } catch (x) {}
    aplicaTema(n);
  };
}
initTema();
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
