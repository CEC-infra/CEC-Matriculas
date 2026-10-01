-- E-mail do código de assinatura com layout da marca. O banco grava qual
-- template usar e seus dados; a Edge Function dispatch-contract-emails monta o
-- HTML com a logo inline. html_body continua preenchido como fallback.

alter table public.email_queue
  add column if not exists template text,
  add column if not exists template_data jsonb;

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

  insert into public.email_queue (contract_session_id, recipient, subject, html_body, template, template_data)
  values (
    v_session.id,
    v_session.confirmation_email,
    'Seu código para assinar o contrato CEC: ' || v_code,
    '<p>Use o código <strong>' || v_code || '</strong> para confirmar sua identidade e assinar o contrato.</p><p>O código expira em 15 minutos.</p>',
    'contract_code',
    jsonb_build_object('code', v_code, 'expires_minutes', 15)
  );

  insert into public.enrollment_events(enrollment_id, code, title, body, actor, metadata)
  select cse.enrollment_id, 'CONTRACT_CODE_REQUESTED', 'Código de confirmação solicitado',
         'Código preparado e aguardando envio para o e-mail de assinatura.', 'sistema',
         jsonb_build_object('contract_session_id', v_session.id)
    from public.contract_session_enrollments cse
   where cse.contract_session_id = v_session.id;
end $$;
