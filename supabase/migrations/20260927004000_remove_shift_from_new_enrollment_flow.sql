-- A jornada deixa de solicitar ou exibir turno. Mantemos a coluna para não
-- apagar o histórico, mas novos cadastros por esta operação são gravados sem turno.

create or replace function public.staff_create_family_enrollment(
  p_guardian_cpf text,
  p_guardian_name text,
  p_guardian_phone text,
  p_guardian_email text,
  p_guardian_address text,
  p_student_name text,
  p_target_grade_id uuid,
  p_student_birth_date date,
  p_current_school text,
  p_source public.enrollment_origin,
  p_relationship text,
  p_guardian_notes text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_internal_shift public.shift;
  v_result jsonb;
  v_enrollment_id uuid;
begin
  if not public.is_staff() then
    raise exception 'Apenas a equipe pode cadastrar famílias' using errcode = '42501';
  end if;
  select o.shifts[1] into v_internal_shift
    from public.grade_offerings o
    join public.campaigns c on c.academic_year = o.academic_year
   where c.kind = 'matricula_nova' and c.status = 'ativa'
     and c.starts_on <= public.local_today()
     and (c.ends_on is null or c.ends_on >= public.local_today())
     and o.grade_id = p_target_grade_id
   order by c.starts_on desc
   limit 1;
  if v_internal_shift is null then
    raise exception 'A série não está disponível nesta campanha' using errcode = '22023';
  end if;
  v_result := public.staff_create_family_enrollment(
    p_guardian_cpf, p_guardian_name, p_guardian_phone, p_guardian_email, p_guardian_address,
    p_student_name, p_target_grade_id, v_internal_shift, p_student_birth_date, p_current_school,
    p_source, p_relationship, p_guardian_notes
  );
  v_enrollment_id := (v_result ->> 'id')::uuid;
  update public.enrollments set target_shift = null where id = v_enrollment_id;
  return v_result;
end $$;

revoke execute on function public.staff_create_family_enrollment(text, text, text, text, text, text, uuid, public.shift, date, text, public.enrollment_origin, text, text) from authenticated;
revoke execute on function public.staff_create_family_enrollment(text, text, text, text, text, text, uuid, date, text, public.enrollment_origin, text, text) from public, anon, authenticated;
grant execute on function public.staff_create_family_enrollment(text, text, text, text, text, text, uuid, date, text, public.enrollment_origin, text, text) to authenticated;
