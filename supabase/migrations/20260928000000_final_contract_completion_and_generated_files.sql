-- Contrato final CEC: dados obrigatórios do preâmbulo e evidência do PDF
-- individual gerado antes da assinatura. O turno volta a ser solicitado
-- exclusivamente nesta etapa contratual, pois é exigido pelo documento.

alter table public.guardians
  add column if not exists rg text;

alter table public.document_acceptances
  add column if not exists generated_storage_path text,
  add column if not exists generated_document_hash text check (generated_document_hash is null or generated_document_hash ~ '^[0-9a-f]{64}$'),
  add column if not exists generated_at timestamptz,
  add column if not exists generation_data jsonb not null default '{}'::jsonb;

comment on column public.guardians.rg is 'RG informado pelo responsável para o preâmbulo do contrato.';
comment on column public.document_acceptances.generated_storage_path is 'Arquivo PDF individual, privado e imutável, gerado a partir da versão contratual.';
comment on column public.document_acceptances.generated_document_hash is 'SHA-256 do PDF individual efetivamente apresentado e assinado.';

-- O arquivo-base é a conversão sem alterações do Word final entregue pela escola.
-- A Edge Function valida este hash antes de gerar qualquer PDF individual.
update public.document_versions
   set is_current = false
 where document_id = (select id from public.documents where code = 'contrato_prestacao')
   and is_current;

insert into public.document_versions (document_id, version, pages, storage_path, sha256, is_current, published_at)
select id, 'v5-contrato-cec-final-2025', 6, '/contracts/contrato-matricula-cec-2025.pdf',
       'ffa54c5ade1db754031c556ed7011732496d571a1a241f7db2405671e2cf4ca0', true, now()
  from public.documents
 where code = 'contrato_prestacao';

create or replace function public.contract_required_data(p_contract_session_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'ready', not (
      nullif(trim(g.full_name), '') is null
      or nullif(trim(g.phone), '') is null
      or nullif(trim(g.rg), '') is null
      or nullif(trim(g.cpf), '') is null
      or nullif(trim(g.address), '') is null
      or exists (
        select 1
          from public.contract_session_enrollments cse2
          join public.enrollments e2 on e2.id = cse2.enrollment_id
          join public.students s2 on s2.id = e2.student_id
         where cse2.contract_session_id = cs.id
           and (nullif(trim(s2.full_name), '') is null or e2.target_grade_id is null or e2.target_shift is null)
      )
    ),
    'guardian', jsonb_build_object(
      'missing', jsonb_build_object(
        'full_name', nullif(trim(g.full_name), '') is null,
        'phone', nullif(trim(g.phone), '') is null,
        'rg', nullif(trim(g.rg), '') is null,
        'cpf', nullif(trim(g.cpf), '') is null,
        'address', nullif(trim(g.address), '') is null
      )
    ),
    'students', coalesce((
      select jsonb_agg(jsonb_build_object(
        'enrollment_id', e.id,
        'student_name', s.full_name,
        'grade', gr.name,
        'missing', jsonb_build_object(
          'student_name', nullif(trim(s.full_name), '') is null,
          'target_grade', e.target_grade_id is null,
          'target_shift', e.target_shift is null
        )
      ) order by s.full_name)
        from public.contract_session_enrollments cse
        join public.enrollments e on e.id = cse.enrollment_id
        join public.students s on s.id = e.student_id
        left join public.grades gr on gr.id = e.target_grade_id
       where cse.contract_session_id = cs.id
    ), '[]'::jsonb)
  )
    from public.contract_sessions cs
    join public.guardians g on g.id = cs.guardian_id
   where cs.id = p_contract_session_id;
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
  v_phone text;
  v_cpf text;
  v_shift public.shift;
  v_student_input jsonb;
  v_result jsonb;
