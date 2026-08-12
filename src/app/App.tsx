import { useEffect } from 'react';
import { getExperiment } from '../core/experimentRegistry';
import { Gallery } from '../ui/Gallery';
import { Header } from '../ui/Header';
import { ExperimentWorkspace } from '../ui/ExperimentWorkspace';
import { useAppStore } from './store';
import { useHashRoute } from './useHashRoute';

export function App() {
  const route = useHashRoute();
  const locale = useAppStore((state) => state.locale);

  useEffect(() => {
    document.documentElement.lang = locale === 'zh' ? 'zh-CN' : 'en';
  }, [locale]);

  const experiment = route.type === 'experiment' ? getExperiment(route.id) : undefined;

  return (
    <div className="app-shell">
      <Header />
      {experiment ? (
        <ExperimentWorkspace key={experiment.id} experiment={experiment} />
      ) : (
        <Gallery />
      )}
    </div>
  );
}
