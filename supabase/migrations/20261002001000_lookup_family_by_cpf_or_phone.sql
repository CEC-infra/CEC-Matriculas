-- A identificação na matrícula nova pode ocorrer por CPF ou WhatsApp.
-- Quando os dois forem preenchidos, o CPF tem prioridade na seleção.

create or replace function public.onboarding_lookup_existing_family(
  p_token text,
  p_cpf text,
  p_phone text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_session public.enrollment_onboarding_sessions;
  v_guardian public.guardians;
  v_cpf text := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
  v_phone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
begin
  select * into v_session from public.enrollment_onboarding_sessions
   where token = p_token and flow = 'matricula_nova' and status <> 'cancelada' for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;

  if v_cpf !~ '^[0-9]{11}$' and length(v_phone) < 10 then
    return jsonb_build_object('found', false);
  end if;

  select * into v_guardian from public.guardians
   where (v_cpf ~ '^[0-9]{11}$' and cpf = v_cpf)
      or (length(v_phone) >= 10 and right(regexp_replace(phone, '\D', '', 'g'), 8) = right(v_phone, 8))
   order by case when v_cpf ~ '^[0-9]{11}$' and cpf = v_cpf then 0 else 1 end
   limit 1;
  if not found then return jsonb_build_object('found', false); end if;

  return jsonb_build_object(
    'found', true,
    'guardian', jsonb_build_object('name', v_guardian.full_name, 'cpf', v_guardian.cpf, 'phone', v_guardian.phone, 'email', v_guardian.email, 'address', v_guardian.address),
    'children', coalesce((
      select jsonb_agg(jsonb_build_object('name', s.full_name, 'current_grade', current_grade.name, 'target_grade', target_grade.name) order by s.full_name)
        from public.student_guardians sg
        join public.students s on s.id = sg.student_id
        left join public.classes current_class on current_class.id = s.current_class_id
        left join public.grades current_grade on current_grade.id = current_class.grade_id
        left join public.grades target_grade on target_grade.id = current_grade.next_grade_id
       where sg.guardian_id = v_guardian.id
    ), '[]'::jsonb)
  );
end $$;

create or replace function public.onboarding_start_rematricula_from_new_enrollment(
  p_token text,
  p_cpf text,
  p_phone text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_source public.enrollment_onboarding_sessions;
  v_session public.enrollment_onboarding_sessions;
  v_campaign public.campaigns;
  v_guardian public.guardians;
  v_cpf text := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
  v_phone text := regexp_replace(coalesce(p_phone, ''), '\D', '', 'g');
begin
  select * into v_source from public.enrollment_onboarding_sessions
   where token = p_token and flow = 'matricula_nova' and status <> 'cancelada' for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;
  if v_cpf !~ '^[0-9]{11}$' and length(v_phone) < 10 then
    raise exception 'Informe um CPF ou WhatsApp válido' using errcode = '22023';
  end if;

  select * into v_guardian from public.guardians
   where (v_cpf ~ '^[0-9]{11}$' and cpf = v_cpf)
      or (length(v_phone) >= 10 and right(regexp_replace(phone, '\D', '', 'g'), 8) = right(v_phone, 8))
   order by case when v_cpf ~ '^[0-9]{11}$' and cpf = v_cpf then 0 else 1 end
   limit 1;
  if not found then raise exception 'Não localizamos este responsável' using errcode = 'P0002'; end if;

  v_campaign := public.onboarding_campaign('rematricula');
  select * into v_session from public.enrollment_onboarding_sessions
   where campaign_id = v_campaign.id and guardian_id = v_guardian.id and flow = 'rematricula'
     and status not in ('cancelada', 'concluida')
   order by updated_at desc limit 1 for update;
  if not found then
    insert into public.enrollment_onboarding_sessions(campaign_id, guardian_id, flow, status, current_step, context)
    values (v_campaign.id, v_guardian.id, 'rematricula', 'filhos', 2,
      jsonb_build_object('identified_at', now(), 'originated_from_new_enrollment_token', p_token))
    returning * into v_session;
  else
    update public.enrollment_onboarding_sessions
       set status = case when v_session.current_step < 2 then 'filhos' else v_session.status end,
           current_step = greatest(v_session.current_step, 2), last_opened_at = now()
     where id = v_session.id returning * into v_session;
  end if;
  return public.onboarding_open(v_session.token);
end $$;
