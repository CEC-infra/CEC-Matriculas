-- A versão anterior escapava `\s` duas vezes nesta expressão. Isso fazia a
-- checagem de prontidão reprovar e-mails válidos e impedia gerar o contrato.
create or replace function public.contract_required_data(p_contract_session_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'ready', not (
      nullif(trim(g.full_name), '') is null
      or nullif(trim(g.phone), '') is null
      or nullif(trim(g.rg), '') is null
      or nullif(trim(g.cpf), '') is null
      or nullif(trim(g.address), '') is null
      or nullif(trim(cs.confirmation_email), '') is null
      or cs.confirmation_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'
      or exists (
        select 1
          from public.contract_session_enrollments cse2
          join public.enrollments e2 on e2.id = cse2.enrollment_id
          join public.students s2 on s2.id = e2.student_id
          join public.campaigns c2 on c2.id = e2.campaign_id
         where cse2.contract_session_id = cs.id
           and (nullif(trim(s2.full_name), '') is null or e2.target_grade_id is null
                or public.automatic_shift_for_grade(c2.academic_year, e2.target_grade_id) is null)
      )
    ),
    'guardian', jsonb_build_object(
      'values', jsonb_build_object(
        'full_name', g.full_name,
        'phone', g.phone,
        'rg', g.rg,
        'cpf', g.cpf,
        'address', g.address,
        'email', cs.confirmation_email
      ),
      'missing', jsonb_build_object(
        'full_name', nullif(trim(g.full_name), '') is null,
        'phone', nullif(trim(g.phone), '') is null,
        'rg', nullif(trim(g.rg), '') is null,
        'cpf', nullif(trim(g.cpf), '') is null,
        'address', nullif(trim(g.address), '') is null,
        'email', nullif(trim(cs.confirmation_email), '') is null
      )
    ),
    'students', coalesce((
      select jsonb_agg(jsonb_build_object(
        'enrollment_id', e.id,
        'student_name', s.full_name,
        'grade', current_grade.name,
        'values', jsonb_build_object(
          'student_name', s.full_name,
          'target_grade_id', e.target_grade_id,
          'target_shift', public.automatic_shift_for_grade(campaign.academic_year, e.target_grade_id)
        ),
        'available_grades', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', offering_grade.id,
            'name', offering_grade.name,
            'shifts', offering.shifts
          ) order by offering_grade.sort_order)
            from public.grade_offerings offering
            join public.grades offering_grade on offering_grade.id = offering.grade_id
           where offering.academic_year = campaign.academic_year
        ), '[]'::jsonb),
        'missing', jsonb_build_object(
          'student_name', nullif(trim(s.full_name), '') is null,
          'target_grade', e.target_grade_id is null,
          'target_shift', public.automatic_shift_for_grade(campaign.academic_year, e.target_grade_id) is null
        )
      ) order by s.full_name)
        from public.contract_session_enrollments cse
        join public.enrollments e on e.id = cse.enrollment_id
        join public.students s on s.id = e.student_id
        join public.campaigns campaign on campaign.id = e.campaign_id
        left join public.grades current_grade on current_grade.id = e.target_grade_id
       where cse.contract_session_id = cs.id
    ), '[]'::jsonb)
  )
    from public.contract_sessions cs
    join public.guardians g on g.id = cs.guardian_id
   where cs.id = p_contract_session_id
$$;
