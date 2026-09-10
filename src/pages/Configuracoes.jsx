import { DATA } from '../data/content';
import { Badge, Tile } from '../components/ui';

export default function Configuracoes() {
  return (
    <>
      <div className="notice">
        <Badge tone="warn">Somente leitura</Badge>
        <span>
          Os cadastros vêm da base da secretaria e das regras da campanha. Para alterar valores, séries ou
          condições, fale com a coordenação — nada é editável por aqui.
        </span>
      </div>

      <div className="table">
        <div className="table-title">
          <div className="card-title">Séries e valores 2027</div>
          <div className="card-sub">Regra de transição de turma e mensalidade aplicável a cada família</div>
        </div>
        <div className="table-head cols-series">
          <div>Turma atual</div>
          <div>Próxima turma</div>
          <div>Turno</div>
          <div>Mensalidade</div>
          <div>À vista (−8%)</div>
          <div>Vagas</div>
        </div>
        {DATA.series.map((s) => (
          <div className="table-row cols-series" style={{ cursor: 'default' }} key={s.from}>
            <div className="cell-strong">{s.from}</div>
            <div className="cell-strong" style={{ color: 'var(--navy)' }}>→ {s.to}</div>
            <div className="cell is-secondary">{s.turno}</div>
            <div className="cell-strong">{s.mensal}</div>
            <div className="cell is-secondary">{s.avista}</div>
            <div className="cell is-secondary">{s.vagas}</div>
          </div>
        ))}
      </div>

      <div className="card">
        <div className="card-title">Condições de pagamento</div>
        <div className="card-sub" style={{ marginBottom: 16 }}>
          Definidas pela escola e aplicadas automaticamente na página do responsável
        </div>
        <div className="grid grid--3">
          {DATA.conditions.map((c) => (
            <div className="tile" key={c.label}>
              <span className="stat-label">{c.label}</span>
              <span className="tile-big">{c.value}</span>
              <span className="meta" style={{ lineHeight: 1.5 }}>{c.sub}</span>
            </div>
          ))}
        </div>
      </div>

      <div className="grid grid--main">
        <div className="card">
          <div className="card-title">Parâmetros da campanha</div>
          <div className="card-sub" style={{ marginBottom: 16 }}>Configurados no início e válidos até o fim do período</div>
          <div className="grid grid--3">
            {DATA.campaignConfig.map((c) => <Tile key={c.label} {...c} />)}
          </div>
        </div>

        <div className="card">
          <div className="card-title">Documentos cadastrados</div>
          <div className="card-sub" style={{ marginBottom: 16 }}>Anexados à jornada de cada família</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {DATA.docsConfig.map((d) => (
              <div className="row-item" style={{ background: 'var(--surface)' }} key={d.label}>
                <div className="who"><strong>{d.label}</strong><span>{d.sub}</span></div>
                <strong style={{ fontSize: 12.5, color: 'var(--navy)' }}>{d.value}</strong>
              </div>
            ))}
          </div>
        </div>
      </div>
    </>
  );
}
