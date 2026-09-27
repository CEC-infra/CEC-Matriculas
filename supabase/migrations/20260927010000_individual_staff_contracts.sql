-- A equipe também gera uma sessão por aluno; irmãos não compartilham mais a mesma assinatura.
create or replace function public.contract_create_session(p_enrollment_id uuid, p_confirmation_email text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_enrollment public.enrollments; v_guardian public.guardians; v_session_id uuid; v_token text; v_email text;
begin
  if not public.is_staff() then raise exception 'Apenas a equipe pode iniciar contratos' using errcode = '42501'; end if;
  select * into v_enrollment from public.enrollments where id = p_enrollment_id for update;
  if not found or v_enrollment.status in ('sem_interesse', 'opt_out', 'fora_campanha') or v_enrollment.completed_at is not null then raise exception 'Matrícula não está disponível para contrato' using errcode = 'P0001'; end if;
  if not exists (select 1 from public.campaigns where id = v_enrollment.campaign_id and status = 'ativa') then raise exception 'A campanha desta matrícula não está ativa' using errcode = 'P0001'; end if;
  if v_enrollment.amount_cents is null then raise exception 'Defina o valor da matrícula antes de iniciar o contrato' using errcode = 'P0001'; end if;
  select * into v_guardian from public.guardians where id = v_enrollment.guardian_id for update;
  v_email := lower(trim(coalesce(nullif(p_confirmation_email, ''), v_guardian.email)));
  if v_email is null or v_email !~* '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$' then raise exception 'Informe um e-mail válido para confirmação da assinatura' using errcode = '22023'; end if;
  if not exists (select 1 from public.campaign_documents cd join public.documents d on d.id = cd.document_id and d.kind = 'contrato' join public.document_versions dv on dv.document_id = d.id and dv.is_current and dv.storage_path is not null and dv.sha256 is not null where cd.campaign_id = v_enrollment.campaign_id and (dv.grade_id is null or dv.grade_id = v_enrollment.target_grade_id)) then raise exception 'O PDF definitivo do contrato ainda não foi publicado pela escola' using errcode = 'P0001'; end if;
  update public.guardians set email = v_email where id = v_guardian.id and email is distinct from v_email;
  update public.contract_sessions cs set status = 'cancelada' from public.contract_session_enrollments cse where cse.contract_session_id = cs.id and cse.enrollment_id = v_enrollment.id and cs.status in ('pronta', 'codigo_enviado', 'verificada');
  insert into public.contract_sessions(campaign_id, guardian_id, confirmation_email, created_by) values(v_enrollment.campaign_id, v_enrollment.guardian_id, v_email, public.current_profile_id()) returning id, token into v_session_id, v_token;
  insert into public.contract_session_enrollments(contract_session_id, enrollment_id) values(v_session_id, v_enrollment.id);
  update public.enrollments set status = case when public.journey_rank(status) < public.journey_rank('aguardando_assinatura'::public.journey_status) then 'aguardando_assinatura'::public.journey_status else status end where id = v_enrollment.id;
  insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata) values(v_enrollment.id, 'CONTRACT_READY', 'Contrato preparado', 'A família recebeu uma etapa individual de assinatura.', 'sistema', jsonb_build_object('contract_session_id', v_session_id));
  return jsonb_build_object('token', v_token, 'expires_at', (select expires_at from public.contract_sessions where id = v_session_id));
end $$;
