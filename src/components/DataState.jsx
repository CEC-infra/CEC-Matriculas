export default function DataState({ loading, error, empty, children }) {
  if (loading) return <div className="notice">Carregando dados reais…</div>;
  if (error) return <div className="notice"><strong>Não foi possível carregar.</strong><span>{error}</span></div>;
  if (empty) return <div className="notice">Ainda não há registros para esta tela.</div>;
  return children;
}
