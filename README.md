# Minha Loja — Site (substitui o app do Expo Go)

Site completo da loja: catálogo, produto, carrinho, checkout (com cupom,
frete e Mercado Pago) e conta com login por telefone. Usa o **mesmo banco
Supabase** do app e do painel administrativo — nenhuma migração nova é
necessária, os dados já estão todos lá.

## Passo 1 — Configurar

1. Duplique `.env.local.example`, renomeie para `.env.local`
2. Preencha com os **mesmos valores** que você já usa no `admin-painel` e no
   `minha-loja` (Supabase URL/chave, e as chaves do EmailJS)

## Passo 2 — Instalar e rodar localmente

```bash
npm install
npm run dev
```

Abra `http://localhost:3000` no navegador.

## Passo 3 — Publicar na Vercel (igual ao admin-painel)

1. Suba esta pasta para um repositório novo no GitHub (mesmo processo do
   `admin-painel`: `git init`, `git add .`, `git commit`, `git remote add
   origin ...`, `git push`)
   - **Importante:** crie um `.gitignore` com `node_modules`, `.next`,
     `.env.local` antes do primeiro commit, para não repetir o erro de
     arquivo grande que tivemos no admin
2. Na Vercel: **Add New → Project** → importe o repositório
3. Adicione as mesmas variáveis de ambiente do `.env.local`
4. Deploy

## Design

- Cor principal: laranja `#FF6B1A` (marca/ação), azul-marinho `#16243D`
  (cabeçalho e texto), fundo creme `#FFFBF6`
- Tipografia: Baloo 2 (títulos, arredondada e amigável) + Inter (texto)
- Mobile-first: navegação inferior fixa no celular, barra superior no
  desktop

## O que fazer com o app antigo (Expo Go)

Ele pode continuar existindo como referência ou ser descontinuado — os dois
"consomem" o mesmo banco de dados, então não há conflito técnico em manter
os dois no ar por um tempo, mas a recomendação é divulgar só o link do site
a partir de agora, para não confundir os clientes com dois canais.