begin
  select * into v_session
    from public.contract_sessions
   where token = trim(p_token)
     and status not in ('assinada', 'cancelada', 'expirada')
     and expires_at > now()
   for update;
  if not found then
    raise exception 'Link de contrato inválido ou expirado' using errcode = 'P0002';
  end if;

  select * into v_guardian from public.guardians where id = v_session.guardian_id for update;

  if nullif(trim(v_guardian.full_name), '') is null then
    if length(trim(coalesce(p_guardian ->> 'full_name', ''))) < 3 then
      raise exception 'Informe o nome completo do responsável' using errcode = '22023';
    end if;
    update public.guardians set full_name = trim(p_guardian ->> 'full_name') where id = v_guardian.id;
  end if;

  if nullif(trim(v_guardian.phone), '') is null then
    v_phone := public.normalize_phone_br(p_guardian ->> 'phone');
    if v_phone is null then raise exception 'Informe um telefone/WhatsApp válido' using errcode = '22023'; end if;
    update public.guardians set phone = v_phone where id = v_guardian.id;
  end if;

  if nullif(trim(v_guardian.rg), '') is null then
    if nullif(trim(coalesce(p_guardian ->> 'rg', '')), '') is null then
      raise exception 'Informe o RG do responsável' using errcode = '22023';
    end if;
    update public.guardians set rg = trim(p_guardian ->> 'rg') where id = v_guardian.id;
  end if;

  if nullif(trim(v_guardian.cpf), '') is null then
    v_cpf := regexp_replace(coalesce(p_guardian ->> 'cpf', ''), '\\D', '', 'g');
    if not public.is_valid_cpf(v_cpf) then
      raise exception 'Informe um CPF válido' using errcode = '22023';
    end if;
    update public.guardians set cpf = v_cpf where id = v_guardian.id;
  end if;

  if nullif(trim(v_guardian.address), '') is null then
    if nullif(trim(coalesce(p_guardian ->> 'address', '')), '') is null then
      raise exception 'Informe o endereço completo do responsável' using errcode = '22023';
    end if;
    update public.guardians set address = trim(p_guardian ->> 'address') where id = v_guardian.id;
  end if;

  for v_enrollment in
    select e.id, e.target_shift, e.target_grade_id, e.student_id, c.academic_year, s.full_name as student_name
      from public.contract_session_enrollments cse
      join public.enrollments e on e.id = cse.enrollment_id
      join public.campaigns c on c.id = e.campaign_id
      join public.students s on s.id = e.student_id
     where cse.contract_session_id = v_session.id
     for update of e, s
  loop
    v_student_input := coalesce(p_students -> v_enrollment.id::text, '{}'::jsonb);
    if nullif(trim(v_enrollment.student_name), '') is null then
      if length(trim(coalesce(v_student_input ->> 'student_name', ''))) < 3 then
        raise exception 'Informe o nome completo do aluno' using errcode = '22023';
      end if;
      update public.students set full_name = trim(v_student_input ->> 'student_name') where id = v_enrollment.student_id;
    end if;
    if v_enrollment.target_grade_id is null then
      raise exception 'A série pretendida precisa ser definida pela escola antes do contrato' using errcode = 'P0001';
    end if;
    if v_enrollment.target_shift is null then
      begin
        v_shift := lower(trim(coalesce(v_student_input ->> 'target_shift', '')))::public.shift;
      exception when others then
        raise exception 'Selecione um turno válido para o aluno' using errcode = '22023';
      end;
      if not exists (
        select 1 from public.grade_offerings go
         where go.academic_year = v_enrollment.academic_year
           and go.grade_id = v_enrollment.target_grade_id
           and v_shift = any(go.shifts)
      ) then
        raise exception 'O turno selecionado não está disponível para esta série' using errcode = '22023';
      end if;
      update public.enrollments set target_shift = v_shift where id = v_enrollment.id;
    end if;
  end loop;

  v_result := public.contract_required_data(v_session.id);
  if coalesce((v_result ->> 'ready')::boolean, false) is not true then
    raise exception 'Ainda há dados obrigatórios pendentes para gerar o contrato' using errcode = '22023';
  end if;

  insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
  select cse.enrollment_id, 'CONTRACT_DATA_COMPLETED', 'Dados do contrato confirmados',
         'Dados obrigatórios do responsável e do aluno foram confirmados para a geração do contrato.',
         'responsavel', jsonb_build_object('contract_session_id', v_session.id)
    from public.contract_session_enrollments cse
   where cse.contract_session_id = v_session.id;

  return v_result;
