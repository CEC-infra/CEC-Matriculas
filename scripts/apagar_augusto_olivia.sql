-- Apaga o cadastro de teste do Augusto Santos Lopes e da Olívia Figueira dos
-- Santos Lopes (eram só teste). A jornada, o contrato e a conversa já foram
-- apagados pelo reset_teste_davi_augusto.sql. Rodar no SQL Editor.

do $$
declare
  v_augusto constant uuid := '80b5ae82-e861-49cf-9943-11f079df0706';
  v_olivia  constant uuid := '6545781a-47fa-4e03-b7a1-40a1dcb9c302';
begin
  if exists (select 1 from public.enrollments where guardian_id = v_augusto or student_id = v_olivia) then
    raise exception 'Ainda há matrícula do Augusto ou da Olívia. Rode antes o reset_teste_davi_augusto.sql.';
  end if;

  delete from public.message_queue where guardian_id = v_augusto;
  delete from public.conversations where guardian_id = v_augusto;
  delete from public.student_guardians where guardian_id = v_augusto or student_id = v_olivia;
  delete from public.students where id = v_olivia;
  delete from public.guardians where id = v_augusto;
end $$;

-- Conferência: os dois devem dar 0
select
  (select count(*) from public.guardians where id = '80b5ae82-e861-49cf-9943-11f079df0706') as augusto,
  (select count(*) from public.students where id = '6545781a-47fa-4e03-b7a1-40a1dcb9c302')  as olivia;
