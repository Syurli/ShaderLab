import { useMemo, useState } from 'react';
import { useAppStore } from '../app/store';
import { localize, t } from '../app/i18n';
import { experiments } from '../core/experimentRegistry';

export function Gallery() {
  const locale = useAppStore((state) => state.locale);
  const [query, setQuery] = useState('');

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return experiments;

    return experiments.filter((experiment) => {
      const haystack = [
        localize(locale, experiment.title),
        localize(locale, experiment.description),
        localize(locale, experiment.category),
        ...experiment.tags,
      ]
        .join(' ')
        .toLowerCase();
      return haystack.includes(needle);
    });
  }, [locale, query]);

  return (
    <main className="gallery-page">
      <section className="hero">
        <div>
          <p className="eyebrow">WEBGL · WEBGPU · WGSL · GLSL</p>
          <h1>{t(locale, 'introTitle')}</h1>
          <p className="hero-copy">{t(locale, 'introBody')}</p>
        </div>
        <div className="hero-rule-card">
          <span className="rule-index">01</span>
          <strong>{t(locale, 'parameterRule')}</strong>
          <p>{t(locale, 'metadataHint')}</p>
          <code>/* @shaderlab {'{ ... }'} @endshaderlab */</code>
        </div>
      </section>

      <section className="gallery-toolbar">
        <div>
          <p className="section-kicker">{t(locale, 'gallery')}</p>
          <h2>{experiments.length.toString().padStart(2, '0')} Experiments</h2>
        </div>
        <label className="search-field">
          <span>⌕</span>
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder={t(locale, 'search')}
          />
        </label>
      </section>

      {filtered.length > 0 ? (
        <section className="experiment-grid">
          {filtered.map((experiment, index) => (
            <a
              className="experiment-card"
              href={`#/experiment/${experiment.id}`}
              key={experiment.id}
            >
              <div className={`card-preview preview-${experiment.id}`}>
                <div className="preview-grid" />
                <span className="preview-index">{String(index + 1).padStart(2, '0')}</span>
                <span className="preview-backend">{experiment.backend.toUpperCase()}</span>
              </div>
              <div className="card-body">
                <div className="card-heading">
                  <div>
                    <p>{localize(locale, experiment.category)}</p>
                    <h3>{localize(locale, experiment.title)}</h3>
                  </div>
                  <span className="card-arrow">↗</span>
                </div>
                <p className="card-description">{localize(locale, experiment.description)}</p>
                <div className="tag-row">
                  {experiment.tags.map((tag) => (
                    <span key={tag}>{tag}</span>
                  ))}
                </div>
              </div>
            </a>
          ))}
        </section>
      ) : (
        <div className="empty-state">{t(locale, 'noResults')}</div>
      )}
    </main>
  );
}
