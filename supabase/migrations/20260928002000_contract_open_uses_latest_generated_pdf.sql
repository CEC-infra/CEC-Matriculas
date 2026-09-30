-- A sessão pode ter históricos de versões; a tela deve exibir apenas o PDF
-- individual mais recente daquela sessão e nunca duplicar o aluno na resposta.
create or replace function public.contract_open(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.contract_sessions; v_out jsonb;
begin
  select * into v_session from public.contract_sessions where token = trim(p_token) and status not in ('cancelada', 'expirada') and expires_at > now();
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
