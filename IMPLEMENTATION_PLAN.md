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
2. Corrigir os 10 alunos sem oferta de 2027 (9º ano → 1ª série), os 2 sem turma atual e decidir os 103 casos de turno antes de qualquer disparo em escala. A base já foi importada.
3. Publicar o agente de WhatsApp e configurar seu cron externo para consumir `message_queue`. As Edge Functions de contrato e e-mail existem; a instância UAZAPI e o envio real precisam de validação controlada.
4. Integrar Asaas para criar cliente e cobranças a partir de `payment_dispatches`, alimentando `installments` por webhook. Boleto ainda não está disponível no ambiente atual.
5. Habilitar a proteção contra senhas vazadas no Supabase Auth e revisar os avisos de `SECURITY DEFINER` — as três RPCs públicas são intencionais, mas devem continuar restritas aos seus parâmetros atuais.

## 5. Validação

- Build: `npm run build`.
- Formulário público: enviar uma pré-matrícula de teste e verificar `pre_enrollment_submissions`, `enrollments` e `message_queue`.
- Painel: entrar com um perfil ativo e verificar as views da campanha.
