-- O PDF apresentado ao responsável é preservado e, após o aceite, uma cópia
-- final recebe a assinatura no campo CONTRATANTE(S). Ambos os arquivos ficam
-- privados; os metadados permanecem vinculados à matrícula e ao responsável.

alter table public.document_acceptances
  add column if not exists signed_storage_path text,
  add column if not exists signed_document_hash text check (signed_document_hash is null or signed_document_hash ~ '^[0-9a-f]{64}$'),
  add column if not exists signed_pdf_at timestamptz;

comment on column public.document_acceptances.signed_storage_path is 'PDF final com a assinatura desenhada no campo CONTRATANTE(S), mantido em bucket privado.';
comment on column public.document_acceptances.signed_document_hash is 'SHA-256 do PDF final assinado.';

create or replace function public.contract_finalize_signed_pdf(
  p_token text,
  p_signer_full_name text,
  p_signature_image_data text,
  p_accepted boolean,
  p_ip text default null,
  p_user_agent text default null,
  p_device text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_session public.contract_sessions;
  v_enrollment record;
  v_acceptance public.document_acceptances;
  v_signature_hash text;
  v_ip inet;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Finalização disponível somente pelo serviço de assinatura' using errcode = '42501';
  end if;
  if p_accepted is not true then raise exception 'Confirme a leitura e o aceite do contrato' using errcode = '22023'; end if;
  if nullif(trim(p_signer_full_name), '') is null then raise exception 'Informe o nome de quem assina' using errcode = '22023'; end if;
  if p_signature_image_data is null or p_signature_image_data !~ '^data:image/(png|jpeg);base64,' or length(p_signature_image_data) not between 100 and 500000 then
    raise exception 'A assinatura desenhada é obrigatória' using errcode = '22023';
  end if;
  select * into v_session from public.contract_sessions where token = trim(p_token) for update;
  if not found or v_session.status in ('assinada', 'cancelada', 'expirada') or v_session.expires_at <= now() then raise exception 'Link de contrato inválido ou expirado' using errcode = 'P0002'; end if;
  if v_session.verification_verified_at is null then raise exception 'Confirme o código enviado por e-mail antes de assinar' using errcode = 'P0001'; end if;
  if coalesce((public.contract_required_data(v_session.id) ->> 'ready')::boolean, false) is not true then raise exception 'Conclua os dados obrigatórios antes de assinar' using errcode = 'P0001'; end if;
  begin v_ip := nullif(split_part(coalesce(p_ip, ''), ',', 1), '')::inet; exception when others then v_ip := null; end;
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
       and da.signed_storage_path is not null
       and da.signed_document_hash is not null
     for update;
    if not found then raise exception 'O PDF assinado deste contrato não foi encontrado' using errcode = 'P0001'; end if;
    update public.document_acceptances
       set status = 'assinado', provider = 'cec_assinatura_interna', signer_full_name = trim(p_signer_full_name),
           signer_email = v_session.confirmation_email, email_verified_at = v_session.verification_verified_at,
           signature_image_data = p_signature_image_data, signature_image_sha256 = v_signature_hash,
           document_hash = v_acceptance.signed_document_hash, completed_at = now(), ip = v_ip,
           user_agent = p_user_agent, device = p_device, updated_at = now()
     where id = v_acceptance.id;
    if v_enrollment.payment_plan_id is not null and not exists(select 1 from public.installments where enrollment_id = v_enrollment.id and status <> 'cancelado') then perform public.generate_installments(v_enrollment.id); end if;
    update public.enrollments set signed_at = now(), status = case when payment_plan_id is null then 'aguardando_pagamento' else status end where id = v_enrollment.id;
    insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
    values(v_enrollment.id, 'CONTRACT_SIGNED', 'Contrato assinado', 'PDF individual assinado após confirmação por e-mail.', 'responsavel', jsonb_build_object('contract_session_id', v_session.id, 'signature_sha256', v_signature_hash, 'document_sha256', v_acceptance.signed_document_hash, 'signed_pdf_at', v_acceptance.signed_pdf_at));
  end loop;
  update public.contract_sessions set status = 'assinada', signed_at = now() where id = v_session.id;
  return jsonb_build_object('ok', true, 'signed_at', now());
end $$;

-- O cliente não pode concluir a assinatura diretamente: somente a Edge Function
-- pode fazê-lo depois de inserir a assinatura no PDF privado.
revoke execute on function public.contract_sign(text, text, text, boolean) from public, anon, authenticated;
revoke execute on function public.contract_finalize_signed_pdf(text, text, text, boolean, text, text, text) from public, anon, authenticated;
grant execute on function public.contract_finalize_signed_pdf(text, text, text, boolean, text, text, text) to service_role;
