-- Zera os testes de Davi (matrícula nova) e Augusto (rematrícula) para
-- refazerem o fluxo completo até o Asaas. Rodar no SQL Editor do Supabase.
--
-- Davi Santos Lopes: tudo foi criado pelo próprio fluxo de matrícula nova
--   (responsável, Leona, Pirata, Mel e Dino). Apaga tudo, inclusive o cadastro.
-- Augusto Santos Lopes: a Olívia é aluna da base da escola. Mantém o
--   responsável, a aluna e o vínculo; apaga só a jornada de 2027 (matrícula,
--   contrato, parcela) e a conversa do WhatsApp, para a IA começar do zero.
--
-- Um bloco só (DO): se qualquer passo falhar, nada é apagado. O SQL Editor
-- não mantém tabela temporária entre comandos, por isso tudo fica aqui dentro.

do $$
declare
  v_davi    constant uuid := 'cc8c2fff-6c5d-40b9-84cb-77d387e41c78';
  v_augusto constant uuid := '80b5ae82-e861-49cf-9943-11f079df0706';
  v_guardians uuid[] := array['cc8c2fff-6c5d-40b9-84cb-77d387e41c78', '80b5ae82-e861-49cf-9943-11f079df0706']::uuid[];
  v_enrollments uuid[];
  v_students uuid[];
begin
  select coalesce(array_agg(id), '{}') into v_enrollments
    from public.enrollments where guardian_id = any (v_guardians);

  -- Alunos que só o Davi tem (os criados no teste de matrícula nova)
  select coalesce(array_agg(sg.student_id), '{}') into v_students
    from public.student_guardians sg
   where sg.guardian_id = v_davi
     and not exists (select 1 from public.student_guardians other
                      where other.student_id = sg.student_id and other.guardian_id <> v_davi);

  -- Jornada, contrato e cobrança das matrículas de teste
  delete from public.enrollment_onboarding_items where enrollment_id = any (v_enrollments);
  delete from public.enrollment_onboarding_sessions where guardian_id = any (v_guardians);
  delete from public.contract_session_enrollments where enrollment_id = any (v_enrollments);
  delete from public.contract_sessions where guardian_id = any (v_guardians);
  delete from public.document_acceptances where enrollment_id = any (v_enrollments);
  delete from public.installments where enrollment_id = any (v_enrollments);
  delete from public.message_queue where guardian_id = any (v_guardians);
  delete from public.enrollments where id = any (v_enrollments);

  -- Conversas do WhatsApp (as mensagens vão junto)
  delete from public.conversations where guardian_id = any (v_guardians);

  -- Augusto volta a ser só o cadastro da base, sem cliente do Asaas
  update public.guardians set asaas_customer_id = null where id = v_augusto;

  -- Davi: cadastro e alunos criados pelo fluxo de matrícula nova
  delete from public.guardians where id = v_davi;
  delete from public.students where id = any (v_students);

  raise notice 'Apagados: % matrícula(s), % aluno(s) de teste', cardinality(v_enrollments), cardinality(v_students);
end $$;

-- Conferência: tudo zerado, Augusto e Olívia mantidos
select
  (select count(*) from public.guardians where id = 'cc8c2fff-6c5d-40b9-84cb-77d387e41c78')                 as davi_cadastro,
  (select count(*) from public.students where full_name in ('Leona', 'Pirata', 'Mel', 'Dino'))              as alunos_teste,
  (select count(*) from public.enrollments where guardian_id = '80b5ae82-e861-49cf-9943-11f079df0706')       as augusto_matriculas,
  (select count(*) from public.student_guardians where guardian_id = '80b5ae82-e861-49cf-9943-11f079df0706') as augusto_alunos_mantidos;
