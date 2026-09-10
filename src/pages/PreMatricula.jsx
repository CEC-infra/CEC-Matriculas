import { DATA } from '../data/content';
import { Field, LogoBlocks } from '../components/ui';

export default function PreMatricula() {
  return (
    <div className="grid" style={{ gridTemplateColumns: '1fr 360px', gap: 28, alignItems: 'start' }}>
      <div className="public">
        <div className="public-head--navy">
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <LogoBlocks /><span className="public-kicker">Matrículas 2027</span>
          </div>
          <h2>Comece a matrícula do seu filho em dois minutos</h2>
          <p>
            Preencha os dados básicos e nossa equipe continua o atendimento pelo WhatsApp, com valores,
            turnos e vagas disponíveis.
          </p>
        </div>

        <div className="public-body" style={{ padding: '30px 32px' }}>
          <div className="grid grid--2">
            {DATA.preFields.map((f) => <Field key={f.label} {...f} />)}
          </div>
          <div className="consent">
            <i /><span>Autorizo o CEC a entrar em contato pelo WhatsApp sobre a matrícula.</span>
          </div>
          <div className="public-foot">
            <span>Sem compromisso. Você pode encerrar o contato a qualquer momento.</span>
            <button type="button" className="cta">Quero atendimento →</button>
          </div>
        </div>
      </div>

      <div className="stack" style={{ gap: 16 }}>
        <div className="card">
          <div className="card-title" style={{ marginBottom: 14 }}>O que acontece depois</div>
          <div className="bullet-list">
            {DATA.preBenefits.map((b) => (
              <div className="bullet" key={b}><i /><span>{b}</span></div>
            ))}
          </div>
        </div>

        <div className="card card--navy">
          <div className="card-title" style={{ marginBottom: 10 }}>Do outro lado do formulário</div>
          <p style={{ fontSize: 13, color: 'var(--navy-soft)', lineHeight: 1.6 }}>
            Cada envio cria uma família no painel com origem “pré-matrícula”, entra na régua de novos alunos
            e recebe a primeira mensagem da IA em minutos.
          </p>
          <div style={{ marginTop: 16, display: 'flex', flexDirection: 'column', gap: 9, fontSize: 12, color: 'var(--navy-mute)' }}>
            <span>pré-matrículas hoje · 14</span>
            <span>convertidas em matrícula · 6</span>
            <span>visitas agendadas · 5</span>
          </div>
        </div>
      </div>
    </div>
  );
}
