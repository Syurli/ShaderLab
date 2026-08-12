import { useMemo } from 'react';
import { localize, t } from '../app/i18n';
import { useAppStore } from '../app/store';
import type {
  ParameterValues,
  ShaderLabMetadata,
  ShaderParameterMetadata,
} from '../core/types';

interface ParameterPanelProps {
  metadata: ShaderLabMetadata;
  values: ParameterValues;
  onChange: (name: string, value: number | boolean | string) => void;
  onReset: () => void;
}

function groupParameters(metadata: ShaderLabMetadata) {
  const groups = new Map<string, [string, ShaderParameterMetadata][]>();
  Object.entries(metadata.parameters).forEach(([name, config]) => {
    const key = JSON.stringify(config.group ?? { zh: '常规', en: 'General' });
    const list = groups.get(key) ?? [];
    list.push([name, config]);
    groups.set(key, list);
  });
  return [...groups.entries()].map(([key, parameters]) => ({
    group: JSON.parse(key) as { zh: string; en: string },
    parameters,
  }));
}

export function ParameterPanel({
  metadata,
  values,
  onChange,
  onReset,
}: ParameterPanelProps) {
  const locale = useAppStore((state) => state.locale);
  const groups = useMemo(() => groupParameters(metadata), [metadata]);

  return (
    <aside className="parameter-panel">
      <div className="panel-header">
        <div>
          <span className="panel-kicker">SHADERLAB META</span>
          <h2>{t(locale, 'parameters')}</h2>
        </div>
        <button className="ghost-button" onClick={onReset}>
          {t(locale, 'reset')}
        </button>
      </div>

      <p className="panel-note">{t(locale, 'metadataHint')}</p>

      {groups.length === 0 ? (
        <div className="empty-panel">{t(locale, 'noParameters')}</div>
      ) : (
        <div className="parameter-groups">
          {groups.map(({ group, parameters }) => (
            <section className="parameter-group" key={group.en}>
              <h3>{localize(locale, group)}</h3>
              {parameters.map(([name, config]) => (
                <ParameterControl
                  key={name}
                  name={name}
                  config={config}
                  value={values[name]}
                  locale={locale}
                  onChange={onChange}
                />
              ))}
            </section>
          ))}
        </div>
      )}
    </aside>
  );
}

interface ParameterControlProps {
  name: string;
  config: ShaderParameterMetadata;
  value: number | boolean | string;
  locale: 'zh' | 'en';
  onChange: (name: string, value: number | boolean | string) => void;
}

function ParameterControl({
  name,
  config,
  value,
  locale,
  onChange,
}: ParameterControlProps) {
  const label = localize(locale, config.label);
  const description = config.description ? localize(locale, config.description) : '';

  return (
    <div className="parameter-control">
      <div className="parameter-label-row">
        <label htmlFor={`param-${name}`}>{label}</label>
        <code>{name}</code>
      </div>
      {description && <p>{description}</p>}

      {(config.type === 'float' || config.type === 'int') && (
        <div className="range-control">
          <input
            id={`param-${name}`}
            type="range"
            min={config.min}
            max={config.max}
            step={config.step ?? (config.type === 'int' ? 1 : 0.01)}
            value={Number(value)}
            onChange={(event) =>
              onChange(
                name,
                config.type === 'int'
                  ? Number.parseInt(event.target.value, 10)
                  : Number.parseFloat(event.target.value),
              )
            }
          />
          <input
            className="number-input"
            type="number"
            min={config.min}
            max={config.max}
            step={config.step ?? (config.type === 'int' ? 1 : 0.01)}
            value={Number(value)}
            onChange={(event) =>
              onChange(
                name,
                config.type === 'int'
                  ? Number.parseInt(event.target.value, 10)
                  : Number.parseFloat(event.target.value),
              )
            }
          />
        </div>
      )}

      {config.type === 'boolean' && (
        <label className="toggle-control" htmlFor={`param-${name}`}>
          <input
            id={`param-${name}`}
            type="checkbox"
            checked={Boolean(value)}
            onChange={(event) => onChange(name, event.target.checked)}
          />
          <span />
          <strong>{Boolean(value) ? 'ON' : 'OFF'}</strong>
        </label>
      )}

      {config.type === 'color' && (
        <div className="color-control">
          <input
            id={`param-${name}`}
            type="color"
            value={String(value)}
            onChange={(event) => onChange(name, event.target.value)}
          />
          <code>{String(value)}</code>
        </div>
      )}

      {config.type === 'enum' && config.options && (
        <select
          id={`param-${name}`}
          value={String(value)}
          onChange={(event) => onChange(name, event.target.value)}
        >
          {config.options.map((option) => (
            <option value={String(option.value)} key={String(option.value)}>
              {localize(locale, option.label)}
            </option>
          ))}
        </select>
      )}
    </div>
  );
}
