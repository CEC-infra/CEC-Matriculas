import { useEffect, useState } from 'react';
import { useNavigate, useOutletContext } from 'react-router-dom';
import { Badge, CardHead } from '../components/ui';
import DataState from '../components/DataState';
import { useAsyncData } from '../hooks/useAsyncData';
import { getContractSessions, getEnrollments, getPaymentPlans, setEnrollmentPaymentPlan, startContract } from '../services/data';
import { dateTime, money, statusTone } from '../lib/format';

const closedStatuses = ['sem_interesse', 'opt_out', 'fora_campanha'];

function ContractSetup({ enrollment, documents, installments }) {
  const plans = useAsyncData(() => getPaymentPlans(enrollment.campaign_id), [enrollment.campaign_id]);
  const [email, setEmail] = useState(enrollment.guardian_email || '');
  const [selectedPlan, setSelectedPlan] = useState(enrollment.payment_plan_id || '');
  const [contractLink, setContractLink] = useState('');
  const [message, setMessage] = useState('');
  const [savingPlan, setSavingPlan] = useState(false);
  const [starting, setStarting] = useState(false);

  useEffect(() => {
    setEmail(enrollment.guardian_email || '');
    setSelectedPlan(enrollment.payment_plan_id || '');
    setContractLink('');
    setMessage('');
  }, [enrollment.id, enrollment.guardian_email, enrollment.payment_plan_id]);

  async function savePlan() {
    if (!selectedPlan) { setMessage('Escolha uma condição de pagamento antes de continuar.'); return; }
    setSavingPlan(true); setMessage('');
    try {
      const result = await setEnrollmentPaymentPlan(enrollment.id, selectedPlan);
      setMessage(`Condição salva: ${result.payment_plan_name}. Agora o contrato pode ser preparado.`);
    } catch (err) { setMessage(err.message || 'Não foi possível salvar a condição de pagamento.'); }
    finally { setSavingPlan(false); }
  }
  async function createContract() {
    const confirmationEmail = (email || enrollment.guardian_email || '').trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(confirmationEmail)) {
      setMessage('Informe um e-mail válido para receber a confirmação da assinatura.');
      return;
    }
    setStarting(true); setMessage('');
    try {
      const result = await startContract(enrollment.id, confirmationEmail);
      const url = `${window.location.origin}/contrato/${result.token}`;
      setContractLink(url);
      setMessage('Contrato individual preparado. Copie o link para a família; o código será enviado quando ela iniciar a assinatura.');
    } catch (err) { setMessage(err.message || 'Não foi possível preparar o contrato.'); }
    finally { setStarting(false); }
  }

  return <div className="contract-setup-layout">
    <div className="stack">
      <section className="card contract-setup-card">
        <div className="contract-setup-card__head"><div><div className="card-title">Preparar contrato individual</div><div className="card-sub">Revise a condição e o e-mail que receberá a confirmação de assinatura.</div></div><span className="badge badge--info">{enrollment.student_name}</span></div>
        <div className="contract-setup-card__fields">
          <div className="field"><label>Condição de pagamento <span className="contract-setup-card__optional">Opcional nesta etapa</span></label><select className="control" value={selectedPlan} onChange={(event) => setSelectedPlan(event.target.value)} disabled={plans.loading || Boolean(enrollment.completed_at)}><option value="">Definir depois</option>{plans.data?.map((plan) => <option key={plan.id} value={plan.id}>{plan.name} · {plan.description || `${plan.installments}x`}</option>)}</select><span className="contract-setup-card__hint">{selectedPlan ? 'A condição já selecionada pode ser alterada antes do contrato.' : 'A forma de pagamento poderá ser definida após a assinatura.'}</span><button type="button" className="btn contract-setup-card__secondary" onClick={savePlan} disabled={savingPlan || !selectedPlan || Boolean(enrollment.completed_at)}>{savingPlan ? 'Salvando…' : 'Salvar condição'}</button></div>
          <div className="field"><label>E-mail para confirmação</label><input className="control" type="email" value={email} onChange={(event) => setEmail(event.target.value)} required /><span className="contract-setup-card__hint">O código de confirmação será enviado para este endereço quando o responsável iniciar a assinatura.</span></div>
        </div>
        <div className="contract-setup-card__action"><div><strong>Próxima etapa</strong><span>Gerar o link individual de contrato para {enrollment.student_name}.</span></div><button type="button" className="btn btn--primary" onClick={createContract} disabled={starting || Boolean(enrollment.completed_at)}>{starting ? 'Preparando…' : 'Preparar link do contrato'}</button></div>
        {contractLink ? <div className="notice contract-setup-card__notice"><span>Link individual do contrato</span><code>{contractLink}</code><button type="button" className="btn" onClick={() => navigator.clipboard?.writeText(contractLink)}>Copiar link</button></div> : null}
        {message ? <div className="notice contract-setup-card__notice"><span>{message}</span></div> : null}
      </section>
      <div className="card"><div className="card-title">Documentos da matrícula</div><div className="card-sub" style={{ marginBottom: 16 }}>Aceite e assinatura registrados para esta jornada.</div>{documents.length ? <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>{documents.map((item) => <div className="row-item" style={{ background: 'var(--surface)' }} key={item.id}><div className="who"><strong>{item.document_versions?.documents?.title || 'Documento'}</strong><span>{item.document_versions?.version || '—'} · {item.provider || 'sem provedor'}</span></div><Badge tone={statusTone(item.status)}>{item.status}</Badge></div>)}</div> : <div className="notice">Nenhum documento gerado ainda.</div>}</div>
    </div>
    <div className="stack"><div className="card"><CardHead title="Parcelas geradas" right={<span className="meta">{enrollment.payment_plan_name || 'A definir após assinatura'}</span>} />{installments.length ? <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>{installments.map((item) => <div className="row-item" style={{ background: 'var(--surface)' }} key={item.id}><div className="who"><strong>Parcela {item.number}</strong><span>{money(item.amount_cents)} · vence em {dateTime(item.due_date)}</span></div><Badge tone={statusTone(item.status)}>{item.status}</Badge></div>)}</div> : <div className="notice">As parcelas serão criadas depois da assinatura e da escolha de pagamento.</div>}</div></div>
  </div>;
}

