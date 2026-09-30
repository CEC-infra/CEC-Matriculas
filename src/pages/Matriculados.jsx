import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Badge, Chips, KpiRow } from '../components/ui';
import DataState from '../components/DataState';
import { useAsyncData } from '../hooks/useAsyncData';
import { getCampaigns, getEnrollments } from '../services/data';
import { dateTime, money, statusTone } from '../lib/format';

export default function Matriculados() {
  const [scope, setScope] = useState('Campanha atual');
  const [type, setType] = useState('Todos');
  const navigate = useNavigate();
  const source = useAsyncData(async () => {
    const [enrollments, campaigns] = await Promise.all([getEnrollments(), getCampaigns()]);
    return { enrollments, campaigns };
  }, []);
  const completed = (source.data?.enrollments || []).filter((item) => item.completed_at);
  const activeCampaigns = new Set((source.data?.campaigns || []).filter((campaign) => campaign.status === 'ativa').map((campaign) => campaign.id));
  const historicalCampaigns = new Set((source.data?.campaigns || []).filter((campaign) => campaign.academic_year === 2026).map((campaign) => campaign.id));
  const scoped = completed.filter((item) => scope === 'Campanha atual' ? activeCampaigns.has(item.campaign_id) : scope === '2026 (histórico)' ? historicalCampaigns.has(item.campaign_id) : true);
  const rows = scoped.filter((item) => type === 'Todos' || (type === 'Rematrícula' ? item.campaign_kind === 'rematricula' : item.campaign_kind === 'matricula_nova'));
  const received = scoped.reduce((sum, item) => sum + Number(item.amount_cents || 0), 0);
  const stats = [{ label: 'Total matriculados', value: scoped.length, sub: scope === 'Campanha atual' ? 'campanhas ativas' : scope.toLowerCase() }, { label: 'Receita contratada', value: money(received), sub: 'valor da matrícula' }, { label: 'Ticket médio', value: money(scoped.length ? received / scoped.length : 0), sub: 'por matrícula' }, { label: 'Concluídas hoje', value: scoped.filter((item) => new Date(item.completed_at).toDateString() === new Date().toDateString()).length, sub: 'assinatura e pagamento' }];
  return <DataState loading={source.loading} error={source.error} empty={false}><KpiRow items={stats} cls="grid--4" valueSize={30} /><div className="chip-row"><Chips items={['Campanha atual', '2026 (histórico)', 'Todos']} active={scope} onSelect={setScope} /></div><div className="chip-row"><Chips items={['Todos', 'Rematrícula', 'Matrícula nova']} active={type} onSelect={setType} /></div><div className="table"><div className="table-head cols-matric"><div>Responsável</div><div>Aluno</div><div>Turma</div><div>Tipo</div><div>Condição</div><div>Concluída em</div></div>{rows.length ? rows.map((item) => <div className="table-row cols-matric" key={item.id} onClick={() => navigate(`/familias/${item.id}`)}><div className="cell-strong">{item.guardian_name}</div><div className="cell">{item.student_name}</div><div className="cell is-secondary">{item.target_grade_name}</div><div><Badge tone={statusTone(item.status)}>{item.campaign_kind === 'rematricula' ? 'Rematrícula' : 'Matrícula nova'}</Badge></div><div className="cell is-secondary">{item.payment_plan_name || '—'}</div><div className="cell is-secondary">{dateTime(item.completed_at)}</div></div>) : <div className="notice">Não há matrículas concluídas neste filtro.</div>}<div className="table-foot"><span>Mostrando {rows.length} de {scoped.length} matrículas</span></div></div></DataState>;
}