end $$;

create or replace function public.contract_open(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.contract_sessions; v_out jsonb;
begin
  select * into v_session from public.contract_sessions
   where token = trim(p_token) and status not in ('cancelada', 'expirada') and expires_at > now();
  if not found then raise exception 'Link de contrato inválido ou expirado' using errcode = 'P0002'; end if;
  update public.contract_sessions set first_opened_at = coalesce(first_opened_at, now()), last_opened_at = now(), open_count = open_count + 1 where id = v_session.id;
  if v_session.first_opened_at is null then
    insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
    select cse.enrollment_id, 'CONTRACT_OPENED', 'Página de contrato visitada', 'A família acessou a página de assinatura.', 'responsavel', jsonb_build_object('contract_session_id', v_session.id)
      from public.contract_session_enrollments cse where cse.contract_session_id = v_session.id;
  end if;
  select jsonb_build_object(
    'status', v_session.status,
    'email_masked', regexp_replace(v_session.confirmation_email, '^(.{1,2}).*(@.*)$', '\1***\2'),
    'email_verified', v_session.verification_verified_at is not null,
    'verification_sent_at', v_session.verification_sent_at,
    'email_delivery_status', (select q.status from public.email_queue q where q.contract_session_id = v_session.id order by q.created_at desc limit 1),
    'expires_at', v_session.expires_at,
    'guardian', jsonb_build_object('name', g.full_name),
    'required_data', public.contract_required_data(v_session.id),
    'enrollments', coalesce(jsonb_agg(jsonb_build_object(
      'id', e.id, 'student_name', s.full_name, 'grade', gr.name, 'shift', e.target_shift,
      'amount_cents', e.amount_cents, 'payment_plan', pp.name,
      'contract_generated', da.generated_storage_path is not null and da.generated_document_hash is not null,
      'contract', jsonb_build_object('title', ddoc.title, 'version', ddoc.version)
    ) order by s.full_name), '[]'::jsonb)
  ) into v_out
    from public.contract_session_enrollments cse
    join public.enrollments e on e.id = cse.enrollment_id
    join public.students s on s.id = e.student_id
    join public.grades gr on gr.id = e.target_grade_id
    join public.guardians g on g.id = v_session.guardian_id
    left join public.payment_plans pp on pp.id = e.payment_plan_id
    left join lateral (
      select da.generated_storage_path, da.generated_document_hash
        from public.document_acceptances da
       where da.enrollment_id = e.id and da.contract_session_id = v_session.id
       order by da.generated_at desc nulls last, da.created_at desc
       limit 1
    ) da on true
    join lateral (
      select d.id, d.title, dv.version
        from public.campaign_documents cd
        join public.documents d on d.id = cd.document_id and d.kind = 'contrato'
        join public.document_versions dv on dv.document_id = d.id and dv.is_current
       where cd.campaign_id = e.campaign_id and (dv.grade_id is null or dv.grade_id = e.target_grade_id)
       order by case when dv.grade_id = e.target_grade_id then 0 else 1 end limit 1
    ) ddoc on true
   where cse.contract_session_id = v_session.id group by g.full_name;
  return v_out;
end $$;

create or replace function public.contract_sign(p_token text, p_signer_full_name text, p_signature_image_data text, p_accepted boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_session public.contract_sessions;
  v_enrollment record;
  v_acceptance public.document_acceptances;
  v_signature_hash text;
  v_headers jsonb := coalesce(current_setting('request.headers', true), '{}')::jsonb;
  v_ip inet;
begin
  if p_accepted is not true then raise exception 'Confirme a leitura e o aceite do contrato' using errcode = '22023'; end if;
  if nullif(trim(p_signer_full_name), '') is null then raise exception 'Informe o nome de quem assina' using errcode = '22023'; end if;
  if p_signature_image_data is null or p_signature_image_data !~ '^data:image/(png|jpeg);base64,' or length(p_signature_image_data) not between 100 and 500000 then
    raise exception 'A assinatura desenhada é obrigatória' using errcode = '22023';
  end if;
  select * into v_session from public.contract_sessions where token = trim(p_token) for update;
  if not found or v_session.status in ('assinada', 'cancelada', 'expirada') or v_session.expires_at <= now() then raise exception 'Link de contrato inválido ou expirado' using errcode = 'P0002'; end if;
  if v_session.verification_verified_at is null then raise exception 'Confirme o código enviado por e-mail antes de assinar' using errcode = 'P0001'; end if;
  if coalesce((public.contract_required_data(v_session.id) ->> 'ready')::boolean, false) is not true then raise exception 'Conclua os dados obrigatórios antes de assinar' using errcode = 'P0001'; end if;
  begin v_ip := nullif(split_part(coalesce(v_headers ->> 'x-forwarded-for', ''), ',', 1), '')::inet; exception when others then v_ip := null; end;
  v_signature_hash := encode(extensions.digest(p_signature_image_data, 'sha256'), 'hex');
  for v_enrollment in
    select e.* from public.contract_session_enrollments cse join public.enrollments e on e.id = cse.enrollment_id
     where cse.contract_session_id = v_session.id
  loop
    select * into v_acceptance
      from public.document_acceptances da
     where da.enrollment_id = v_enrollment.id
       and da.contract_session_id = v_session.id
       and da.generated_storage_path is not null
       and da.generated_document_hash is not null
     for update;
    if not found then raise exception 'O PDF individual deste contrato ainda não foi gerado' using errcode = 'P0001'; end if;
    update public.document_acceptances
       set status = 'assinado', provider = 'cec_assinatura_interna', signer_full_name = trim(p_signer_full_name),
           signer_email = v_session.confirmation_email, email_verified_at = v_session.verification_verified_at,
           signature_image_data = p_signature_image_data, signature_image_sha256 = v_signature_hash,
           document_hash = v_acceptance.generated_document_hash, completed_at = now(), ip = v_ip,
           user_agent = v_headers ->> 'user-agent', device = v_headers ->> 'sec-ch-ua-mobile', updated_at = now()
     where id = v_acceptance.id;
    if v_enrollment.payment_plan_id is not null and not exists(select 1 from public.installments where enrollment_id = v_enrollment.id and status <> 'cancelado') then perform public.generate_installments(v_enrollment.id); end if;
    update public.enrollments set signed_at = now(), status = case when payment_plan_id is null then 'aguardando_pagamento' else status end where id = v_enrollment.id;
    insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
    values(v_enrollment.id, 'CONTRACT_SIGNED', 'Contrato assinado', 'Contrato individual assinado após confirmação por e-mail.', 'responsavel', jsonb_build_object('contract_session_id', v_session.id, 'signature_sha256', v_signature_hash, 'document_sha256', v_acceptance.generated_document_hash));
  end loop;
  update public.contract_sessions set status = 'assinada', signed_at = now() where id = v_session.id;
  return jsonb_build_object('ok', true, 'signed_at', now());
end $$;

revoke execute on function public.contract_required_data(uuid), public.contract_complete_required_data(text, jsonb, jsonb) from public;
grant execute on function public.contract_complete_required_data(text, jsonb, jsonb) to anon, authenticated;
