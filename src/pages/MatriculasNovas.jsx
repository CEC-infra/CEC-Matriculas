import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { DATA } from '../data/content';
import { Badge, Chips, Field, KpiRow } from '../components/ui';

export default function MatriculasNovas() {
  const [filter, setFilter] = useState('Todas');
  const navigate = useNavigate();

  const rows = filter === 'Todas' ? DATA.novas : DATA.novas.filter((n) => n.stage === filter);

  return (
    <>
      <KpiRow items={DATA.novasStats} cls="grid--4" valueSize={30} />

      <div className="grid grid--wide">
        <div className="stack" style={{ gap: 14 }}>
          <div className="chip-row">
            <Chips items={DATA.novasFilters} active={filter} onSelect={setFilter} />
          </div>

          <div className="table">
            <div className="table-head cols-novas">
              <div>Responsável</div>
              <div>Aluno</div>
              <div>Série pretendida</div>
              <div>Etapa</div>
              <div>Origem</div>
              <div />
            </div>
            {rows.map((n) => (
              <div className="table-row cols-novas" key={n.id} onClick={() => navigate(`/familias/${n.id}`)}>
                <div className="cell-stack"><strong className="cell-strong">{n.parent}</strong><span>{n.phone}</span></div>
                <div className="cell-stack"><span className="cell">{n.student}</span><span>{n.when}</span></div>
                <div className="cell is-secondary">{n.target}</div>
                <div><Badge tone={n.tone}>{n.stage}</Badge></div>
                <div className="cell is-secondary">{n.origin}</div>
                <div className="cell-open is-secondary">Abrir →</div>
              </div>
            ))}
          </div>
        </div>

        <div className="card">
          <div className="card-title">Cadastrar família</div>
          <div className="card-sub" style={{ marginBottom: 16 }}>
            Para quem chegou por visita, telefone ou indicação — entra direto na esteira de atendimento
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {DATA.novaForm.map((f) => <Field key={f.label} {...f} />)}
          </div>
          <button type="button" className="btn btn--primary btn--block" style={{ marginTop: 18 }}>
            Cadastrar e iniciar atendimento
          </button>
          <p className="meta" style={{ lineHeight: 1.5, marginTop: 12 }}>
            A família recebe a primeira mensagem no próximo lote da fila.
          </p>
        </div>
      </div>
    </>
  );
}
