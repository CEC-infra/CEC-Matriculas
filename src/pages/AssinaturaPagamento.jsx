import { DATA } from '../data/content';
import { Badge, CardHead } from '../components/ui';

/* Serve a /assinatura-e-pagamento e a /familias/:id/assinatura. */
export default function AssinaturaPagamento() {
  return (
    <div className="grid grid--2" style={{ gap: 18, alignItems: 'start' }}>
      <div className="card">
        <div className="card-title">Documentos da matrícula</div>
        <div className="card-sub" style={{ marginBottom: 16 }}>Aceite e assinatura digital com validade jurídica</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {DATA.signItems.map((d) => (
            <div className="row-item" style={{ background: 'var(--surface)' }} key={d.label}>
              <div className="who"><strong>{d.label}</strong><span>{d.sub}</span></div>
              <span className="badge badge--solid-ok">{d.status}</span>
            </div>
          ))}
        </div>

        <div style={{ marginTop: 18, paddingTop: 18, borderTop: '1px solid var(--line-3)' }}>
          <div className="stat-label" style={{ marginBottom: 12 }}>Evidências do aceite</div>
          <div className="grid grid--2">
            {DATA.evidence.map((e) => (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }} key={e.label}>
                <span className="stat-label">{e.label}</span>
                <strong style={{ fontSize: 13 }}>{e.value}</strong>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="stack">
        <div className="card">
          <div className="card-title" style={{ marginBottom: 16 }}>Formas de pagamento liberadas pela escola</div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {DATA.payMethods.map((m) => (
              <div className="row-item" key={m.label}>
                <div className="who"><strong>{m.label}</strong><span>{m.sub}</span></div>
                <span className={`badge ${m.solid ? 'badge--solid-ok' : 'badge--mute'}`}>{m.badge}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="card">
          <CardHead title="Parcelas geradas" right={<span className="meta">3x de R$ 486,00</span>} />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {DATA.installments.map((p) => (
              <div className="row-item" style={{ background: 'var(--surface)' }} key={p.label}>
                <div className="who"><strong>{p.label}</strong><span>{p.value}</span></div>
                <Badge tone={p.tone}>{p.status}</Badge>
              </div>
            ))}
          </div>
        </div>

        <div
          className="card card--navy"
          style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 16, flexWrap: 'wrap' }}
        >
          <div style={{ display: 'flex', flexDirection: 'column', gap: 5 }}>
            <strong style={{ fontSize: 15, fontFamily: 'var(--font-display)' }}>Rematrícula concluída</strong>
            <span style={{ fontSize: 12.5, color: 'var(--navy-soft)' }}>
              A escola e a família recebem a confirmação pelo WhatsApp.
            </span>
          </div>
          <span className="badge" style={{ background: 'var(--green-ink)', color: '#fff', borderColor: 'var(--green-ink)' }}>
            ✓ Confirmar
          </span>
        </div>
      </div>
    </div>
  );
}
