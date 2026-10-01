-- Enquanto a assinatura ainda não foi solicitada, todos os dados que entram
-- no contrato podem ser conferidos e corrigidos pelo responsável. A cada
-- alteração o PDF rascunho é invalidado e precisa ser gerado novamente.

-- Turno é uma característica da turma configurada pela escola, não uma
-- escolha da família. A nomenclatura interna continua `manha`/`tarde`, mas a
-- interface e o contrato a apresentam como Matutino/Vespertino.
update public.grade_offerings offering
   set shifts = case
     when grade.code in ('grupo_2', 'grupo_3', 'infantil_4', 'infantil_5',
                         'ano_1', 'ano_2', 'ano_3', 'ano_4', 'ano_5')
       then array['tarde'::public.shift]
     when grade.code in ('ano_6', 'ano_7', 'ano_8', 'ano_9')
       then array['manha'::public.shift]
     else offering.shifts
   end,
       updated_at = now()
  from public.grades grade
 where grade.id = offering.grade_id
   and offering.academic_year = 2027
   and grade.code in ('grupo_2', 'grupo_3', 'infantil_4', 'infantil_5',
                      'ano_1', 'ano_2', 'ano_3', 'ano_4', 'ano_5',
                      'ano_6', 'ano_7', 'ano_8', 'ano_9');

create or replace function public.automatic_shift_for_grade(
  p_academic_year smallint,
  p_grade_id uuid
)
returns public.shift language sql stable security definer set search_path = '' as $$
  select case when cardinality(o.shifts) = 1 then o.shifts[1] else null end
    from public.grade_offerings o
   where o.academic_year = p_academic_year and o.grade_id = p_grade_id
$$;

-- Recupera jornadas abertas criadas antes da regra automática de turno.
update public.enrollments enrollment
   set target_shift = public.automatic_shift_for_grade(campaign.academic_year, enrollment.target_grade_id)
  from public.campaigns campaign
 where campaign.id = enrollment.campaign_id
   and enrollment.target_shift is null
   and enrollment.target_grade_id is not null
   and public.automatic_shift_for_grade(campaign.academic_year, enrollment.target_grade_id) is not null;

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
      or cs.confirmation_email !~* '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$'
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