export default function AssinaturaPagamento() {
  const detail = useOutletContext();
  const navigate = useNavigate();
  const enrollments = useAsyncData(getEnrollments, []);
  const contracts = useAsyncData(getContractSessions, []);
  if (detail) return <ContractSetup enrollment={detail.enrollment} documents={detail.documents || []} installments={detail.installments || []} />;

  const data = enrollments.data || [];
  const sessions = contracts.data || [];
  const completed = data.filter((item) => item.signed_at || item.completed_at);
  const pendingContracts = sessions.filter((item) => item.status !== 'assinada' && item.status !== 'cancelada' && item.status !== 'expirada');
  const preparing = data.filter((item) => !item.completed_at && !closedStatuses.includes(item.status) && !sessions.some((session) => session.campaign_id === item.campaign_id && session.guardian_id === item.guardian_id));
  return <DataState loading={enrollments.loading || contracts.loading} error={enrollments.error || contracts.error} empty={false}><div className="stack"><div className="card"><CardHead title="Matrículas aguardando preparo" sub="Defina a condição de pagamento e prepare o contrato." /><div className="table"><div className="table-head cols-matric"><div>Responsável</div><div>Aluno</div><div>Campanha</div><div>Condição</div><div>Etapa</div><div /></div>{preparing.length ? preparing.map((item) => <div className="table-row cols-matric" key={item.id} onClick={() => navigate(`/familias/${item.id}/assinatura`)}><div className="cell-strong">{item.guardian_name}</div><div>{item.student_name}</div><div>{item.campaign_name}</div><div>{item.payment_plan_name || 'Definir condição'}</div><div><Badge tone={statusTone(item.status)}>{item.status_label}</Badge></div><div className="cell-open is-secondary">Preparar →</div></div>) : <div className="notice">Não há matrículas aguardando preparo.</div>}</div></div><div className="card"><CardHead title="Contratos em andamento" sub="Famílias que chegaram à página de contrato e ainda não concluíram" /><div className="table"><div className="table-head cols-matric"><div>Responsável</div><div>Campanha</div><div>Filhos</div><div>Etapa</div><div>Visitas</div><div>Última atividade</div></div>{pendingContracts.length ? pendingContracts.map((item) => <div className="table-row cols-matric" key={item.id}><div className="cell-strong">{item.guardian_name}</div><div>{item.campaign_name}</div><div>{item.students_count}</div><div><Badge tone={statusTone(item.status)}>{item.status}</Badge></div><div>{item.open_count || 0}</div><div>{dateTime(item.last_opened_at || item.created_at)}</div></div>) : <div className="notice">Nenhuma assinatura pendente de contrato.</div>}</div></div><div className="card"><CardHead title="Assinaturas e pagamentos" sub="Jornadas com contrato assinado ou matrícula concluída" /><div className="table"><div className="table-head cols-matric"><div>Responsável</div><div>Aluno</div><div>Turma</div><div>Status</div><div>Condição</div><div>Atualizada em</div></div>{completed.length ? completed.map((item) => <div className="table-row cols-matric" key={item.id} onClick={() => navigate(`/familias/${item.id}/assinatura`)}><div className="cell-strong">{item.guardian_name}</div><div>{item.student_name}</div><div>{item.target_grade_name}</div><div><Badge tone={statusTone(item.status)}>{item.status_label}</Badge></div><div>{item.payment_plan_name || '—'}</div><div>{dateTime(item.updated_at)}</div></div>) : <div className="notice">Nenhum contrato assinado ou pagamento registrado.</div>}</div></div></div></DataState>;
}
