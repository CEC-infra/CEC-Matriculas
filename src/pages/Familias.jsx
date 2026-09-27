import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Badge, Chips, toneColor } from '../components/ui';
import DataState from '../components/DataState';
import { useAsyncData } from '../hooks/useAsyncData';
import { getEnrollments } from '../services/data';
import { dateTime, statusTone } from '../lib/format';

const filters = ['Todas', 'Em fila', 'Precisa de humano', 'Concluída'];

export default function Familias() {
  const [filter, setFilter] = useState('Todas');
  const navigate = useNavigate();
  const { loading, data, error } = useAsyncData(getEnrollments, []);
  const rows = (data || []).filter((item) => filter === 'Todas' || item.status_label === filter);
  return <DataState loading={loading} error={error} empty={!loading && !error && !data?.length}>
    <div className="chip-row"><Chips items={filters} active={filter} onSelect={setFilter} /><div className="push"><span className="meta">{rows.length} famílias encontradas</span></div></div>
    <div className="table"><div className="table-head cols-families"><div /><div>Responsável</div><div>Aluno / turma</div><div>Status da jornada</div><div>Tentativas</div><div>Próxima ação</div><div /></div>{rows.map((row) => <div className="table-row cols-families" key={row.id} onClick={() => navigate(`/familias/${row.id}`)}><div className="dot" style={{ width: 9, height: 9, background: toneColor(statusTone(row.status)) }} /><div className="cell-stack"><strong className="cell-strong">{row.guardian_name}</strong><span>{row.guardian_phone}</span></div><div className="cell-stack"><span className="cell">{row.student_name}</span><span>{row.from_class_name || row.target_grade_name}</span></div><div><Badge tone={statusTone(row.status)}>{row.status_label}</Badge></div><div className="cell is-secondary">{row.attempts} de {row.max_attempts}</div><div className="cell is-secondary">{row.next_action || dateTime(row.next_action_at)}</div><div className="cell-open is-secondary">Abrir →</div></div>)}<div className="table-foot"><span>Mostrando {rows.length} de {data?.length || 0} famílias</span></div></div>
  </DataState>;
}
