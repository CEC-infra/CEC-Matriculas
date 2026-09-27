import { useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { Badge, Chips } from '../components/ui';
import DataState from '../components/DataState';
import { useAsyncData } from '../hooks/useAsyncData';
import { createPersonalizedEnrollmentLink, getActiveEnrollmentLinks, getEnrollments } from '../services/data';
import { dateTime, statusTone } from '../lib/format';

const kinds = [
  { value: 'rematricula', label: 'Rematrícula', path: 'rematricula' },
  { value: 'matricula_nova', label: 'Matrícula nova', path: 'matricula' }
];

export default function LinkGenerator() {
  const [params, setParams] = useSearchParams();
  const [busyId, setBusyId] = useState('');
  const [generatedLinks, setGeneratedLinks] = useState({});
  const [message, setMessage] = useState('');
  const selectedKind = kinds.some((item) => item.value === params.get('tipo')) ? params.get('tipo') : 'rematricula';
  const { loading, data, error, refresh } = useAsyncData(() => getEnrollments({ kind: selectedKind }), [selectedKind]);
  const savedLinks = useAsyncData(getActiveEnrollmentLinks, []);
  const config = kinds.find((item) => item.value === selectedKind);
  const rows = useMemo(() => (data || []).filter((item) => !item.completed_at && !['sem_interesse', 'opt_out', 'fora_campanha'].includes(item.status)), [data]);
  const savedByEnrollment = useMemo(() => Object.fromEntries((savedLinks.data || []).map((link) => [link.enrollment_id, `${window.location.origin}/${config.path}/${link.token}`])), [savedLinks.data, config.path]);

  async function generate(row) {
    setBusyId(row.id); setMessage('');
    try {
      const result = await createPersonalizedEnrollmentLink(row.id);
      const path = result.kind === 'rematricula' ? 'rematricula' : 'matricula';
      const url = `${window.location.origin}/${path}/${result.token}`;
      setGeneratedLinks((current) => ({ ...current, [row.id]: url }));
      setMessage('Link individual gerado. Copie-o e envie ao responsável pelo canal de atendimento.');
      await Promise.all([refresh(), savedLinks.refresh()]);
    } catch (err) { setMessage(err.message || 'Não foi possível gerar o link.'); }
    finally { setBusyId(''); }
  }

  function copy(url) {
    navigator.clipboard?.writeText(url);
    setMessage('Link copiado.');
  }

  return <DataState loading={loading || savedLinks.loading} error={error || savedLinks.error} empty={!loading && !error && !rows.length}><div className="stack"><div className="card"><div className="card-title">Links individuais</div><div className="card-sub" style={{ marginBottom: 16 }}>Cada link é seguro, expira em 30 dias e permite ao responsável retomar o preenchimento de onde parou.</div><Chips items={kinds.map((item) => item.label)} active={config.label} onSelect={(label) => setParams({ tipo: kinds.find((item) => item.label === label).value })} />{message ? <div className="notice" style={{ marginTop: 16 }}><span>{message}</span></div> : null}</div><div className="card"><div className="table"><div className="table-head cols-matric"><div>Responsável</div><div>Aluno</div><div>Série</div><div>Status</div><div>Atualizada em</div><div>Link</div></div>{rows.map((row) => { const url = generatedLinks[row.id] || savedByEnrollment[row.id]; return <div className="table-row cols-matric" key={row.id}><div className="cell-stack"><strong className="cell-strong">{row.guardian_name}</strong><span>{row.guardian_phone}</span></div><div>{row.student_name}</div><div>{row.target_grade_name}</div><div><Badge tone={statusTone(row.status)}>{row.status_label}</Badge></div><div>{dateTime(row.updated_at)}</div><div>{url ? <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}><button className="btn btn--primary" type="button" onClick={() => copy(url)}>Copiar link</button><code style={{ fontSize: 10, overflowWrap: 'anywhere' }}>{url}</code></div> : <button className="btn btn--primary" type="button" disabled={busyId === row.id} onClick={() => generate(row)}>{busyId === row.id ? 'Gerando…' : 'Gerar link'}</button>}</div></div>; })}</div></div></div></DataState>;
}
