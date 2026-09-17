import { useOutletContext } from 'react-router-dom';
import { Badge, CardHead } from '../components/ui';
import DataState from '../components/DataState';
import { useAsyncData } from '../hooks/useAsyncData';
import { getEnrollments } from '../services/data';
import { dateTime, money, statusTone } from '../lib/format';

export default function AssinaturaPagamento() {
  const detail = useOutletContext();
  const { loading, data, error } = useAsyncData(getEnrollments, []);
  if (detail) {
    const { enrollment, documents = [], installments = [] } = detail;
    return <div className="grid grid--2" style={{ gap: 18, alignItems: 'start' }}><div className="card"><div className="card-title">Documentos da matrícula</div><div className="card-sub" style={{ marginBottom: 16 }}>Aceite e assinatura registrados para esta jornada.</div>{documents.length ? <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>{documents.map((item) => <div className="row-item" style={{ background: 'var(--surface)' }} key={item.id}><div className="who"><strong>{item.document_versions?.documents?.title || 'Documento'}</strong><span>{item.document_versions?.version || '—'} · {item.provider || 'sem provedor'}</span></div><Badge tone={statusTone(item.status)}>{item.status}</Badge></div>)}</div> : <div className="notice">Nenhum documento gerado ainda.</div>}</div><div className="card"><CardHead title="Parcelas geradas" right={<span className="meta">{enrollment.payment_plan_name || 'Sem condição escolhida'}</span>} />{installments.length ? <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>{installments.map((item) => <div className="row-item" style={{ background: 'var(--surface)' }} key={item.id}><div className="who"><strong>Parcela {item.number}</strong><span>{money(item.amount_cents)} · vence em {dateTime(item.due_date)}</span></div><Badge tone={statusTone(item.status)}>{item.status}</Badge></div>)}</div> : <div className="notice">As parcelas serão criadas depois da assinatura.</div>}</div></div>;
  }
  const completed = (data || []).filter((item) => item.signed_at || item.completed_at);
  return <DataState loading={loading} error={error} empty={!loading && !error && !completed.length}><div className="card"><CardHead title="Assinaturas e pagamentos" sub="Jornadas com documentos ou conclusão registrados" /><div className="table"><div className="table-head cols-matric"><div>Responsável</div><div>Aluno</div><div>Turma</div><div>Status</div><div>Condição</div><div>Atualizada em</div></div>{completed.map((item) => <div className="table-row cols-matric" key={item.id}><div className="cell-strong">{item.guardian_name}</div><div>{item.student_name}</div><div>{item.target_grade_name}</div><div><Badge tone={statusTone(item.status)}>{item.status_label}</Badge></div><div>{item.payment_plan_name || '—'}</div><div>{dateTime(item.updated_at)}</div></div>)}</div></div></DataState>;
}
