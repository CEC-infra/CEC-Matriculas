-- Ao (re)confirmar os alunos, a escolha de pagamento anterior deixa de valer:
-- a família volta à etapa Valores e escolhe de novo para os filhos atuais.
-- Patch cirúrgico sobre a definição vigente (20261002004000), sem recopiá-la.
do $$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.onboarding_select_rematricula_children(text,uuid[])'::regprocedure);
  if position('payment_choice' in v_def) > 0 then return; end if;
  if position('set status = ''contratos'', current_step = 3, last_opened_at = now()' in v_def) = 0 then
    raise exception 'onboarding_select_rematricula_children mudou; revise este patch';
  end if;
  execute replace(v_def,
    'set status = ''contratos'', current_step = 3, last_opened_at = now()',
    'set status = ''contratos'', current_step = 3, last_opened_at = now(), context = context - ''values_confirmed_at'' - ''payment_choice''');
end $$;
