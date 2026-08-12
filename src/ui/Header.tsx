import { useAppStore } from '../app/store';
import { t } from '../app/i18n';

export function Header() {
  const locale = useAppStore((state) => state.locale);
  const setLocale = useAppStore((state) => state.setLocale);
  const webgpuSupported = typeof navigator !== 'undefined' && 'gpu' in navigator;

  return (
    <header className="topbar">
      <a className="brand" href="#/" aria-label="ShaderLab home">
        <span className="brand-mark" />
        <span>ShaderLab</span>
        <span className="version-chip">v0.1</span>
      </a>

      <div className="topbar-actions">
        <span className={`capability-chip ${webgpuSupported ? 'ready' : ''}`}>
          <span className="capability-dot" />
          {webgpuSupported ? t(locale, 'webgpuReady') : t(locale, 'webgpuUnavailable')}
        </span>

        <div className="language-switch" aria-label="Language">
          <button
            className={locale === 'zh' ? 'active' : ''}
            onClick={() => setLocale('zh')}
          >
            中文
          </button>
          <button
            className={locale === 'en' ? 'active' : ''}
            onClick={() => setLocale('en')}
          >
            EN
          </button>
        </div>

        <a
          className="topbar-link"
          href="https://github.com/Syurli/ShaderLab"
          target="_blank"
          rel="noreferrer"
        >
          {t(locale, 'github')}
        </a>
      </div>
    </header>
  );
}
