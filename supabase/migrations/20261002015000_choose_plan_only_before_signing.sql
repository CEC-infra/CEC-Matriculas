-- Depois de assinar, o plano não muda mais (as parcelas já foram geradas).
do $$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.onboarding_choose_plan(text,smallint)'::regprocedure);
  if position('já foram assinados' in v_def) = 0 then
    execute replace(v_def,
      $x$  select o into v_choice from jsonb_array_elements(public.payment_plan_choices(v_session.campaign_id, public.local_today())) o$x$,
      $x$  if not exists (
    select 1 from public.enrollment_onboarding_items oi join public.enrollments e on e.id = oi.enrollment_id
     where oi.onboarding_session_id = v_session.id and e.signed_at is null
  ) then raise exception 'Os contratos já foram assinados; as condições não podem mais ser alteradas' using errcode = 'P0001'; end if;
  select o into v_choice from jsonb_array_elements(public.payment_plan_choices(v_session.campaign_id, public.local_today())) o$x$);
  end if;
end $$;
