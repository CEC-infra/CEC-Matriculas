-- Rematrícula de irmãos: uma sessão de assinatura para todos os filhos
-- selecionados. Cada aluno continua com o PDF, o hash e o aceite próprios
-- (document_acceptances por matrícula); só a cerimônia é única — um código
-- por e-mail e uma assinatura desenhada aplicada em cada contrato.
create or replace function public.onboarding_prepare_family_contract(p_token text, p_confirmation_email text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_session public.enrollment_onboarding_sessions;
  v_enrollment record;
  v_contract_id uuid;
  v_contract_token text;
  v_email text;
  v_campaign uuid;
  v_count integer := 0;
begin
  select * into v_session from public.enrollment_onboarding_sessions where token = trim(p_token) and status <> 'cancelada' for update;
  if not found then raise exception 'Jornada inválida ou expirada' using errcode = 'P0002'; end if;
  v_email := lower(trim(coalesce(nullif(p_confirmation_email, ''), (select email from public.guardians where id = v_session.guardian_id))));
  if v_email is null or v_email !~* '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then raise exception 'Informe um e-mail válido para confirmação' using errcode = '22023'; end if;

  for v_enrollment in
    select e.* from public.enrollment_onboarding_items oi
      join public.enrollments e on e.id = oi.enrollment_id
     where oi.onboarding_session_id = v_session.id
       and e.guardian_id = v_session.guardian_id
       and e.signed_at is null
     order by e.created_at
       for update of e
  loop
    if not exists (
      select 1 from public.campaign_documents cd
        join public.documents d on d.id = cd.document_id and d.kind = 'contrato'
        join public.document_versions dv on dv.document_id = d.id and dv.is_current and dv.storage_path is not null and dv.sha256 is not null
       where cd.campaign_id = v_enrollment.campaign_id and (dv.grade_id is null or dv.grade_id = v_enrollment.target_grade_id)
    ) then raise exception 'O PDF definitivo do contrato ainda não foi publicado pela escola' using errcode = 'P0001'; end if;

    if v_contract_id is null then
      update public.guardians set email = v_email where id = v_session.guardian_id and email is distinct from v_email;
      insert into public.contract_sessions(campaign_id, guardian_id, confirmation_email)
      values (v_enrollment.campaign_id, v_session.guardian_id, v_email)
      returning id, token into v_contract_id, v_contract_token;
    end if;

    -- Sessões abertas anteriores (individuais ou de família) deixam de valer.
    update public.contract_sessions cs set status = 'cancelada'
      from public.contract_session_enrollments cse
     where cse.contract_session_id = cs.id and cse.enrollment_id = v_enrollment.id
       and cs.id <> v_contract_id and cs.status in ('pronta', 'codigo_enviado', 'verificada');
    insert into public.contract_session_enrollments(contract_session_id, enrollment_id) values (v_contract_id, v_enrollment.id);
    update public.enrollments set status = 'aguardando_assinatura' where id = v_enrollment.id;
    v_count := v_count + 1;
  end loop;

  if v_count = 0 then raise exception 'Não há contratos pendentes nesta jornada' using errcode = 'P0001'; end if;
  return jsonb_build_object('token', v_contract_token, 'url', '/contrato/' || v_contract_token, 'contracts', v_count);
end $$;

revoke all on function public.onboarding_prepare_family_contract(text, text) from public;
grant execute on function public.onboarding_prepare_family_contract(text, text) to anon, authenticated;
