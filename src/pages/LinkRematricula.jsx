import { useState } from 'react';
import { DATA } from '../data/content';
import { Field, LogoBlocks } from '../components/ui';

/** Trilha de etapas da jornada do responsável. */
function Steps({ done }) {
  return (
    <div className="steps">
      {DATA.steps.map((label, i) => (
        <div className={`step${i <= done ? ' is-done' : ''}`} key={label}>
          <i /><span>{label}</span>
        </div>
      ))}
    </div>
  );
}

export default function LinkRematricula() {
  const [plan, setPlan] = useState(1);

  return (
    <div className="grid" style={{ gridTemplateColumns: '1fr 400px', gap: 34, alignItems: 'start' }}>
      <div className="public">
        <div className="public-head public-head--orange">
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <LogoBlocks /><strong>Rematrícula 2027</strong>
          </div>
          <span>/rematricula/8fa21c</span>
        </div>

        <Steps done={0} />

        <div className="public-body">
          <div>
            <h2>Confirme os dados de Lucas</h2>
            <p style={{ marginTop: 6 }}>
              Já preenchemos tudo o que temos no sistema. Ajuste o que estiver diferente e siga para o contrato.
            </p>
          </div>

          <div className="grid grid--2">
            {DATA.linkFields.map((f) => <Field key={f.label} {...f} />)}
          </div>

          <div style={{ border: '1px solid var(--line)', borderRadius: 'var(--r-lg)', padding: '18px 20px', display: 'flex', flexDirection: 'column', gap: 14 }}>
            <strong style={{ fontSize: 14 }}>Condição de pagamento</strong>
            {DATA.plans.map((p, i) => (
              <div className={`plan${plan === i ? ' is-active' : ''}`} key={p.label} onClick={() => setPlan(i)}>
                <div className="plan-left">
                  <div className="plan-radio" />
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                    <strong>{p.label}</strong><span>{p.sub}</span>
                  </div>
                </div>
                <span className="plan-price">{p.price}</span>
              </div>
            ))}
          </div>

          <div className="public-foot">
            <span>Ao continuar você aceita os termos do contrato e assina eletronicamente com validade jurídica.</span>
            <button type="button" className="cta">Ir para assinatura →</button>
          </div>
        </div>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div className="stat-label">Mesma página no celular</div>
        <div className="phone">
          <div className="phone-head">
            <LogoBlocks /><strong style={{ fontSize: 12.5 }}>Rematrícula 2027</strong>
          </div>
          <div className="phone-body">
            <div className="phone-steps">
              {DATA.steps.map((s, i) => <i className={i === 0 ? 'is-done' : ''} key={s} />)}
            </div>
            <strong style={{ fontSize: 18, fontFamily: 'var(--font-display)' }}>Confirme os dados de Lucas</strong>
            {DATA.mobileFields.map((f) => <Field key={f.label} {...f} />)}
            <div className="plan is-active">
              <div style={{ display: 'flex', flexDirection: 'column' }}>
                <strong style={{ fontSize: 13 }}>3x sem juros</strong>
                <span className="meta">nov · dez · jan</span>
              </div>
              <strong style={{ fontSize: 14 }}>R$ 486</strong>
            </div>
            <button type="button" className="cta btn--block">Ir para assinatura</button>
          </div>
        </div>
      </div>
    </div>
  );
}
