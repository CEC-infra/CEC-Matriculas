import { useState } from 'react';
import { useOutletContext } from 'react-router-dom';
import { Badge, CardHead } from '../components/ui';
import DataState from '../components/DataState';
import { useAsyncData } from '../hooks/useAsyncData';
import { getContractSessions, getEnrollments, startContract } from '../services/data';
import { dateTime, money, statusTone } from '../lib/format';

export default function AssinaturaPagamento() {
  const detail = useOutletContext();
  const { loading, data, error } = useAsyncData(getEnrollments, []);
  const contracts = useAsyncData(getContractSessions, []);
  const [email, setEmail] = useState('');
  const [contractLink, setContractLink] = useState('');
  const [message, setMessage] = useState('');
  const [starting, setStarting] = useState(false);
  async function createContract(enrollment) {
    setStarting(true); setMessage('');
    try {
      const result = await startContract(enrollment.id, email || enrollment.guardian_email || null);
      const url = `${window.location.origin}/contrato/${result.token}`;
      setContractLink(url);
      setMessage('Contrato preparado e código de confirmação colocado na fila de e-mail. Copie o link para a família.');
    } catch (err) { setMessage(err.message || 'Não foi possível preparar o contrato.'); }
    finally { setStarting(false); }
  }
  if (detail) {
    const { enrollment, documents = [], installments = [] } = detail;
    return <div className="grid grid--2" style={{ gap: 18, alignItems: 'start' }}><div className="stack"><div className="card"><div className="card-title">Iniciar contrato</div><div className="card-sub" style={{ marginBottom: 16 }}>Confirme o e-mail do responsável. O contrato reúne os filhos ativos da mesma campanha.</div><label>E-mail para confirmação<input className="input" type="email" placeholder={enrollment.guardian_email || 'responsavel@email.com'} value={email} onChange={(event) => setEmail(event.target.value)} /></label><button type="button" className="btn btn--primary" style={{ marginTop: 14 }} onClick={() => createContract(enrollment)} disabled={starting || Boolean(enrollment.completed_at)}>{starting ? 'Preparando…' : 'Preparar contrato e e-mail'}</button>{contractLink ? <div className="notice" style={{ marginTop: 14, alignItems: 'flex-start', flexDirection: 'column' }}><span>Link individual do contrato</span><code style={{ overflowWrap: 'anywhere' }}>{contractLink}</code><button type="button" className="btn" onClick={() => navigator.clipboard?.writeText(contractLink)}>Copiar link</button></div> : null}{message ? <div className="notice" style={{ marginTop: 14 }}><span>{message}</span></div> : null}</div><div className="card"><div className="card-title">Documentos da matrícula</div><div className="card-sub" style={{ marginBottom: 16 }}>Aceite e assinatura registrados para esta jornada.</div>{documents.length ? <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>{documents.map((item) => <div className="row-item" style={{ background: 'var(--surface)' }} key={item.id}><div className="who"><strong>{item.document_versions?.documents?.title || 'Documento'}</strong><span>{item.document_versions?.version || '—'} · {item.provider || 'sem provedor'}</span></div><Badge tone={statusTone(item.status)}>{item.status}</Badge></div>)}</div> : <div className="notice">Nenhum documento gerado ainda.</div>}</div></div><div className="card"><CardHead title="Parcelas geradas" right={<span className="meta">{enrollment.payment_plan_name || 'Sem condição escolhida'}</span>} />{installments.length ? <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>{installments.map((item) => <div className="row-item" style={{ background: 'var(--surface)' }} key={item.id}><div className="who"><strong>Parcela {item.number}</strong><span>{money(item.amount_cents)} · vence em {dateTime(item.due_date)}</span></div><Badge tone={statusTone(item.status)}>{item.status}</Badge></div>)}</div> : <div className="notice">As parcelas serão criadas depois da assinatura.</div>}</div></div>;
  }
  const completed = (data || []).filter((item) => item.signed_at || item.completed_at);
  const pendingContracts = (contracts.data || []).filter((item) => item.status !== 'assinada');
  return <DataState loading={loading || contracts.loading} error={error || contracts.error} empty={!loading && !contracts.loading && !error && !contracts.error && !completed.length && !pendingContracts.length}><div className="stack"><div className="card"><CardHead title="Contratos em andamento" sub="Famílias que chegaram à página de contrato e ainda não concluíram" /><div className="table"><div className="table-head cols-matric"><div>Responsável</div><div>Campanha</div><div>Filhos</div><div>Etapa</div><div>Visitas</div><div>Última atividade</div></div>{pendingContracts.length ? pendingContracts.map((item) => <div className="table-row cols-matric" key={item.id}><div className="cell-strong">{item.guardian_name}</div><div>{item.campaign_name}</div><div>{item.students_count}</div><div><Badge tone={statusTone(item.status)}>{item.status}</Badge></div><div>{item.open_count || 0}</div><div>{dateTime(item.last_opened_at || item.created_at)}</div></div>) : <div className="notice">Nenhuma assinatura pendente de contrato.</div>}</div></div><div className="card"><CardHead title="Assinaturas e pagamentos" sub="Jornadas com documentos ou conclusão registrados" /><div className="table"><div className="table-head cols-matric"><div>Responsável</div><div>Aluno</div><div>Turma</div><div>Status</div><div>Condição</div><div>Atualizada em</div></div>{completed.map((item) => <div className="table-row cols-matric" key={item.id}><div className="cell-strong">{item.guardian_name}</div><div>{item.student_name}</div><div>{item.target_grade_name}</div><div><Badge tone={statusTone(item.status)}>{item.status_label}</Badge></div><div>{item.payment_plan_name || '—'}</div><div>{dateTime(item.updated_at)}</div></div>)}</div></div></div></DataState>;
}
