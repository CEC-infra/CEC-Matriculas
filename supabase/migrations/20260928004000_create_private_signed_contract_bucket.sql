-- Os contratos preenchidos e assinados são documentos privados. A Edge Function
-- usa a service role para gravá-los; não há política de leitura direta do cliente.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('contract-files', 'contract-files', false, 5242880, array['application/pdf']::text[])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
