-- "formulário iniciado" e "aguardando assinatura" compartilham a mesma
-- prioridade de jornada; a conclusão precisa promover explicitamente a etapa.
create or replace function public.matricula_link_complete(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_enrollment public.enrollments;
  v_guardian public.guardians;
  v_student public.students;
  v_was_completed boolean;
begin
  select e.* into v_enrollment
    from public.enrollment_links l
    join public.enrollments e on e.id = l.enrollment_id
    join public.campaigns c on c.id = e.campaign_id
   where l.token = p_token and l.revoked_at is null and l.expires_at > now() and c.kind = 'matricula_nova'
   for update of e;
  if not found then raise exception 'Link de matrícula inválido ou expirado' using errcode = 'P0002'; end if;
  select * into v_guardian from public.guardians where id = v_enrollment.guardian_id;
  select * into v_student from public.students where id = v_enrollment.student_id;
  if nullif(trim(v_guardian.full_name), '') is null
     or nullif(trim(v_guardian.email), '') is null
     or nullif(trim(v_guardian.phone), '') is null
     or nullif(trim(v_guardian.address), '') is null
     or nullif(trim(v_student.full_name), '') is null
     or v_enrollment.target_grade_id is null then
    raise exception 'Preencha nome, e-mail, WhatsApp, endereço do responsável e os dados do aluno antes de concluir.' using errcode = '22023';
  end if;
  v_was_completed := v_enrollment.form_completed_at is not null;
  update public.enrollments
     set form_completed_at = coalesce(form_completed_at, now()),
         status = case when status in ('pre_matricula', 'em_fila', 'contatada', 'conversando', 'precisa_humano', 'link_enviado', 'link_aberto', 'formulario_iniciado')
                       then 'aguardando_assinatura'::public.journey_status else status end
   where id = v_enrollment.id;
  if not v_was_completed then
    insert into public.enrollment_events(enrollment_id, code, title, body, actor)
    values(v_enrollment.id, 'PERSONAL_LINK_COMPLETED', 'Formulário concluído pelo responsável',
           'O responsável finalizou o formulário pelo link individual e a matrícula segue para assinatura.', 'responsavel');
  end if;
  return jsonb_build_object('ok', true, 'enrollment_id', v_enrollment.id, 'form_completed_at', coalesce(v_enrollment.form_completed_at, now()), 'status', 'aguardando_assinatura');
end $$;
