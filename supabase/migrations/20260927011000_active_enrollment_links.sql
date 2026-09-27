-- Todo cadastro em campanha vigente recebe um link individual, sem marcar o
-- link como enviado até que a equipe efetivamente o encaminhe ao responsável.
create or replace function public.ensure_active_enrollment_link()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_ttl smallint;
begin
  select link_ttl_days into v_ttl
    from public.campaigns
   where id = new.campaign_id and status = 'ativa'
     and starts_on <= public.local_today() and (ends_on is null or ends_on >= public.local_today());
  if v_ttl is null or exists (select 1 from public.enrollment_links where enrollment_id = new.id and revoked_at is null) then
    return new;
  end if;
  insert into public.enrollment_links(enrollment_id, expires_at)
  values(new.id, now() + make_interval(days => v_ttl));
  insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
  values(new.id, 'LINK_CREATED', 'Link individual gerado', 'Link individual criado automaticamente para a matrícula.', 'sistema', jsonb_build_object('flow', (select kind::text from public.campaigns where id = new.campaign_id)));
  return new;
end $$;

drop trigger if exists enrollments_create_active_link on public.enrollments;
create trigger enrollments_create_active_link
  after insert on public.enrollments
  for each row execute function public.ensure_active_enrollment_link();

-- Gera os links das matrículas já existentes em campanhas abertas.
with inserted as (
  insert into public.enrollment_links(enrollment_id, expires_at)
  select e.id, now() + make_interval(days => c.link_ttl_days)
    from public.enrollments e
    join public.campaigns c on c.id = e.campaign_id
   where c.status = 'ativa' and c.starts_on <= public.local_today() and (c.ends_on is null or c.ends_on >= public.local_today())
     and e.completed_at is null and e.status not in ('sem_interesse', 'opt_out', 'fora_campanha')
     and not exists (select 1 from public.enrollment_links el where el.enrollment_id = e.id and el.revoked_at is null)
  returning enrollment_id
)
insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
select enrollment_id, 'LINK_CREATED', 'Link individual gerado', 'Link individual criado para a matrícula existente.', 'sistema', '{}'::jsonb
from inserted;

-- Mantém o modal de cadastro manual informado do link criado no mesmo commit.
create or replace function public.staff_create_family_enrollment(
  p_guardian_cpf text,
  p_guardian_name text,
  p_guardian_phone text,
  p_guardian_email text,
  p_guardian_address text,
  p_student_name text,
  p_target_grade_id uuid,
  p_student_birth_date date default null,
  p_current_school text default null,
  p_source public.enrollment_origin default 'outro',
  p_relationship text default null,
  p_guardian_notes text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_internal_shift public.shift;
  v_result jsonb;
  v_enrollment_id uuid;
  v_link_token text;
begin
  if not public.is_staff() then raise exception 'Apenas a equipe pode cadastrar famílias' using errcode = '42501'; end if;
  select o.shifts[1] into v_internal_shift
    from public.grade_offerings o join public.campaigns c on c.academic_year = o.academic_year
   where c.kind = 'matricula_nova' and c.status = 'ativa' and c.starts_on <= public.local_today()
     and (c.ends_on is null or c.ends_on >= public.local_today()) and o.grade_id = p_target_grade_id
   order by c.starts_on desc limit 1;
  if v_internal_shift is null then raise exception 'A série não está disponível nesta campanha' using errcode = '22023'; end if;
  v_result := public.staff_create_family_enrollment(
    p_guardian_cpf, p_guardian_name, p_guardian_phone, p_guardian_email, p_guardian_address,
    p_student_name, p_target_grade_id, v_internal_shift, p_student_birth_date, p_current_school,
    p_source, p_relationship, p_guardian_notes
  );
  v_enrollment_id := (v_result ->> 'id')::uuid;
  update public.enrollments set target_shift = null where id = v_enrollment_id;
  select token into v_link_token from public.enrollment_links
   where enrollment_id = v_enrollment_id and revoked_at is null order by created_at desc limit 1;
  return v_result || jsonb_build_object('link_token', v_link_token, 'link_path', '/matricula/' || v_link_token);
end $$;

revoke execute on function public.staff_create_family_enrollment(text, text, text, text, text, text, uuid, date, text, public.enrollment_origin, text, text) from public, anon, authenticated;
grant execute on function public.staff_create_family_enrollment(text, text, text, text, text, text, uuid, date, text, public.enrollment_origin, text, text) to authenticated;
