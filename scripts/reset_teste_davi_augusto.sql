-- Zera os testes de Davi (matrícula nova) e Augusto (rematrícula) para
-- refazerem o fluxo completo até o Asaas. Rodar no SQL Editor do Supabase.
--
-- Davi Santos Lopes: tudo foi criado pelo próprio fluxo de matrícula nova
--   (responsável, Leona, Pirata, Mel e Dino). Apaga tudo, inclusive o cadastro.
-- Augusto Santos Lopes: a Olívia é aluna da base da escola. Mantém o
--   responsável, a aluna e o vínculo; apaga só a jornada de 2027 (matrícula,
--   contrato, parcela) e a conversa do WhatsApp, para a IA começar do zero.
--
-- Tudo numa transação: se qualquer passo falhar, nada é apagado.

begin;

create temp table reset_guardians on commit drop as
select id, full_name from public.guardians
 where id in ('cc8c2fff-6c5d-40b9-84cb-77d387e41c78',   -- Davi
              '80b5ae82-e861-49cf-9943-11f079df0706');  -- Augusto

create temp table reset_enrollments on commit drop as
select e.id from public.enrollments e where e.guardian_id in (select id from reset_guardians);

-- Jornada, contrato e cobrança das matrículas de teste
delete from public.enrollment_onboarding_items where enrollment_id in (select id from reset_enrollments);
delete from public.enrollment_onboarding_sessions where guardian_id in (select id from reset_guardians);
delete from public.contract_session_enrollments where enrollment_id in (select id from reset_enrollments);
delete from public.contract_sessions where guardian_id in (select id from reset_guardians);
delete from public.document_acceptances where enrollment_id in (select id from reset_enrollments);
delete from public.installments where enrollment_id in (select id from reset_enrollments);
delete from public.message_queue where guardian_id in (select id from reset_guardians);
delete from public.enrollments where id in (select id from reset_enrollments);

-- Conversas do WhatsApp (as mensagens vão junto)
delete from public.conversations where guardian_id in (select id from reset_guardians);

-- Augusto volta a ser só o cadastro da base, sem cliente do Asaas
update public.guardians set asaas_customer_id = null
 where id = '80b5ae82-e861-49cf-9943-11f079df0706';

-- Davi: cadastro e alunos criados pelo fluxo de matrícula nova
create temp table reset_students on commit drop as
select sg.student_id id from public.student_guardians sg
 where sg.guardian_id = 'cc8c2fff-6c5d-40b9-84cb-77d387e41c78'
   and not exists (select 1 from public.student_guardians other
                    where other.student_id = sg.student_id
                      and other.guardian_id <> 'cc8c2fff-6c5d-40b9-84cb-77d387e41c78');
delete from public.guardians where id = 'cc8c2fff-6c5d-40b9-84cb-77d387e41c78';
delete from public.students where id in (select id from reset_students);

-- Conferência: tudo zerado, Augusto e Olívia mantidos
select
  (select count(*) from public.guardians where full_name = 'Davi Santos Lopes')                     as davi_cadastro,
  (select count(*) from public.students where full_name in ('Leona', 'Pirata', 'Mel', 'Dino'))      as alunos_teste,
  (select count(*) from public.enrollments where guardian_id = '80b5ae82-e861-49cf-9943-11f079df0706') as augusto_matriculas,
  (select count(*) from public.student_guardians where guardian_id = '80b5ae82-e861-49cf-9943-11f079df0706') as augusto_alunos_mantidos;

commit;
