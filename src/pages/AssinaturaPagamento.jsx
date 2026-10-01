import { useEffect, useState } from 'react';
import { useNavigate, useOutletContext } from 'react-router-dom';
import { Badge, CardHead } from '../components/ui';
import DataState from '../components/DataState';
import { useAsyncData } from '../hooks/useAsyncData';
import { getContractSessions, getEnrollments, startContract, startFamilyContract } from '../services/data';
import { dateTime, money, statusTone } from '../lib/format';

const closedStatuses = ['sem_interesse', 'opt_out', 'fora_campanha'];

function ContractSetup({ enrollment, documents, installments, siblings = [] }) {
  const available = siblings.filter((item) => !item.signed_at && !item.completed_at && !closedStatuses.includes(item.status));
  const [included, setIncluded] = useState(() => available.map((item) => item.id));
  const family = included.length > 0;
  const familyTotal = [enrollment, ...available.filter((item) => included.includes(item.id))].reduce((sum, item) => sum + (Number(item.amount_cents) || 0), 0);
  const [email, setEmail] = useState(enrollment.guardian_email || '');
  const [contractLink, setContractLink] = useState('');
  const [message, setMessage] = useState('');
  const [starting, setStarting] = useState(false);

  useEffect(() => {
    setEmail(enrollment.guardian_email || '');
    setContractLink('');
    setMessage('');
  }, [enrollment.id, enrollment.guardian_email]);

  async function createContract() {
    const confirmationEmail = (email || enrollment.guardian_email || '').trim();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(confirmationEmail)) {
      setMessage('Informe um e-mail válido para receber a confirmação da assinatura.');
      return;
    }
    setStarting(true); setMessage('');
    try {
      const result = family
        ? await startFamilyContract([enrollment.id, ...included], confirmationEmail)
        : await startContract(enrollment.id, confirmationEmail);
      const url = `${window.location.origin}/contrato/${result.token}`;
      setContractLink(url);
      setMessage(family
        ? `Contrato conjunto preparado para ${included.length + 1} alunos. A família assina uma vez só; cada aluno fica com o seu PDF.`
        : 'Contrato individual preparado. Copie o link para a família; o código será enviado quando ela iniciar a assinatura.');
    } catch (err) { setMessage(err.message || 'Não foi possível preparar o contrato.'); }
    finally { setStarting(false); }
  }

  return <div className="contract-setup-layout">
    <div className="stack">
      <section className="card contract-setup-card">
        <div className="contract-setup-card__head"><div><div className="card-title">{family ? 'Preparar contrato conjunto' : 'Preparar contrato individual'}</div><div className="card-sub">Informe o e-mail que receberá a confirmação de assinatura.</div></div><span className="badge badge--info">{enrollment.student_name}</span></div>
        <div className="contract-setup-card__fields">
          <div className="notice contract-setup-card__notice"><span><strong>Pagamento</strong><br />Na rematrícula assinada até 31/10, vale o valor de outubro e a família escolhe: boleto ou cartão em 3x (nov, dez e jan) ou 2x (dez e jan), ou Pix à vista em janeiro. A partir de 01/11, tabela 2027 em Pix à vista em janeiro.</span></div>
          <div className="field"><label>E-mail para confirmação</label><input className="control" type="email" value={email} onChange={(event) => setEmail(event.target.value)} required /><span className="contract-setup-card__hint">O código de confirmação será enviado para este endereço quando o responsável iniciar a assinatura.</span></div>
        </div>
        {available.length ? <div className="contract-siblings"><strong>Irmãos na mesma campanha</strong><span>Marque quem entra no mesmo link. A família assina tudo de uma vez; cada aluno continua com o seu contrato.</span>
          <label className="contract-siblings__item is-fixed"><input type="checkbox" checked disabled /><span>{enrollment.student_name}<small>{enrollment.target_grade_name}</small></span><b>{money(enrollment.amount_cents)}</b></label>
          {available.map((item) => <label className="contract-siblings__item" key={item.id}><input type="checkbox" checked={included.includes(item.id)} onChange={(event) => setIncluded((current) => event.target.checked ? [...current, item.id] : current.filter((id) => id !== item.id))} /><span>{item.student_name}<small>{item.target_grade_name}</small></span><b>{money(item.amount_cents)}</b></label>)}
          {family ? <div className="contract-siblings__total"><span>Total do contrato conjunto</span><b>{money(familyTotal)}</b></div> : null}
        </div> : null}
        <div className="contract-setup-card__action"><div><strong>Próxima etapa</strong><span>{family ? `Gerar um link de assinatura para ${included.length + 1} alunos.` : `Gerar o link individual de contrato para ${enrollment.student_name}.`}</span></div><button type="button" className="btn btn--primary" onClick={createContract} disabled={starting || Boolean(enrollment.completed_at)}>{starting ? 'Preparando…' : family ? 'Preparar link conjunto' : 'Preparar link do contrato'}</button></div>
        {contractLink ? <div className="notice contract-setup-card__notice"><span>Link individual do contrato</span><code>{contractLink}</code><button type="button" className="btn" onClick={() => navigator.clipboard?.writeText(contractLink)}>Copiar link</button></div> : null}
        {message ? <div className="notice contract-setup-card__notice"><span>{message}</span></div> : null}
      </section>
      <div className="card"><div className="card-title">Documentos da matrícula</div><div className="card-sub" style={{ marginBottom: 16 }}>Aceite e assinatura registrados para esta jornada.</div>{documents.length ? <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>{documents.map((item) => <div className="row-item" style={{ background: 'var(--surface)' }} key={item.id}><div className="who"><strong>{item.document_versions?.documents?.title || 'Documento'}</strong><span>{item.document_versions?.version || '—'} · {item.provider || 'sem provedor'}</span></div><Badge tone={statusTone(item.status)}>{item.status}</Badge></div>)}</div> : <div className="notice">Nenhum documento gerado ainda.</div>}</div>
    </div>
    <div className="stack"><div className="card"><CardHead title="Parcelas geradas" right={<span className="meta">{enrollment.payment_plan_name || 'Definidas na assinatura'}</span>} />{installments.length ? <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>{installments.map((item) => <div className="row-item" style={{ background: 'var(--surface)' }} key={item.id}><div className="who"><strong>Parcela {item.number}</strong><span>{money(item.amount_cents)} · vence em {dateTime(item.due_date)}</span></div><Badge tone={statusTone(item.status)}>{item.status}</Badge></div>)}</div> : <div className="notice">As parcelas serão definidas automaticamente quando o contrato for assinado.</div>}</div></div>
  </div>;
}

