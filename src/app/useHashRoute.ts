import { useEffect, useState } from 'react';

export type Route =
  | { type: 'gallery' }
  | { type: 'experiment'; id: string };

function parseHash(): Route {
  const raw = window.location.hash.replace(/^#\/?/, '');
  const parts = raw.split('/').filter(Boolean);
  if (parts[0] === 'experiment' && parts[1]) {
    return { type: 'experiment', id: decodeURIComponent(parts[1]) };
  }
  return { type: 'gallery' };
}

export function useHashRoute(): Route {
  const [route, setRoute] = useState<Route>(() => parseHash());

  useEffect(() => {
    const onHashChange = () => setRoute(parseHash());
    window.addEventListener('hashchange', onHashChange);
    return () => window.removeEventListener('hashchange', onHashChange);
  }, []);

  return route;
}
