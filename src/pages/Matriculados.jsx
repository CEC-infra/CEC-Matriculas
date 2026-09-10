import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { DATA } from '../data/content';
import { Badge, Chips, KpiRow } from '../components/ui';

export default function Matriculados() {
  const [filter, setFilter] = useState('Todos');
  const navigate = useNavigate();

  const rows = filter === 'Todos' ? DATA.matriculados : DATA.matriculados.filter((m) => m.type === filter);

  return (
    <>
      <KpiRow items={DATA.matriculadosStats} cls="grid--4" valueSize={30} />

      <div className="chip-row">
        <Chips items={DATA.matriculadosFilters} active={filter} onSelect={setFilter} />
        <div className="push"><button type="button" className="btn">Exportar lista</button></div>
      </div>

      <div className="table">
        <div className="table-head cols-matric">
          <div>Responsável</div>
          <div>Aluno</div>
          <div>Turma 2027</div>
          <div>Tipo</div>
          <div>Condição</div>
          <div>Concluída em</div>
        </div>
        {rows.map((m) => (
          <div className="table-row cols-matric" key={m.id} onClick={() => navigate(`/familias/${m.id}`)}>
            <div className="cell-strong">{m.parent}</div>
            <div className="cell">{m.student}</div>
            <div className="cell is-secondary">{m.klass}</div>
            <div><Badge tone={m.tone}>{m.type}</Badge></div>
            <div className="cell is-secondary">{m.plan}</div>
            <div className="cell is-secondary">{m.when}</div>
          </div>
        ))}
        <div className="table-foot">
          <span>Mostrando {rows.length} de 91 matriculados</span>
          <strong>1 / 13</strong>
        </div>
      </div>
    </>
  );
}
