-- Views das telas do painel. security_invoker: respeitam o RLS de quem consulta.

-- Famílias, Matrículas novas e Matriculados.
create view public.v_enrollment_list with (security_invoker = true) as
select
  e.id,
  e.campaign_id,
  c.name                                   as campaign_name,
  c.kind                                   as campaign_kind,
  e.status,
  public.journey_status_label(e.status)    as status_label,
  e.origin,
  g.id                                     as guardian_id,
  g.full_name                              as guardian_name,
  g.phone                                  as guardian_phone,
  s.id                                     as student_id,
  s.full_name                              as student_name,
  fc.name                                  as from_class_name,
  tg.name                                  as target_grade_name,
  e.target_shift,
  e.attempts,
  c.max_attempts,
  e.next_action,
  e.next_action_at,
  e.automation_paused,
  e.assigned_to,
  e.amount_cents,
  e.discount_pct,
  pp.name                                  as payment_plan_name,
  pp.installments                          as payment_plan_installments,
  e.created_at,
  e.completed_at,
  e.updated_at
from public.enrollments e
join public.campaigns c  on c.id = e.campaign_id
join public.guardians g  on g.id = e.guardian_id
join public.students s   on s.id = e.student_id
join public.grades tg    on tg.id = e.target_grade_id
left join public.classes fc       on fc.id = e.from_class_id
left join public.payment_plans pp on pp.id = e.payment_plan_id;

-- Funil da jornada e cards de fechamento (Fechadas / A fechar / Perdidas).
create view public.v_campaign_funnel with (security_invoker = true) as
select
  c.id                                         as campaign_id,
  c.name                                       as campaign_name,
  count(e.id)                                  as elegiveis,
  count(e.contacted_at)                        as contatadas,
  count(e.replied_at)                          as responderam,
  count(e.link_sent_at)                        as link_enviado,
  count(e.link_opened_at)                      as link_aberto,
  count(e.form_started_at)                     as formulario_iniciado,
  count(e.signed_at)                           as assinado,
  count(e.completed_at)                        as concluido,
  count(e.id) filter (where e.lost_at is not null)                              as perdidas,
  count(e.id) filter (where e.completed_at is null and e.lost_at is null)       as a_fechar,
  coalesce(sum(e.amount_cents) filter (where e.lost_at is not null), 0)::bigint as perdidas_cents,
  coalesce(sum(e.amount_cents) filter (where e.completed_at is null and e.lost_at is null), 0)::bigint as a_fechar_cents
from public.campaigns c
left join public.enrollments e on e.campaign_id = c.id
group by c.id;

-- Financeiro da campanha (Previsto / Contratado / Recebido / Em atraso).
create view public.v_campaign_finance with (security_invoker = true) as
select
  c.id   as campaign_id,
  c.name as campaign_name,
  (select coalesce(sum(round(e.amount_cents * (1 - e.discount_pct / 100))), 0)
     from public.enrollments e where e.campaign_id = c.id)::bigint as previsto_cents,
  (select coalesce(sum(i.amount_cents), 0)
     from public.installments i join public.enrollments e on e.id = i.enrollment_id
    where e.campaign_id = c.id and e.signed_at is not null and i.status <> 'cancelado')::bigint as contratado_cents,
  (select coalesce(sum(coalesce(i.paid_amount_cents, i.amount_cents)), 0)
     from public.installments i join public.enrollments e on e.id = i.enrollment_id
    where e.campaign_id = c.id and i.status = 'pago')::bigint as recebido_cents,
  (select coalesce(sum(i.amount_cents), 0)
     from public.installments i join public.enrollments e on e.id = i.enrollment_id
    where e.campaign_id = c.id and i.status = 'vencido')::bigint as em_atraso_cents,
  (select count(*)
     from public.installments i join public.enrollments e on e.id = i.enrollment_id
    where e.campaign_id = c.id and i.status = 'vencido') as parcelas_vencidas,
  (select count(*)
     from public.enrollments e where e.campaign_id = c.id and e.signed_at is not null) as contratos_assinados,
  (select count(distinct i.enrollment_id)
     from public.installments i join public.enrollments e on e.id = i.enrollment_id
    where e.campaign_id = c.id and i.status = 'pago') as familias_pagantes
from public.campaigns c;

