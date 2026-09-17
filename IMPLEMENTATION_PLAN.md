# Roteiro de dados reais

## 1. Fundação — concluído

- Configuração pública do Supabase no ambiente local, sem chave de serviço no navegador.
- Cliente HTTP para Auth, REST e RPCs, respeitando o RLS já definido no banco.
- Estados comuns de carregamento, erro e lista vazia.
- Login obrigatório para páginas internas e validação de `profiles.active`.

## 2. Jornadas públicas — concluído

- `/matricula` consulta séries e valores públicos e chama `pre_matricula_submit`.
- `/rematricula/:token` chama `rematricula_open` e salva a escolha via `rematricula_save`.

## 3. Painel operacional — concluído

- Dashboard: views de funil, financeiro, alertas e fila.
- Famílias, matrículas novas e matriculados: `v_enrollment_list`.
- Detalhe da família: eventos, parcelas, documentos e conversa.
- Configurações: ofertas, políticas, campanhas e versões de documentos.
- Automação: estatísticas, próximas mensagens, throughput e pausa de fila.
- Atendimento: lista, histórico e handoff de conversas.

## 4. Pré-requisitos para uso em produção

1. Criar os usuários da secretaria no Supabase Auth e ativar seus perfis em `public.profiles`.
2. Importar a base de responsáveis, alunos, turmas e matrículas existentes. O banco remoto ainda só contém dados de configuração.
3. Configurar a integração de WhatsApp e uma Edge Function/worker para consumir `message_queue`; nenhuma Edge Function existe hoje.
4. Integrar o provedor de assinatura e pagamento para alimentar `document_acceptances` e `installments`.
5. Habilitar a proteção contra senhas vazadas no Supabase Auth e revisar os avisos de `SECURITY DEFINER` — as três RPCs públicas são intencionais, mas devem continuar restritas aos seus parâmetros atuais.

## 5. Validação

- Build: `npm run build`.
- Formulário público: enviar uma pré-matrícula de teste e verificar `pre_enrollment_submissions`, `enrollments` e `message_queue`.
- Painel: entrar com um perfil ativo e verificar as views da campanha.
