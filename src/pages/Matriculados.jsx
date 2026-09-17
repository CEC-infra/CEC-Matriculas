import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Badge, Chips, KpiRow } from '../components/ui';
import DataState from '../components/DataState';
import { useAsyncData } from '../hooks/useAsyncData';
import { getEnrollments } from '../services/data';
import { dateTime, money, statusTone } from '../lib/format';

export default function Matriculados() {
  const [filter, setFilter] = useState('Todos');
  const navigate = useNavigate();
  const { loading, data, error } = useAsyncData(getEnrollments, []);
  const completed = (data || []).filter((item) => item.completed_at);
  const rows = completed.filter((item) => filter === 'Todos' || (filter === 'Rematrícula' ? item.campaign_kind === 'rematricula' : item.campaign_kind === 'matricula_nova'));
  const received = completed.reduce((sum, item) => sum + (Number(item.amount_cents || 0) * (1 - Number(item.discount_pct || 0) / 100)), 0);
  const stats = [{ label: 'Total matriculados', value: completed.length, sub: 'jornadas concluídas' }, { label: 'Receita contratada', value: money(received), sub: 'valor da matrícula' }, { label: 'Ticket médio', value: money(completed.length ? received / completed.length : 0), sub: 'por família' }, { label: 'Concluídas hoje', value: completed.filter((item) => new Date(item.completed_at).toDateString() === new Date().toDateString()).length, sub: 'assinatura e pagamento' }];
  return <DataState loading={loading} error={error} empty={!loading && !error && !completed.length}><KpiRow items={stats} cls="grid--4" valueSize={30} /><div className="chip-row"><Chips items={['Todos', 'Rematrícula', 'Matrícula nova']} active={filter} onSelect={setFilter} /></div><div className="table"><div className="table-head cols-matric"><div>Responsável</div><div>Aluno</div><div>Turma</div><div>Tipo</div><div>Condição</div><div>Concluída em</div></div>{rows.map((item) => <div className="table-row cols-matric" key={item.id} onClick={() => navigate(`/familias/${item.id}`)}><div className="cell-strong">{item.guardian_name}</div><div className="cell">{item.student_name}</div><div className="cell is-secondary">{item.target_grade_name}</div><div><Badge tone={statusTone(item.status)}>{item.campaign_kind === 'rematricula' ? 'Rematrícula' : 'Matrícula nova'}</Badge></div><div className="cell is-secondary">{item.payment_plan_name || '—'}</div><div className="cell is-secondary">{dateTime(item.completed_at)}</div></div>)}<div className="table-foot"><span>Mostrando {rows.length} de {completed.length} matrículas</span></div></div></DataState>;
}