export default function AssinaturaPagamento() {
  const detail = useOutletContext();
  const navigate = useNavigate();
  const enrollments = useAsyncData(getEnrollments, []);
  const contracts = useAsyncData(getContractSessions, []);
  if (detail) return <ContractSetup key={detail.enrollment.id} enrollment={detail.enrollment} documents={detail.documents || []} installments={detail.installments || []} siblings={detail.siblings || []} />;

  const data = enrollments.data || [];
  const sessions = contracts.data || [];
  const completed = data.filter((item) => item.signed_at || item.completed_at);
  const pendingContracts = sessions.filter((item) => item.status !== 'assinada' && item.status !== 'cancelada' && item.status !== 'expirada');
  const preparing = data.filter((item) => !item.completed_at && !closedStatuses.includes(item.status) && !sessions.some((session) => session.campaign_id === item.campaign_id && session.guardian_id === item.guardian_id));
  return <DataState loading={enrollments.loading || contracts.loading} error={enrollments.error || contracts.error} empty={false}><div className="stack"><div className="card"><CardHead title="Matrículas aguardando preparo" sub="Prepare o contrato; na rematrícula, a condição segue a data da assinatura." /><div className="table"><div className="table-head cols-matric"><div>Responsável</div><div>Aluno</div><div>Campanha</div><div>Pagamento</div><div>Etapa</div><div /></div>{preparing.length ? preparing.map((item) => <div className="table-row cols-matric" key={item.id} onClick={() => navigate(`/familias/${item.id}/assinatura`)}><div className="cell-strong">{item.guardian_name}</div><div>{item.student_name}</div><div>{item.campaign_name}</div><div>Definir após assinatura</div><div><Badge tone={statusTone(item.status)}>{item.status_label}</Badge></div><div className="cell-open is-secondary">Preparar →</div></div>) : <div className="notice">Não há matrículas aguardando preparo.</div>}</div></div><div className="card"><CardHead title="Contratos em andamento" sub="Famílias que chegaram à página de contrato e ainda não concluíram" /><div className="table"><div className="table-head cols-matric"><div>Responsável</div><div>Campanha</div><div>Filhos</div><div>Etapa</div><div>Visitas</div><div>Última atividade</div></div>{pendingContracts.length ? pendingContracts.map((item) => <div className="table-row cols-matric" key={item.id}><div className="cell-strong">{item.guardian_name}</div><div>{item.campaign_name}</div><div>{item.students_count}</div><div><Badge tone={statusTone(item.status)}>{item.status}</Badge></div><div>{item.open_count || 0}</div><div>{dateTime(item.last_opened_at || item.created_at)}</div></div>) : <div className="notice">Nenhuma assinatura pendente de contrato.</div>}</div></div><div className="card"><CardHead title="Assinaturas e pagamentos" sub="Jornadas com contrato assinado ou matrícula concluída" /><div className="table"><div className="table-head cols-matric"><div>Responsável</div><div>Aluno</div><div>Turma</div><div>Status</div><div>Parcelamento</div><div>Atualizada em</div></div>{completed.length ? completed.map((item) => <div className="table-row cols-matric" key={item.id} onClick={() => navigate(`/familias/${item.id}/assinatura`)}><div className="cell-strong">{item.guardian_name}</div><div>{item.student_name}</div><div>{item.target_grade_name}</div><div><Badge tone={statusTone(item.status)}>{item.status_label}</Badge></div><div>{item.payment_plan_name || '—'}</div><div>{dateTime(item.updated_at)}</div></div>) : <div className="notice">Nenhum contrato assinado ou pagamento registrado.</div>}</div></div></div></DataState>;
}
