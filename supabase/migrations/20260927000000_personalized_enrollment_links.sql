-- Links retomáveis para os dois fluxos. A tabela enrollment_links já guarda
-- expiração, revogação e acessos; esta migração só completa as RPCs e o controle.

create or replace function public.create_personalized_enrollment_link(p_enrollment_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_enrollment public.enrollments;
  v_kind public.campaign_kind;
  v_token text;
begin
  if not public.is_staff() then
    raise exception 'Apenas a equipe pode gerar links individuais' using errcode = '42501';
  end if;
  select e.* into v_enrollment from public.enrollments e where e.id = p_enrollment_id for update;
  if not found or v_enrollment.status in ('sem_interesse', 'opt_out', 'fora_campanha') or v_enrollment.completed_at is not null then
    raise exception 'Matrícula indisponível para gerar link' using errcode = 'P0001';
  end if;
  select kind into v_kind from public.campaigns where id = v_enrollment.campaign_id;
  if not exists (select 1 from public.campaigns where id = v_enrollment.campaign_id and status = 'ativa') then
    raise exception 'A campanha desta matrícula não está ativa' using errcode = 'P0001';
  end if;

  v_token := public.create_enrollment_link(v_enrollment.id);
  insert into public.enrollment_events (enrollment_id, code, title, body, actor, metadata)
  values (v_enrollment.id, 'LINK_CREATED', 'Link individual gerado',
          'Link individual pronto para ser copiado e enviado ao responsável.', 'equipe',
          jsonb_build_object('flow', v_kind::text));
  return jsonb_build_object('token', v_token, 'kind', v_kind::text);
end $$;

create or replace function public.matricula_link_open(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_link public.enrollment_links;
  v_enrollment public.enrollments;
  v_out jsonb;
begin
  select l.* into v_link
    from public.enrollment_links l
    join public.enrollments e on e.id = l.enrollment_id
    join public.campaigns c on c.id = e.campaign_id
   where l.token = p_token and l.revoked_at is null and l.expires_at > now() and c.kind = 'matricula_nova';
  if not found then raise exception 'Link de matrícula inválido ou expirado' using errcode = 'P0002'; end if;

  update public.enrollment_links
     set open_count = open_count + 1,
         first_opened_at = coalesce(first_opened_at, now()),
         last_opened_at = now()
   where id = v_link.id;
  select * into v_enrollment from public.enrollments where id = v_link.enrollment_id;

  if v_link.first_opened_at is null then
    insert into public.enrollment_events (enrollment_id, code, title, body, actor, metadata)
    values (v_enrollment.id, 'LINK_OPENED', 'Link de matrícula aberto',
            'Primeira abertura do link individual de matrícula.', 'responsavel',
            jsonb_build_object('user_agent', nullif(current_setting('request.headers', true), '')::json ->> 'user-agent'));
  end if;
  if public.journey_rank(v_enrollment.status) < public.journey_rank('link_aberto'::public.journey_status) then
    update public.enrollments set status = 'link_aberto' where id = v_enrollment.id;
  end if;

  select jsonb_build_object(
    'enrollment_id', v_enrollment.id,
    'campaign', c.name,
    'guardian', jsonb_build_object('name', g.full_name, 'email', g.email, 'phone', g.phone),
    'student', jsonb_build_object('name', s.full_name, 'birth_date', s.birth_date, 'previous_school', s.previous_school),
    'target_grade_id', v_enrollment.target_grade_id,
    'target_shift', v_enrollment.target_shift,
    'payment_plan_id', v_enrollment.payment_plan_id,
    'offerings', (
      select coalesce(jsonb_agg(jsonb_build_object('grade_id', o.grade_id, 'name', gr.name, 'shifts', o.shifts, 'amount_cents', o.amount_cents) order by gr.sort_order), '[]'::jsonb)
      from public.grade_offerings o join public.grades gr on gr.id = o.grade_id
      where o.academic_year = c.academic_year
    ),
    'plans', (
      select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'description', p.description, 'installments', p.installments, 'discount_pct', p.discount_pct) order by p.sort_order), '[]'::jsonb)
      from public.payment_plans p where p.campaign_id = c.id and p.active
    )
  ) into v_out
  from public.campaigns c
  join public.guardians g on g.id = v_enrollment.guardian_id
  join public.students s on s.id = v_enrollment.student_id
  where c.id = v_enrollment.campaign_id;
  return v_out;
