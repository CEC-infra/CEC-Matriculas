-- Contrato 2027 (versão enxuta) passa a ser o modelo das assinaturas.
-- O hash é o do arquivo public/contracts/contrato-cec-2027.pdf; o gerador
-- recusa qualquer modelo que não bata com a versão atual. Rascunhos do
-- modelo 2025 ainda não assinados são refeitos ao abrir a página do contrato.

update public.document_versions v set is_current = false
  from public.documents d
 where d.id = v.document_id and d.code = 'contrato_prestacao' and v.is_current;

insert into public.document_versions (document_id, version, pages, storage_path, sha256, is_current, published_at)
select d.id, 'v6-contrato-cec-2027', 2, '/contracts/contrato-cec-2027.pdf',
       '1b7bd029787c49955681ee1cc439f5e905afc1880495aa791c7e07a498eb109c', true, now()
  from public.documents d where d.code = 'contrato_prestacao';