-- Alertas do dashboard.
create view public.v_dashboard_alerts with (security_invoker = true) as
select
  c.id as campaign_id,
  (select count(*) from public.enrollments e
    where e.campaign_id = c.id and e.status = 'link_aberto'
      and e.updated_at < now() - interval '24 hours') as conversas_travadas,
  (select count(distinct i.enrollment_id)
     from public.installments i join public.enrollments e on e.id = i.enrollment_id
    where e.campaign_id = c.id and i.status = 'vencido') as pagamentos_vencidos,
  (select count(*) from public.enrollments e
    where e.campaign_id = c.id and e.lost_at is null
      and (e.status = 'precisa_humano'
           or exists (select 1 from public.conversations cv where cv.enrollment_id = e.id and cv.handler = 'humano'))) as aguardando_humano,
  (select count(*) from public.webhook_events w where w.status = 'falhou') as falhas_webhook
from public.campaigns c;

-- Motor de mensagens (Dashboard e Automação).
create view public.v_queue_stats with (security_invoker = true) as
select
  c.id as campaign_id,
  count(q.id) filter (where q.status in ('pendente', 'processando'))                                  as na_fila,
  count(q.id) filter (where q.status = 'enviada' and q.sent_at >= public.local_day_start())            as enviadas_hoje,
  count(q.id) filter (where q.status = 'enviada' and q.sent_at >= now() - interval '1 hour')           as enviadas_ultima_hora,
  count(q.id) filter (where q.status = 'falhou' or (q.status = 'pendente' and q.retries > 0))          as falhas_retry,
  min(q.scheduled_for) filter (where q.status = 'pendente')                                            as proximo_envio,
  max(q.sent_at)                                                                                        as ultimo_envio
from public.campaigns c
left join public.message_queue q on q.campaign_id = c.id
group by c.id;

-- Gráfico "Mensagens por hora" (hoje, horário local).
create view public.v_hourly_throughput with (security_invoker = true) as
select
  q.campaign_id,
  extract(hour from q.sent_at at time zone 'America/Fortaleza')::int as hora,
  count(*)                                                           as enviadas
from public.message_queue q
where q.status = 'enviada' and q.sent_at >= public.local_day_start()
group by q.campaign_id, 2;

-- Próximos da fila (Automação).
create view public.v_queue_upcoming with (security_invoker = true) as
select
  q.id,
  q.campaign_id,
  q.scheduled_for,
  q.attempt_number,
  q.status,
  q.retries,
  t.name        as template_name,
  g.full_name   as guardian_name,
  s.full_name   as student_name,
  fc.name       as from_class_name
from public.message_queue q
join public.guardians g on g.id = q.guardian_id
left join public.message_templates t on t.id = q.template_id
left join public.enrollments e on e.id = q.enrollment_id
left join public.students s on s.id = e.student_id
left join public.classes fc on fc.id = e.from_class_id
where q.status in ('pendente', 'processando');

-- Central de atendimento.
create view public.v_conversation_list with (security_invoker = true) as
select
  cv.id,
  cv.guardian_id,
  g.full_name                                    as guardian_name,
  g.phone                                        as guardian_phone,
  cv.enrollment_id,
  s.full_name                                    as student_name,
  fc.name                                        as from_class_name,
  tg.name                                        as target_grade_name,
  e.status                                       as enrollment_status,
  public.journey_status_label(e.status)          as enrollment_status_label,
  e.attempts,
  c.max_attempts,
  cv.handler,
  cv.assigned_to,
  cv.ai_intent,
  cv.ai_sentiment,
  cv.last_message_at,
  cv.last_message_preview,
  cv.unread_count
from public.conversations cv
join public.guardians g on g.id = cv.guardian_id
left join public.enrollments e on e.id = cv.enrollment_id
left join public.campaigns c on c.id = e.campaign_id
left join public.students s on s.id = e.student_id
left join public.classes fc on fc.id = e.from_class_id
left join public.grades tg on tg.id = e.target_grade_id;

-- Séries e valores com vagas restantes (Configurações).
create view public.v_grade_offerings with (security_invoker = true) as
select
  o.id                 as offering_id,
  o.academic_year,
  g.id                 as grade_id,
  g.name               as grade_name,
  g.sort_order,
  pg.name              as from_grade_name,
  o.shifts,
  o.amount_cents,
  o.cash_amount_cents,
  o.seats_total,
  coalesce(t.taken, 0)::int                              as seats_taken,
  greatest(o.seats_total - coalesce(t.taken, 0), 0)::int as seats_available
from public.grade_offerings o
join public.grades g on g.id = o.grade_id
left join public.grades pg on pg.next_grade_id = g.id
left join lateral (
  select count(*) as taken
  from public.enrollments e
  join public.campaigns c on c.id = e.campaign_id
  where c.academic_year = o.academic_year
    and e.target_grade_id = o.grade_id
    and e.signed_at is not null
    and e.lost_at is null
) t on true;
