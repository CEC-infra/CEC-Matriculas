# CEC · Matrícula Inteligente — versão React + Vite

Mesmo painel do `site/` (HTML estático), reescrito em React com **navegação por
path**: cada tela tem a sua URL, o botão voltar do navegador funciona e qualquer
rota pode ser recarregada ou compartilhada.

## Rodar

```bash
npm install
npm run dev      # http://localhost:5173
npm run build    # gera dist/
npm run preview  # serve o dist/
```

## Rotas

| Caminho | Tela |
|---|---|
| `/` | redireciona para `/dashboard` |
| `/dashboard` | Visão geral da operação |
| `/familias` | CRM operacional |
| `/familias/:id` | Detalhe da família + linha do tempo |
| `/familias/:id/atendimento` | Subaba de atendimento da família |
| `/familias/:id/assinatura` | Subaba de assinatura e pagamento |
| `/atendimento` | Central de atendimento (todas as conversas) |
| `/matriculas-novas` | Entrada de novas famílias |
| `/matriculados` | Resultado da campanha |
| `/automacao` | Motor de mensagens e fila de envio |
| `/assinatura-e-pagamento` | Documentos, evidências e parcelas |
| `/configuracoes` | Séries, condições e parâmetros (somente leitura) |
| `/rematricula` | Prévia do link individual do responsável |
| `/matricula` | Prévia do link público de pré-matrícula |

Rota desconhecida cai no dashboard.

## Estrutura

```
index.html                    shell do Vite
src/main.jsx                  monta o app dentro do BrowserRouter
src/App.jsx                   tabela de rotas (inclui as rotas filhas da família)
src/components/Layout.jsx     sidebar + topbar + <Outlet>; título vem da rota
src/components/Icon.jsx       ícones do menu (SVG inline, sem dependência)
src/components/ui.jsx         primitivos: Badge, Kpi, CardHead, Field, Chips…
src/data/content.js           dados de demonstração + findFamily/initials
src/pages/*.jsx               uma tela por arquivo
src/styles/styles.css         mesma folha do site estático + ajustes do roteador
```

## Menu com ícones

Cada item de `DATA.nav` traz `icon` (traçado em `Icon.jsx`), `dot` (cor de acento,
exposta ao CSS como `--accent`) e `path` (rota). O ícone aparece num quadrado
arredondado tingido com o acento; o item ativo ganha fundo e um filete lateral.
Para acrescentar uma tela: novo traçado em `Icon.jsx`, nova entrada em `DATA.nav`
e em `DATA.heads`, e uma `<Route>` em `App.jsx`.

## Deploy

Como a navegação é por path, o servidor precisa devolver `index.html` em qualquer
rota. Na Vercel isso já está no `vercel.json`; em outro host, configure o mesmo
fallback de SPA.

- **Root Directory**: `app`
- **Build Command**: `npm run build`
- **Output Directory**: `dist`
