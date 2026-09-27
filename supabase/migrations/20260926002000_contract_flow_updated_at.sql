create trigger contract_sessions_set_updated_at
  before update on public.contract_sessions
  for each row execute function public.set_updated_at();

create trigger email_queue_set_updated_at
  before update on public.email_queue
  for each row execute function public.set_updated_at();

create trigger payment_dispatches_set_updated_at
  before update on public.payment_dispatches
  for each row execute function public.set_updated_at();
