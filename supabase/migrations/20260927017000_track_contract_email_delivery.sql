-- A tela de assinatura só permite informar o código depois da confirmação
-- do provedor de e-mail. Reenvios invalidam filas pendentes anteriores.

create or replace function public.contract_issue_verification_code(p_session_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_session public.contract_sessions; v_code text;
begin
  select * into v_session from public.contract_sessions where id = p_session_id for update;
  if not found or v_session.status in ('assinada', 'cancelada', 'expirada') or v_session.expires_at <= now() then
    raise exception 'Sessão de contrato indisponível' using errcode = 'P0002';
  end if;

  update public.email_queue
     set status = 'cancelado'
   where contract_session_id = v_session.id
     and status = 'pendente';

  v_code := upper(substr(encode(extensions.gen_random_bytes(4), 'hex'), 1, 6));
  update public.contract_sessions
     set status = 'codigo_enviado',
         verification_code_hash = encode(extensions.digest(v_code || token, 'sha256'), 'hex'),
         verification_expires_at = now() + interval '15 minutes',
         verification_sent_at = now(),
         verification_attempts = 0
   where id = v_session.id;

  insert into public.email_queue (contract_session_id, recipient, subject, html_body)
  values (
    v_session.id,
    v_session.confirmation_email,
    'Confirme seu código para assinar o contrato CEC',
    '<p>Use o código <strong>' || v_code || '</strong> para confirmar sua identidade e assinar o contrato.</p><p>O código expira em 15 minutos.</p>'
  );

  insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
  select cse.enrollment_id, 'CONTRACT_CODE_REQUESTED', 'Código de confirmação solicitado',
         'Código preparado e aguardando envio para o e-mail de assinatura.', 'sistema',
         jsonb_build_object('contract_session_id', v_session.id)
    from public.contract_session_enrollments cse
   where cse.contract_session_id = v_session.id;
end $$;

create or replace function public.contract_open(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.contract_sessions; v_out jsonb;
begin
  select * into v_session from public.contract_sessions where token = p_token and status not in ('cancelada', 'expirada') and expires_at > now();
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
    'enrollments', coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'student_name', s.full_name, 'grade', gr.name, 'amount_cents', e.amount_cents, 'payment_plan', pp.name, 'contract', jsonb_build_object('title', ddoc.title, 'version', ddoc.version, 'storage_path', ddoc.storage_path)) order by s.full_name), '[]'::jsonb)
  ) into v_out
  from public.contract_session_enrollments cse
  join public.enrollments e on e.id = cse.enrollment_id
  join public.students s on s.id = e.student_id
  join public.grades gr on gr.id = e.target_grade_id
  join public.guardians g on g.id = v_session.guardian_id
  left join public.payment_plans pp on pp.id = e.payment_plan_id
  join lateral (
    select d.id, d.title, dv.version, dv.storage_path from public.campaign_documents cd
    join public.documents d on d.id = cd.document_id and d.kind = 'contrato'
    join public.document_versions dv on dv.document_id = d.id and dv.is_current
    where cd.campaign_id = e.campaign_id and (dv.grade_id is null or dv.grade_id = e.target_grade_id)
    order by case when dv.grade_id = e.target_grade_id then 0 else 1 end limit 1
  ) ddoc on true
  where cse.contract_session_id = v_session.id group by g.full_name;
  return v_out;
end $$;
