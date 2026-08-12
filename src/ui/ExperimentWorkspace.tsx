import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { localize, t } from '../app/i18n';
import { useAppStore } from '../app/store';
import { experiments } from '../core/experimentRegistry';
import { createDefaultParameterValues } from '../core/shaderMetadata';
import type {
  ExperimentDefinition,
  ParameterValues,
  PerfSnapshot,
} from '../core/types';
import { ParameterPanel } from './ParameterPanel';
import { ShaderCanvas } from './ShaderCanvas';

type WorkspaceTab = 'view' | 'code' | 'info' | 'perf';

const EMPTY_PERF: PerfSnapshot = {
  fps: 0,
  frameMs: 0,
  width: 0,
  height: 0,
  drawCalls: 0,
  renderer: '—',
};

export function ExperimentWorkspace({ experiment }: { experiment: ExperimentDefinition }) {
  const locale = useAppStore((state) => state.locale);
  const [tab, setTab] = useState<WorkspaceTab>('view');
  const [values, setValues] = useState<ParameterValues>(() =>
    createDefaultParameterValues(experiment.metadata),
  );
  const [perf, setPerf] = useState<PerfSnapshot>(EMPTY_PERF);
  const viewerRef = useRef<HTMLDivElement>(null);

  const defaults = useMemo(
    () => createDefaultParameterValues(experiment.metadata),
    [experiment],
  );

  useEffect(() => {
    setValues(defaults);
    setPerf(EMPTY_PERF);
    setTab('view');
  }, [defaults, experiment.id]);

  const onChange = (name: string, value: number | boolean | string) => {
    setValues((current) => ({ ...current, [name]: value }));
  };

  const reset = () => setValues(defaults);
  const onPerf = useCallback((snapshot: PerfSnapshot) => setPerf(snapshot), []);

  const requestFullscreen = () => {
    viewerRef.current?.requestFullscreen?.();
  };

  const source = experiment.wgsl ?? experiment.fragmentShader ?? '';

  return (
    <main className="workspace">
      <aside className="experiment-sidebar">
        <a className="back-link" href="#/">
          ← {t(locale, 'backToGallery')}
        </a>
        <p className="panel-kicker">{t(locale, 'experiments')}</p>
        <nav className="experiment-nav">
          {experiments.map((item) => (
            <a
              key={item.id}
              className={item.id === experiment.id ? 'active' : ''}
              href={`#/experiment/${item.id}`}
            >
              <span>{localize(locale, item.category)}</span>
              <strong>{localize(locale, item.title)}</strong>
            </a>
          ))}
        </nav>
      </aside>

      <section className="workspace-main">
        <div className="workspace-toolbar">
          <div>
            <p className="workspace-breadcrumb">
              {localize(locale, experiment.category)} / {experiment.id}
            </p>
            <h1>{localize(locale, experiment.title)}</h1>
          </div>

          <div className="workspace-toolbar-actions">
            <div className="workspace-tabs">
              {(['view', 'code', 'info', 'perf'] as WorkspaceTab[]).map((item) => (
                <button
                  className={tab === item ? 'active' : ''}
                  key={item}
                  onClick={() => setTab(item)}
                >
                  {t(locale, item)}
                </button>
              ))}
            </div>
            <button className="ghost-button" onClick={requestFullscreen}>
              {t(locale, 'fullscreen')}
            </button>
          </div>
        </div>

        <div className="viewer-shell" ref={viewerRef}>
          {tab === 'view' && (
            <ShaderCanvas
              key={experiment.id}
              experiment={experiment}
              values={values}
              onPerf={onPerf}
            />
          )}

          {tab === 'code' && (
            <div className="code-view">
              <div className="code-toolbar">
                <span>{t(locale, 'source')}</span>
                <code>{experiment.id}/{experiment.sourceFile}</code>
              </div>
              <pre>
                <code>{source}</code>
              </pre>
            </div>
          )}

          {tab === 'info' && (
            <div className="info-view">
              <p className="eyebrow">{localize(locale, experiment.category)}</p>
              <h2>{localize(locale, experiment.title)}</h2>
              <p>{localize(locale, experiment.description)}</p>
              <dl>
                <div>
                  <dt>{t(locale, 'backend')}</dt>
                  <dd>{experiment.backend}</dd>
                </div>
                <div>
                  <dt>{t(locale, 'languages')}</dt>
                  <dd>{experiment.languages.join(' · ')}</dd>
                </div>
                <div>
                  <dt>Tags</dt>
                  <dd>{experiment.tags.join(' · ')}</dd>
                </div>
              </dl>
              <div className="metadata-explainer">
                <strong>@shaderlab</strong>
                <p>{t(locale, 'metadataHint')}</p>
              </div>
            </div>
          )}

          {tab === 'perf' && (
            <div className="perf-view">
              <Metric label="FPS" value={perf.fps.toFixed(1)} />
              <Metric label={t(locale, 'frame')} value={`${perf.frameMs.toFixed(2)} ms`} />
              <Metric
                label={t(locale, 'resolution')}
                value={`${perf.width} × ${perf.height}`}
              />
              <Metric label={t(locale, 'drawCalls')} value={String(perf.drawCalls)} />
              <Metric label={t(locale, 'currentRenderer')} value={perf.renderer} />
            </div>
          )}
        </div>

        <div className="statusbar">
          <span><b>{perf.fps.toFixed(0)}</b> FPS</span>
          <span><b>{perf.frameMs.toFixed(2)}</b> ms</span>
          <span>{perf.renderer}</span>
          <span>{experiment.languages.join(' / ')}</span>
          <span>{perf.width} × {perf.height}</span>
        </div>
      </section>

      <ParameterPanel
        metadata={experiment.metadata}
        values={values}
        onChange={onChange}
        onReset={reset}
      />
    </main>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div className="metric-card">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}
