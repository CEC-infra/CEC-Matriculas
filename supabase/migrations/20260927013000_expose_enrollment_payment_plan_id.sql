-- O painel precisa do ID para marcar a condição já escolhida no seletor.
create or replace view public.v_enrollment_list with (security_invoker = true) as
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
  e.updated_at,
  g.email                                  as guardian_email,
  e.signed_at,
  e.paid_at,
  e.payment_plan_id,
  e.form_completed_at
from public.enrollments e
join public.campaigns c  on c.id = e.campaign_id
join public.guardians g  on g.id = e.guardian_id
join public.students s   on s.id = e.student_id
join public.grades tg    on tg.id = e.target_grade_id
left join public.classes fc       on fc.id = e.from_class_id
left join public.payment_plans pp on pp.id = e.payment_plan_id;
