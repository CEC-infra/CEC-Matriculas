-- Modelo de teste fornecido pela escola, publicado sem alterações.
-- O arquivo é servido pelo app em /contracts/contrato-matricula-escolar-teste.pdf.

do $$
declare
  v_document_id uuid;
begin
  select id into v_document_id
    from public.documents
   where code = 'contrato_prestacao'
     and kind = 'contrato';

  if v_document_id is null then
    raise exception 'Documento de contrato padrão não encontrado';
  end if;

  update public.document_versions
     set is_current = false
   where document_id = v_document_id
     and grade_id is null
     and is_current;

  insert into public.document_versions (
    document_id, version, grade_id, pages, storage_path, sha256, is_current, published_at
  ) values (
    v_document_id,
    'v4-teste-pdf',
    null,
    2,
    '/contracts/contrato-matricula-escolar-teste.pdf',
    '9abd1b4f87f4c27bc30001674b2a927f600dd41ef6cdbfc1c58fa2014dfcff06',
    true,
    now()
  ) on conflict (document_id, version, grade_id)
  do update set
    pages = excluded.pages,
    storage_path = excluded.storage_path,
    sha256 = excluded.sha256,
    is_current = true,
    published_at = excluded.published_at;
end $$;
