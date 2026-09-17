-- Cadastros da campanha 2027 (tela Configurações). Famílias e alunos NÃO são semeados:
-- entram pela importação da base da secretaria e pelo formulário público.

-- Séries e regra de transição ------------------------------------------------

insert into public.grades (code, name, stage, sort_order) values
  ('infantil_4', 'Infantil IV', 'infantil',      1),
  ('infantil_5', 'Infantil V',  'infantil',      2),
  ('ano_1',      '1º ano',      'fundamental_1', 3),
  ('ano_2',      '2º ano',      'fundamental_1', 4),
  ('ano_3',      '3º ano',      'fundamental_1', 5),
  ('ano_4',      '4º ano',      'fundamental_1', 6),
  ('ano_5',      '5º ano',      'fundamental_1', 7),
  ('ano_6',      '6º ano',      'fundamental_2', 8),
  ('ano_7',      '7º ano',      'fundamental_2', 9),
  ('ano_8',      '8º ano',      'fundamental_2', 10),
  ('ano_9',      '9º ano',      'fundamental_2', 11),
  ('serie_1',    '1ª série',    'medio',         12);

update public.grades g
   set next_grade_id = n.id
  from public.grades n
 where n.sort_order = g.sort_order + 1;

-- Valores e vagas 2027 (por série de destino) --------------------------------

insert into public.grade_offerings (academic_year, grade_id, shifts, amount_cents, cash_amount_cents, seats_total)
select 2027, g.id, v.shifts::public.shift[], v.amount, v.cash, v.seats
from (values
  ('infantil_5', '{manha}',       96800,  89100, 12),
  ('ano_1',      '{manha}',      104000,  95700,  8),
  ('ano_2',      '{manha,tarde}', 118500, 109000,  6),
  ('ano_3',      '{manha,tarde}', 124200, 114300,  9),
  ('ano_4',      '{manha,tarde}', 131000, 120500,  4),
  ('ano_5',      '{manha}',      138600, 127500,  7),
  ('ano_6',      '{manha}',      145800, 134100, 11),
  ('ano_7',      '{manha}',      152000, 139800,  5),
  ('ano_8',      '{manha}',      158400, 145700,  3),
  ('ano_9',      '{manha}',      164200, 151000,  6),
  ('serie_1',    '{manha}',      178000, 163700, 10)
) as v (code, shifts, amount, cash, seats)
join public.grades g on g.code = v.code;

-- Campanhas ------------------------------------------------------------------

insert into public.campaigns (name, kind, academic_year, status, starts_on, ends_on)
values
  ('Rematrícula 2027',       'rematricula',    2027, 'ativa', '2026-09-01', '2026-09-20'),
  ('Matrículas novas 2027',  'matricula_nova', 2027, 'ativa', '2026-09-01', null);

insert into public.payment_policies
  (campaign_id, cash_discount_pct, max_installments, last_due_date, accepted_methods,
   sibling_discount_pct, late_fee_pct, monthly_interest_pct, boleto_due_business_days, scholarship_requires_handoff)
select id, 8, 3, '2027-01-10', '{cartao,boleto,pix}', 10, 2, 1, 3, true
from public.campaigns;

insert into public.payment_plans (campaign_id, name, description, installments, discount_pct, due_dates, sort_order)
select c.id, p.name, p.description, p.installments, p.discount, p.due_dates::date[], p.sort_order
from public.campaigns c
cross join (values
  ('À vista',      'Pagamento único em novembro',    1, 8, '{2026-11-10}',                       1),
  ('3x sem juros', 'Novembro · dezembro · janeiro',  3, 0, '{2026-11-10,2026-12-10,2027-01-10}', 2),
  ('2x sem juros', 'Dezembro · janeiro',             2, 0, '{2026-12-10,2027-01-10}',            3)
) as p (name, description, installments, discount, due_dates, sort_order);

-- Documentos -----------------------------------------------------------------

insert into public.documents (code, title, kind, requirement, per_grade) values
  ('contrato_prestacao', 'Contrato de prestação de serviços', 'contrato',       'assinatura_obrigatoria', false),
  ('termo_imagem',       'Termo de uso de imagem',            'termo_imagem',   'opcional',               false),
  ('regimento_interno',  'Regimento interno',                 'regimento',      'aceite_obrigatorio',     false),
  ('lista_material',     'Lista de material',                 'lista_material', 'anexo',                  true);

insert into public.document_versions (document_id, version, pages, is_current, published_at)
select d.id, v.version, v.pages, true, now()
from (values
  ('contrato_prestacao', 'v3', 6),
  ('termo_imagem',       'v1', 1),
  ('regimento_interno',  'v2', 14)
) as v (code, version, pages)
join public.documents d on d.code = v.code;

insert into public.campaign_documents (campaign_id, document_id, sort_order)
select c.id, d.id,
       case d.code when 'contrato_prestacao' then 1 when 'termo_imagem' then 2 when 'regimento_interno' then 3 else 4 end
from public.campaigns c
cross join public.documents d;

-- Régua de mensagens ---------------------------------------------------------
-- Variáveis: {{responsavel}}, {{aluno}}, {{proxima_serie}}, {{fim_campanha}}, {{link}}.
-- Tentativas 4 e 5 ficam inativas até a coordenação revisar o texto.

insert into public.message_templates (campaign_id, code, name, attempt_number, wait_hours, active, body)
select c.id, t.code, t.name, t.attempt, t.wait, t.active, t.body
from public.campaigns c
cross join (values
  ('contato_inicial', 'Contato inicial', 1, 0, true,
   'Oi {{responsavel}}! Aqui é do CEC 👋 A rematrícula de {{aluno}} para o {{proxima_serie}} já está aberta. Quer que eu te explique as condições?'),
  ('lembrete_leve', 'Lembrete leve', 2, 48, true,
   'Oi {{responsavel}}, tudo bem? Passando para lembrar que a rematrícula de {{aluno}} para 2027 segue aberta até {{fim_campanha}}. Posso te ajudar com alguma dúvida?'),
  ('condicoes_pagamento', 'Condições de pagamento', 3, 48, true,
   '{{responsavel}}, a rematrícula de {{aluno}} pode ser paga à vista com 8% de desconto ou em até 3x sem juros (última parcela em janeiro), no cartão, boleto ou Pix. Quer que eu te envie o link para concluir?'),
  ('lembrete_prazo', 'Lembrete de prazo', 4, 48, false,
   '{{responsavel}}, a campanha de rematrícula termina em {{fim_campanha}} e as vagas do {{proxima_serie}} são limitadas. Quer garantir a vaga de {{aluno}}?'),
  ('ultimo_contato', 'Último contato', 5, 72, false,
   '{{responsavel}}, este é nosso último lembrete sobre a rematrícula de {{aluno}}. Se preferir, responda SAIR e não enviaremos mais mensagens.')
) as t (code, name, attempt, wait, active, body)
where c.kind = 'rematricula';

insert into public.message_templates (campaign_id, code, name, attempt_number, wait_hours, active, body)
select c.id, 'primeiro_contato', 'Primeiro contato', 1, 0, true,
       'Oi {{responsavel}}! Aqui é do CEC 👋 Recebemos a pré-matrícula de {{aluno}} para o {{proxima_serie}} em 2027. Posso te passar valores, turnos e vagas disponíveis?'
from public.campaigns c
where c.kind = 'matricula_nova';
