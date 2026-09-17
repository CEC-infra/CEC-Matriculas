-- Rotinas agendadas (horários em UTC; America/Fortaleza = UTC-3).

create extension if not exists pg_cron;

-- 00:15 local: parcelas pendentes com vencimento passado viram "vencido".
select cron.schedule('cec-parcelas-vencidas', '15 3 * * *', $$select public.mark_overdue_installments()$$);

-- A cada 10 min: régua de follow-up. O envio em si respeita janela e tetos em claim_message_batch().
select cron.schedule('cec-regua-follow-ups', '*/10 * * * *', $$select public.schedule_follow_ups()$$);
