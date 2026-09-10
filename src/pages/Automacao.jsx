import { DATA } from '../data/content';
import { Badge, CardHead, KpiRow, Kv } from '../components/ui';

export default function Automacao() {
  const max = DATA.throughputMax;

  return (
    <>
      <KpiRow items={DATA.campaignStats} cls="grid--4" valueSize={30} />

      <div className="grid grid--split">
        <div className="card">
          <CardHead
            title="Próximos a receber mensagem"
            sub="Fila do lote das 15:00 · intervalo de 40 a 90 segundos entre envios"
            right={<button type="button" className="btn">Pausar fila</button>}
          />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
            {DATA.queue.map((q) => (
              <div className="row-item" key={q.time}>
                <span className="row-time">{q.time}</span>
                <div className="who"><strong>{q.parent}</strong><span>{q.student}</span></div>
                <span className="cell">{q.kind}</span>
                <Badge tone="info">{q.attempt}</Badge>
              </div>
            ))}
          </div>
        </div>

        <div className="stack">
          <div className="card">
            <div className="card-title">Mensagens por hora</div>
            <div className="card-sub" style={{ marginBottom: 18 }}>Hoje · teto de 25 por hora</div>
            <div className="bars">
              {DATA.throughput.map((t, i) => (
                <div className={`bar-col${i === DATA.throughput.length - 1 ? ' is-current' : ''}`} key={t.h}>
                  <strong>{t.n}</strong>
                  <div className="bar-plot"><i style={{ height: `${Math.round((t.n / max) * 100)}%` }} /></div>
                  <small>{t.h}</small>
                </div>
              ))}
            </div>
          </div>

          <div className="card card--navy">
            <div className="card-title" style={{ marginBottom: 14 }}>Limites e proteção do número</div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 11 }}>
              {DATA.guards.map((g) => <Kv key={g.label} {...g} />)}
            </div>
          </div>
        </div>
      </div>

      <div className="card">
        <CardHead
          title="Já atendidas"
          sub="Famílias que a automação já contatou e receberam resposta"
          right={<button type="button" className="btn">Ver todas · 318</button>}
        />
        <div style={{ display: 'flex', flexDirection: 'column', gap: 9 }}>
          {DATA.attended.map((a) => (
            <div className="row-item" key={a.parent}>
              <span className="row-time row-time--plain">{a.time}</span>
              <div className="who"><strong>{a.parent}</strong><span>{a.student}</span></div>
              <span className="cell" style={{ minWidth: 110 }}>Atendida pela {a.by}</span>
              <Badge tone={a.tone}>{a.outcome}</Badge>
            </div>
          ))}
        </div>
      </div>
    </>
  );
}
