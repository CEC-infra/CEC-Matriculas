import { useNavigate } from 'react-router-dom';
import { DATA } from '../data/content';
import { Bar, CardHead, KpiRow, Kv } from '../components/ui';

export default function Dashboard() {
  const navigate = useNavigate();

  return (
    <>
      <KpiRow items={DATA.kpis} />

      <div className="card">
        <div className="card-title">Links da campanha</div>
        <div className="card-sub" style={{ marginBottom: 16 }}>
          É daqui que a secretaria copia o link para enviar às famílias
        </div>
        <div className="grid grid--2">
          {DATA.dashLinks.map((l) => (
            <div className="link-card" key={l.path}>
              <div className="link-card-top">
                <span className="dot" style={{ background: l.dot, width: 8, height: 8 }} />
                <strong>{l.label}</strong>
                <span className="meta">{l.n}</span>
              </div>
              <div className="link-url">{l.url}</div>
              <div className="meta" style={{ lineHeight: 1.5 }}>{l.sub}</div>
              <div className="link-actions">
                <button type="button" className="btn btn--primary">Copiar link</button>
                <button type="button" className="btn" onClick={() => navigate(l.path)}>Ver página</button>
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="grid grid--3">
        {DATA.closing.map((c) => {
          const ink = c.navy ? '#fff' : (c.ink || 'var(--navy)');
          return (
            <div className={`close-card${c.navy ? ' is-navy' : ''}`} key={c.label}>
              <div className="close-head" style={{ color: c.navy ? 'var(--navy-soft)' : 'var(--ink-mute)' }}>
                <span>{c.label}</span><span>{c.share}</span>
              </div>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginTop: 10, color: ink }}>
                <span className="close-n">{c.n}</span>
                <strong style={{ fontSize: 13.5 }}>famílias</strong>
              </div>
              <div className="close-money" style={{ color: ink }}>{c.money}</div>
              <div className={`track${c.navy ? ' is-navy' : ''}`}><Bar pct={c.share} color={c.bar} /></div>
              <div className="close-sub" style={{ color: c.navy ? 'var(--navy-mute)' : 'var(--ink-mute)' }}>{c.sub}</div>
            </div>
          );
        })}
      </div>

      <div className="grid grid--main">
        <div className="card">
          <CardHead
            title="Funil da jornada"
            sub="Campanha Rematrícula 2027 · 412 famílias elegíveis"
            right={<span className="meta">atualizado 14:32</span>}
          />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 11 }}>
            {DATA.funnel.map((f) => (
              <div className="funnel-row" key={f.label}>
                <div className="funnel-label">{f.label}</div>
                <div className="funnel-bar"><Bar pct={f.pct} color={f.color} /></div>
                <div className="funnel-num"><strong>{f.n}</strong><span className="meta">{f.pct}</span></div>
              </div>
            ))}
          </div>
        </div>

        <div className="stack">
          <div className="card">
            <div className="card-title">Alertas</div>
            <div className="card-sub" style={{ marginBottom: 16 }}>Exigem ação humana hoje</div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
              {DATA.alerts.map((a) => (
                <div className="alert" key={a.label} onClick={() => navigate(a.go)}>
                  <div className="alert-n" style={{ background: a.color }}>{a.n}</div>
                  <div className="alert-text"><strong>{a.label}</strong><span>{a.sub}</span></div>
                </div>
              ))}
            </div>
          </div>

          <div className="card card--navy">
            <div className="card-title" style={{ marginBottom: 14 }}>Motor de mensagens</div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 11 }}>
              {DATA.engine.map((e) => <Kv key={e.label} {...e} />)}
            </div>
            <p style={{ fontSize: 11.5, color: 'var(--navy-mute)', lineHeight: 1.6, marginTop: 14 }}>
              Janela de envio 08:00–19:30 · retry controlado · pausa automática se a instância cair.
            </p>
          </div>
        </div>
      </div>

      <div className="card">
        <CardHead title="Financeiro da campanha" sub="Parcelamento até janeiro · vencimentos configuráveis" />
        <div className="grid grid--4">
          {DATA.finance.map((p) => (
            <div className="tile" key={p.label}>
              <span className="stat-label">{p.label}</span>
              <span style={{ fontSize: 24, fontWeight: 800, fontFamily: 'var(--font-display)' }}>{p.value}</span>
              <div className="track" style={{ marginTop: 2, height: 5 }}><Bar pct={p.pct} color={p.color} /></div>
              <span className="meta">{p.sub}</span>
            </div>
          ))}
        </div>
      </div>
    </>
  );
}
