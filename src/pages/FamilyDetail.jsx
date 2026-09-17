import { Link, NavLink, Outlet, useParams } from 'react-router-dom';
import DataState from '../components/DataState';
import { useAsyncData } from '../hooks/useAsyncData';
import { getEnrollmentDetail } from '../services/data';

export default function FamilyDetail() {
  const { id } = useParams();
  const { loading, data, error } = useAsyncData(() => getEnrollmentDetail(id), [id]);
  const tabs = [{ to: `/familias/${id}`, label: 'Detalhe da família', end: true }, { to: `/familias/${id}/atendimento`, label: 'Atendimento' }, { to: `/familias/${id}/assinatura`, label: 'Assinatura e pagamento' }];
  return <><div className="subnav"><Link className="back-link" to="/familias">← Voltar para Famílias</Link><div className="tabs">{tabs.map((item) => <NavLink key={item.to} to={item.to} end={item.end} className={({ isActive }) => `tab${isActive ? ' is-active' : ''}`}>{item.label}</NavLink>)}</div></div><DataState loading={loading} error={error} empty={!loading && !error && !data}><Outlet context={data} /></DataState></>;
}
