import { useCallback, useEffect, useState } from 'react';

export function useAsyncData(load, deps = []) {
  const [state, setState] = useState({ loading: true, data: null, error: null });
  const refresh = useCallback(async () => {
    setState((current) => ({ ...current, loading: true, error: null }));
    try {
      const data = await load();
      setState({ loading: false, data, error: null });
    } catch (error) {
      setState({ loading: false, data: null, error: error.message || 'Não foi possível carregar os dados.' });
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  useEffect(() => { refresh(); }, [refresh]);
  return { ...state, refresh };
}
