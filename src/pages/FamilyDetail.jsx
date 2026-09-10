import { Link, NavLink, Outlet, useParams } from 'react-router-dom';
import { findFamily } from '../data/content';

/** Casca do detalhe: volta para a lista, subabas e a aba ativa via <Outlet>.
    Cada subaba tem o seu próprio caminho — /familias/:id/atendimento etc. */
export default function FamilyDetail() {
  const { id } = useParams();
  const family = findFamily(id);

  const tabs = [
    { to: `/familias/${id}`,             label: 'Detalhe da família',     end: true },
    { to: `/familias/${id}/atendimento`, label: 'Atendimento' },
    { to: `/familias/${id}/assinatura`,  label: 'Assinatura e pagamento' }
  ];

  return (
    <>
      <div className="subnav">
        <Link className="back-link" to="/familias">← Voltar para Famílias</Link>
        <div className="tabs">
          {tabs.map((t) => (
            <NavLink
              key={t.to}
              to={t.to}
              end={t.end}
              className={({ isActive }) => `tab${isActive ? ' is-active' : ''}`}
            >
              {t.label}
            </NavLink>
          ))}
        </div>
      </div>

      <Outlet context={family} />
    </>
  );
}