create or replace function public.contract_complete_required_data(
  p_token text,
  p_guardian jsonb default '{}'::jsonb,
  p_students jsonb default '{}'::jsonb
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_session public.contract_sessions;
  v_guardian public.guardians;
  v_enrollment record;
  v_student_input jsonb;
  v_guardian_name text;
  v_phone text;
  v_rg text;
  v_cpf text;
  v_address text;
  v_email text;
  v_student_name text;
  v_target_grade uuid;
  v_shift public.shift;
  v_result jsonb;
begin
  select * into v_session from public.contract_sessions
   where token = trim(p_token)
     and status not in ('assinada', 'cancelada', 'expirada')
     and expires_at > now()
   for update;
  if not found then
    raise exception 'Os dados não podem mais ser alterados nesta sessão' using errcode = 'P0001';
  end if;

  select * into v_guardian from public.guardians where id = v_session.guardian_id for update;
  v_guardian_name := coalesce(nullif(trim(p_guardian ->> 'full_name'), ''), v_guardian.full_name);
  v_phone := public.normalize_phone_br(coalesce(nullif(trim(p_guardian ->> 'phone'), ''), v_guardian.phone));
  v_rg := coalesce(nullif(trim(p_guardian ->> 'rg'), ''), v_guardian.rg);
  v_cpf := regexp_replace(coalesce(nullif(trim(p_guardian ->> 'cpf'), ''), v_guardian.cpf, ''), '\D', '', 'g');
  v_address := coalesce(nullif(trim(p_guardian ->> 'address'), ''), v_guardian.address);
  v_email := lower(trim(coalesce(nullif(trim(p_guardian ->> 'email'), ''), v_session.confirmation_email, v_guardian.email, '')));
  if length(trim(coalesce(v_guardian_name, ''))) < 3 then raise exception 'Informe o nome completo do responsável' using errcode = '22023'; end if;
  if v_phone is null then raise exception 'Informe um telefone/WhatsApp válido' using errcode = '22023'; end if;
  if nullif(trim(coalesce(v_rg, '')), '') is null then raise exception 'Informe o RG do responsável' using errcode = '22023'; end if;
  if not public.is_valid_cpf(v_cpf) then raise exception 'Informe um CPF válido' using errcode = '22023'; end if;
  if nullif(trim(coalesce(v_address, '')), '') is null then raise exception 'Informe o endereço completo do responsável' using errcode = '22023'; end if;
  if v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Informe um e-mail válido para a confirmação' using errcode = '22023'; end if;

  begin
    update public.guardians
       set full_name = trim(v_guardian_name), phone = v_phone, rg = trim(v_rg), cpf = v_cpf,
           address = trim(v_address), email = v_email
     where id = v_guardian.id;
  exception when unique_violation then
      raise exception 'CPF, telefone ou e-mail já cadastrado para outro responsável. Fale com a secretaria.' using errcode = '23505';
  end;

  for v_enrollment in
    select e.id, e.student_id, e.target_grade_id, e.target_shift, e.campaign_id,
           c.academic_year, s.full_name as student_name
      from public.contract_session_enrollments cse
      join public.enrollments e on e.id = cse.enrollment_id
      join public.campaigns c on c.id = e.campaign_id
      join public.students s on s.id = e.student_id
     where cse.contract_session_id = v_session.id
     for update of e, s
  loop
    v_student_input := coalesce(p_students -> v_enrollment.id::text, '{}'::jsonb);
    v_student_name := coalesce(nullif(trim(v_student_input ->> 'student_name'), ''), v_enrollment.student_name);
    if length(trim(coalesce(v_student_name, ''))) < 3 then raise exception 'Informe o nome completo do aluno' using errcode = '22023'; end if;

    begin
      v_target_grade := coalesce(nullif(trim(v_student_input ->> 'target_grade_id'), '')::uuid, v_enrollment.target_grade_id);
    exception when invalid_text_representation then
      raise exception 'Selecione uma série válida para o aluno' using errcode = '22023';
    end;
    if v_target_grade is null or not exists (
      select 1 from public.grade_offerings o where o.academic_year = v_enrollment.academic_year and o.grade_id = v_target_grade
    ) then raise exception 'A série selecionada não está disponível para esta campanha' using errcode = '22023'; end if;

    v_shift := public.automatic_shift_for_grade(v_enrollment.academic_year, v_target_grade);
    if v_shift is null then
      raise exception 'A turma desta série precisa ter um único turno configurado pela escola' using errcode = 'P0001';
    end if;

    if not exists (
      select 1 from public.campaign_documents cd
      join public.documents d on d.id = cd.document_id and d.kind = 'contrato'
      join public.document_versions dv on dv.document_id = d.id and dv.is_current and dv.storage_path is not null and dv.sha256 is not null
       where cd.campaign_id = v_enrollment.campaign_id and (dv.grade_id is null or dv.grade_id = v_target_grade)
    ) then raise exception 'Não existe contrato publicado para a série selecionada' using errcode = 'P0001'; end if;

    update public.students set full_name = trim(v_student_name) where id = v_enrollment.student_id;
    update public.enrollments set target_grade_id = v_target_grade, target_shift = v_shift where id = v_enrollment.id;
  end loop;

  -- O arquivo anterior pode conter dados corrigidos. Ele continua privado no
  -- storage, mas deixa de ser acessível pela sessão e será sobrescrito quando
  -- a Edge Function gerar o novo rascunho.
  delete from public.document_acceptances
   where contract_session_id = v_session.id and status <> 'assinado';

  -- Se um código já tinha sido enviado, ele deixa de ser válido porque o PDF
  -- e os dados foram corrigidos. A tela pedirá um novo código após regenerar.
  update public.email_queue
     set status = 'cancelado', updated_at = now()
   where contract_session_id = v_session.id
     and status in ('pendente', 'processando');
  update public.contract_sessions
     set confirmation_email = v_email, status = 'pronta', verification_code_hash = null,
         verification_expires_at = null, verification_sent_at = null,
         verification_verified_at = null, verification_attempts = 0,
         updated_at = now()
   where id = v_session.id;

  v_result := public.contract_required_data(v_session.id);
  if coalesce((v_result ->> 'ready')::boolean, false) is not true then
    raise exception 'Ainda há dados obrigatórios pendentes para gerar o contrato' using errcode = '22023';
  end if;

  insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
  select cse.enrollment_id, 'CONTRACT_DATA_CONFIRMED', 'Dados do contrato confirmados',
         'Dados editáveis do responsável e aluno foram confirmados; o PDF será regenerado.',
         'responsavel', jsonb_build_object('contract_session_id', v_session.id)
    from public.contract_session_enrollments cse
   where cse.contract_session_id = v_session.id;
  return v_result;
end $$;

revoke execute on function public.contract_required_data(uuid), public.contract_complete_required_data(text, jsonb, jsonb) from public;
grant execute on function public.contract_complete_required_data(text, jsonb, jsonb) to anon, authenticated;
