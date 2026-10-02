# Sistema EAMSP no GitHub Pages (versão simples)

Site estático (HTML + JavaScript) publicado no GitHub Pages. Os dados ficam no Supabase; o sistema **não guarda arquivos**: só nomes, datas de validade (atestado e anuidade), provas e pedidos de reembolso.

## Passo a passo
1. **Supabase:** crie um projeto (região São Paulo, se disponível). No *SQL Editor*, cole o `schema.sql` e clique em *Run*. (Quem já tinha rodado uma versão anterior do `schema.sql` roda só o `migracao_validacao.sql`.)
2. **Chaves:** em *Project Settings > API*, copie a *Project URL* e a chave *anon* para o `config.js`. Nunca use a `service_role`.
3. **GitHub:** crie um repositório em nome da equipe (ex.: `eamsp`) e envie estes arquivos na raiz.
4. **Pages:** em *Settings > Pages*, escolha *Deploy from a branch*, branch `main`, pasta `/ (root)`. O endereço será `https://USUARIO.github.io/eamsp/`.
5. **Login:** no Supabase, em *Authentication > URL Configuration*, coloque o endereço do passo 4 (com a barra final) em *Site URL* e também em *Redirect URLs*. Sem isso, a confirmação de e-mail e a recuperação de senha não funcionam.
6. **Primeira gestão:** cadastre-se no site e, no SQL Editor, rode (trocando o e-mail):
   `update public.perfis set papel = 'admin' where id = (select id from auth.users where email = 'admin@exemplo.com');`
7. **Teste de permissões:** com duas contas de atleta e uma de gestão, siga o roteiro do fim do `schema.sql`.

## Níveis de acesso
- **Atleta:** vê o calendário, atualiza o nome, solicita renovações e reembolsos e acompanha as decisões.
- **Gestão:** tudo do atleta, mais cadastrar provas, ver os atletas e validar renovações e reembolsos.
- **Admin:** tudo da gestão, mais a aba **Usuários**, onde atribui a função de cada pessoa cadastrada. O banco impede que alguém mude a própria função sem ser admin e que o último admin seja rebaixado; cada mudança fica registrada.
- O primeiro admin é definido pelo SQL Editor (passo "Primeira gestão", agora com `'admin'`). Depois disso, as demais funções são dadas pela aba Usuários.

## Validação pela gestão
- **Atestado e anuidade:** o atleta não altera as datas diretamente. Ele solicita a renovação (com a nova validade) e a data só passa a valer quando a gestão aprova. A recusa exige motivo, e só pode haver uma solicitação pendente por tipo.
- **Reembolso:** o atleta cria o pedido como pendente e só pode cancelá-lo enquanto pendente. A gestão aprova, recusa (com motivo) e marca como pago, nessa ordem; o banco bloqueia qualquer outro caminho e registra quem decidiu e quando.
- A gestão confere o comprovante fora do sistema: como não há arquivos guardados, a validação é uma confirmação manual.

## Cuidados
- O repositório em Pages gratuito é **público**. Nele ficam só o código, a URL e a chave anon, que são públicas por desenho. Nunca coloque dados de atletas no repositório.
- A segurança vem das regras do banco (`schema.sql`); não desative a segurança por linha (RLS).
- No plano gratuito do Supabase o projeto pausa após cerca de uma semana sem uso e os backups são limitados. Para uso real com a equipe, avalie o plano Pro.
- A biblioteca do Supabase é carregada de um CDN público; se quiser mais controle, fixe uma versão exata no `index.html`.
- Peça o consentimento dos atletas e publique um aviso de privacidade (LGPD): o sistema trata dado de saúde (validade do atestado).