end $$;

create or replace function public.matricula_link_save(
  p_token text,
  p_guardian_name text,
  p_email text default null,
  p_phone text default null,
  p_student_name text default null,
  p_birth_date date default null,
  p_previous_school text default null,
  p_target_grade_id uuid default null,
  p_target_shift public.shift default null,
  p_payment_plan_id uuid default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_enrollment public.enrollments;
  v_phone text;
  v_amount integer;
begin
  select e.* into v_enrollment
    from public.enrollment_links l
    join public.enrollments e on e.id = l.enrollment_id
    join public.campaigns c on c.id = e.campaign_id
   where l.token = p_token and l.revoked_at is null and l.expires_at > now() and c.kind = 'matricula_nova'
   for update of e;
  if not found then raise exception 'Link de matrícula inválido ou expirado' using errcode = 'P0002'; end if;
  if nullif(trim(p_guardian_name), '') is null or nullif(trim(coalesce(p_student_name, '')), '') is null then
    raise exception 'Informe o nome do responsável e do aluno' using errcode = '22023';
  end if;
  if p_phone is not null and nullif(trim(p_phone), '') is not null then
    v_phone := public.normalize_phone_br(p_phone);
    if v_phone is null then raise exception 'Telefone inválido' using errcode = '22023'; end if;
  end if;
  if p_target_grade_id is not null then
    select o.amount_cents into v_amount
      from public.grade_offerings o join public.campaigns c on c.academic_year = o.academic_year
     where c.id = v_enrollment.campaign_id and o.grade_id = p_target_grade_id;
    if v_amount is null then raise exception 'Série indisponível para esta campanha' using errcode = '22023'; end if;
  end if;
  if p_payment_plan_id is not null and not exists (
    select 1 from public.payment_plans where id = p_payment_plan_id and campaign_id = v_enrollment.campaign_id and active
  ) then raise exception 'Condição de pagamento inválida' using errcode = '22023'; end if;

  begin
    update public.guardians
       set full_name = trim(p_guardian_name),
           email = coalesce(nullif(lower(trim(p_email)), ''), email),
           phone = coalesce(v_phone, phone)
     where id = v_enrollment.guardian_id;
  exception
    when unique_violation then raise exception 'Este telefone já está cadastrado para outro responsável. Fale com a secretaria.' using errcode = '23505';
    when check_violation then raise exception 'E-mail inválido' using errcode = '22023';
  end;
  update public.students
     set full_name = trim(p_student_name),
         birth_date = coalesce(p_birth_date, birth_date),
         previous_school = coalesce(nullif(trim(p_previous_school), ''), previous_school)
   where id = v_enrollment.student_id;
  update public.enrollments
     set target_grade_id = coalesce(p_target_grade_id, target_grade_id),
         target_shift = coalesce(p_target_shift, target_shift),
         payment_plan_id = coalesce(p_payment_plan_id, payment_plan_id),
         amount_cents = coalesce(v_amount, amount_cents),
         status = case when public.journey_rank(status) < public.journey_rank('formulario_iniciado'::public.journey_status)
                       then 'formulario_iniciado'::public.journey_status else status end
   where id = v_enrollment.id;
  insert into public.enrollment_events (enrollment_id, code, title, body, actor)
  values (v_enrollment.id, 'PERSONAL_LINK_SAVED', 'Dados salvos pelo responsável',
          'Dados da matrícula foram atualizados pelo link individual.', 'responsavel');
  return jsonb_build_object('ok', true, 'enrollment_id', v_enrollment.id);
end $$;

revoke execute on function public.create_personalized_enrollment_link(uuid), public.matricula_link_open(text), public.matricula_link_save(text, text, text, text, text, date, text, uuid, public.shift, uuid) from public, anon, authenticated;
grant execute on function public.create_personalized_enrollment_link(uuid) to authenticated;
grant execute on function public.matricula_link_open(text), public.matricula_link_save(text, text, text, text, text, date, text, uuid, public.shift, uuid) to anon, authenticated;
