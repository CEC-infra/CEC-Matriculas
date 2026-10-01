-- Painel: a equipe pode gerar um link de contrato conjunto para irmãos
-- (mesmo responsável e mesma campanha). Mesmas validações do contrato
-- individual; cada aluno mantém PDF, hash e aceite próprios.
create or replace function public.contract_create_family_session(p_enrollment_ids uuid[], p_confirmation_email text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_first public.enrollments;
  v_enrollment public.enrollments;
  v_guardian public.guardians;
  v_session_id uuid;
  v_token text;
  v_email text;
begin
  if not public.is_staff() then raise exception 'Apenas a equipe pode iniciar contratos' using errcode = '42501'; end if;
  if coalesce(cardinality(p_enrollment_ids), 0) = 0 then raise exception 'Selecione pelo menos um aluno' using errcode = '22023'; end if;

  select * into v_first from public.enrollments where id = p_enrollment_ids[1];
  if not found then raise exception 'Matrícula não encontrada' using errcode = 'P0002'; end if;
  if not exists (select 1 from public.campaigns where id = v_first.campaign_id and status = 'ativa') then raise exception 'A campanha desta matrícula não está ativa' using errcode = 'P0001'; end if;
  select * into v_guardian from public.guardians where id = v_first.guardian_id for update;
  v_email := lower(trim(coalesce(nullif(p_confirmation_email, ''), v_guardian.email)));
  if v_email is null or v_email !~* '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Informe um e-mail válido para confirmação da assinatura' using errcode = '22023'; end if;
  update public.guardians set email = v_email where id = v_guardian.id and email is distinct from v_email;

  insert into public.contract_sessions(campaign_id, guardian_id, confirmation_email, created_by)
  values (v_first.campaign_id, v_first.guardian_id, v_email, public.current_profile_id())
  returning id, token into v_session_id, v_token;

  for v_enrollment in select * from public.enrollments where id = any(p_enrollment_ids) order by created_at for update loop
    if v_enrollment.guardian_id <> v_first.guardian_id or v_enrollment.campaign_id <> v_first.campaign_id then
      raise exception 'Os alunos do contrato conjunto precisam ter o mesmo responsável e a mesma campanha' using errcode = 'P0001';
    end if;
    if v_enrollment.status in ('sem_interesse', 'opt_out', 'fora_campanha') or v_enrollment.completed_at is not null or v_enrollment.signed_at is not null then
      raise exception 'Uma das matrículas não está disponível para contrato' using errcode = 'P0001';
    end if;
    if v_enrollment.amount_cents is null then raise exception 'Defina o valor de todas as matrículas antes de iniciar o contrato' using errcode = 'P0001'; end if;
    if not exists (
      select 1 from public.campaign_documents cd
        join public.documents d on d.id = cd.document_id and d.kind = 'contrato'
        join public.document_versions dv on dv.document_id = d.id and dv.is_current and dv.storage_path is not null and dv.sha256 is not null
       where cd.campaign_id = v_enrollment.campaign_id and (dv.grade_id is null or dv.grade_id = v_enrollment.target_grade_id)
    ) then raise exception 'O PDF definitivo do contrato ainda não foi publicado pela escola' using errcode = 'P0001'; end if;

    update public.contract_sessions cs set status = 'cancelada'
      from public.contract_session_enrollments cse
     where cse.contract_session_id = cs.id and cse.enrollment_id = v_enrollment.id
       and cs.id <> v_session_id and cs.status in ('pronta', 'codigo_enviado', 'verificada');
    insert into public.contract_session_enrollments(contract_session_id, enrollment_id) values (v_session_id, v_enrollment.id);
    update public.enrollments set status = case when public.journey_rank(status) < public.journey_rank('aguardando_assinatura'::public.journey_status) then 'aguardando_assinatura'::public.journey_status else status end where id = v_enrollment.id;
    insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
    values (v_enrollment.id, 'CONTRACT_READY', 'Contrato preparado', 'A família recebeu uma etapa de assinatura conjunta com os irmãos.', 'sistema',
            jsonb_build_object('contract_session_id', v_session_id, 'family_contract', true, 'enrollments', cardinality(p_enrollment_ids)));
  end loop;

  return jsonb_build_object('token', v_token, 'expires_at', (select expires_at from public.contract_sessions where id = v_session_id));
end $$;

revoke all on function public.contract_create_family_session(uuid[], text) from public, anon;
grant execute on function public.contract_create_family_session(uuid[], text) to authenticated;
