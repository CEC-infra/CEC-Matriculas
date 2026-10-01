# Análise de rematrícula 2027 — CEC

Atualizada em 30/09/2026, a partir do Supabase de produção
`uczxuaaojixapkdlayph`, do commit `b904745` de `CEC-Matriculas` e da cópia
local do serviço `agente-cec`.

## Regra consolidada

Uma família já cadastrada faz rematrícula. O sistema identifica o responsável,
lista os filhos vinculados, deriva a próxima série pela regra acadêmica e usa a
tabela de preços configurada. De 01 a 31/10, a rematrícula usa o valor
antecipado (sem reajuste); a partir de 01/11, o valor cheio de 2027. O valor é
travado ao assinar o contrato.

Uma família recebe uma única jornada segura; nela seleciona um ou mais filhos.
Cada filho mantém matrícula, contrato, eventos e cobrança próprios. Quem não
existe no cadastro não pode fazer rematrícula: segue para matrícula nova ou
secretaria.

## Estado real validado

| Item | Resultado |
| --- | ---: |
| Responsáveis / alunos importados | 603 / 284 |
| Alunos com responsável primário e financeiro único | 284 / 284 |
| Alunos com caminho acadêmico e preço 2027 | 272 |
| Exceções sem preço (9º ano → 1ª série) | 10 |
| Exceções sem turma atual | 2 |
| Alunos em turno da tarde cuja oferta 2027 só prevê manhã | 103 |
| Matrículas já criadas na campanha 2027 de rematrícula | 0 |

Os 12 registros acadêmicos sem percurso/preço devem ser corrigidos pela
secretaria antes de qualquer disparo. Os 103 alunos de turno diferente podem
escolher manhã no contrato somente se essa for a decisão operacional da escola;
o sistema não deve assumir a troca silenciosamente.

## Controle de versão e banco

`CEC-Matriculas` foi sincronizado do GitHub na revisão `b904745`; estava dois
commits atrás localmente. A pasta `agente-cec` não possui repositório Git nem
um repositório CEC correspondente na conta `lopessd`, portanto suas mudanças
precisam ser versionadas antes de qualquer publicação.

O schema remoto contém funções equivalentes a mudanças recentes que não aparecem
na tabela de histórico de migrações remotas. Antes de usar `supabase db push`,
faça backup e reconcilie esse histórico: aplicar às cegas pode repetir DDL que
já foi feito manualmente. As duas migrações desta revisão são aditivas, mas
dependem dessa reconciliação segura.

## O que já funciona

- Identificação segura de rematrícula por CPF e WhatsApp na página pública.
- Detecção de cadastro existente na matrícula nova, oferecendo rematrícula sem
  duplicar responsável.
- Progressão por `grades.next_grade_id` e ofertas de 2027.
- Contrato individual: PDF privado, confirmação por e-mail, assinatura,
  evidências e hash.
- Painel de funil, eventos, sessões de contrato e filas.
- Agente WhatsApp com buffer, handoff, opt-out, régua, limites e guardrail de
  valores.

## Correções incluídas nesta revisão

- Jornada segura por família no agente, inclusive quando a matrícula 2027
  ainda não foi criada.
- Cotação do agente alinhada ao valor antecipado de outubro.
- Proteção contra trocar o responsável de uma matrícula existente.
- Valor antecipado restrito à rematrícula; matrícula nova usa tabela cheia.
- Filhos sem próxima série/valor, ou já vinculados a outro responsável, ficam
  explícitos como indisponíveis sem bloquear a rematrícula dos demais filhos.
- Dados do contrato editáveis até a solicitação do código; o PDF rascunho é
  invalidado e regenerado após qualquer confirmação.
- A etapa final registra somente a preferência entre Pix e cartão. Ela não
  declara pagamento confirmado nem cria cobrança enquanto o Asaas não estiver
  integrado.

## Pendências que bloqueiam “100% produção”

1. Configurar preço para a 1ª série e classificar os dois alunos sem turma.
2. Definir a política para os 103 alunos de turno da tarde antes de abrir a
   jornada em escala.
3. Fazer backup/reconciliação do histórico de migrações e implantar as novas
   migrações e as versões do agente/painel em conjunto.
4. Configurar e testar as credenciais de e-mail do Resend. Há função publicada,
   mas a permissão atual não permite auditar os segredos.
5. Implementar e configurar o provedor de cobrança (Asaas). Hoje há
   `payment_dispatches`, mas não há função publicada para criar cliente,
   cobranças Pix/cartão ou os boletos.
6. Definir e publicar o contrato definitivo 2027. O documento atual ainda tem
   referência de versão 2025.

## Ordem segura de publicação

1. Corrigir os 12 cadastros acadêmicos e decidir os turnos.
2. Aplicar as migrações, primeiro em ambiente de teste e depois em produção.
3. Publicar a Edge Function `generate-contract`, o painel e o agente juntos.
4. Fazer teste com uma família controlada: link, seleção de dois filhos,
   edição, PDF, e-mail, assinatura e geração de parcelas.
5. Só então iniciar a régua de WhatsApp em lote pequeno e revisar as conversas
   e a fila antes de aumentar o volume.
