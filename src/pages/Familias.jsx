import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { DATA } from '../data/content';
import { Badge, Chips, toneColor } from '../components/ui';

export default function Familias() {
  const [filter, setFilter] = useState('Todas');
  const navigate = useNavigate();

  return (
    <>
      <div className="chip-row">
        <Chips items={DATA.familyFilters} active={filter} onSelect={setFilter} />
        <div className="push">
          <button type="button" className="btn">Exportar</button>
          <button type="button" className="btn btn--orange">Adicionar à fila</button>
        </div>
      </div>

      <div className="table">
        <div className="table-head cols-families">
          <div />
          <div>Responsável</div>
          <div>Aluno / turma</div>
          <div>Status da jornada</div>
          <div>Tentativas</div>
          <div>Próxima ação</div>
          <div />
        </div>

        {DATA.families.map((r) => (
          <div
            className="table-row cols-families"
            key={r.id}
            onClick={() => navigate(`/familias/${r.id}`)}
          >
            <div className="dot" style={{ width: 9, height: 9, background: toneColor(r.tone) }} />
            <div className="cell-stack">
              <strong className="cell-strong">{r.parent}</strong>
              <span>{r.phone}</span>
            </div>
            <div className="cell-stack">
              <span className="cell">{r.student}</span>
              <span>{r.klass}</span>
            </div>
            <div><Badge tone={r.tone}>{r.status}</Badge></div>
            <div className="cell is-secondary">{r.tries} {r.tries === 1 ? 'tentativa' : 'tentativas'}</div>
            <div className="cell is-secondary">{r.next}</div>
            <div className="cell-open is-secondary">Abrir →</div>
          </div>
        ))}

        <div className="table-foot">
          <span>Mostrando 8 de 412 famílias</span>
          <strong>1 / 52</strong>
        </div>
      </div>
    </>
  );
}
