import { useMemo, useState } from 'react';
import { Badge } from '../components/ui';
import DataState from '../components/DataState';
import { useAsyncData } from '../hooks/useAsyncData';
import { getActiveEnrollmentLinks, getEnrollments } from '../services/data';
import { dateTime, statusTone } from '../lib/format';

const pathFor = (kind) => kind === 'rematricula' ? 'rematricula' : 'matricula';
const labelFor = (kind) => kind === 'rematricula' ? 'Rematrícula' : 'Matrícula';

export default function LinkGenerator() {
  const [message, setMessage] = useState('');
  const enrollments = useAsyncData(getEnrollments, []);
  const savedLinks = useAsyncData(getActiveEnrollmentLinks, []);
  const savedByEnrollment = useMemo(() => Object.fromEntries((savedLinks.data || []).map((link) => [link.enrollment_id, link.token])), [savedLinks.data]);
  const rows = useMemo(() => (enrollments.data || []).filter((item) => savedByEnrollment[item.id] && !item.completed_at), [enrollments.data, savedByEnrollment]);

  function copy(url) {
    navigator.clipboard?.writeText(url);
    setMessage('Link copiado.');
  }

  return <DataState loading={enrollments.loading || savedLinks.loading} error={enrollments.error || savedLinks.error} empty={!enrollments.loading && !enrollments.error && !rows.length}>
    <div className="stack">
      <div className="card"><div className="card-title">Links das famílias</div><div className="card-sub" style={{ marginBottom: 16 }}>Consulte e copie os links já vinculados a cada responsável. A tag identifica a modalidade.</div>{message ? <div className="notice"><span>{message}</span></div> : null}</div>
      <div className="card"><div className="table"><div className="table-head cols-matric"><div>Responsável</div><div>Aluno</div><div>Tipo</div><div>Série</div><div>Atualizada em</div><div>Link</div></div>{rows.map((row) => {
        const url = `${window.location.origin}/${pathFor(row.campaign_kind)}/${savedByEnrollment[row.id]}`;
        return <div className="table-row cols-matric" key={row.id}><div className="cell-stack"><strong className="cell-strong">{row.guardian_name}</strong><span>{row.guardian_phone}</span></div><div>{row.student_name}</div><div><Badge tone={row.campaign_kind === 'rematricula' ? 'warn' : 'new'}>{labelFor(row.campaign_kind)}</Badge></div><div>{row.target_grade_name}</div><div>{dateTime(row.updated_at)}</div><div><div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}><button className="btn btn--primary" type="button" onClick={() => copy(url)}>Copiar link</button><code style={{ fontSize: 10, overflowWrap: 'anywhere' }}>{url}</code></div></div></div>;
      })}</div></div>
    </div>
  </DataState>;
}
