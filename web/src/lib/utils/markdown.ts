// Markdown rendering with syntax highlighting and XSS sanitization

import { Marked } from 'marked';
import DOMPurify from 'dompurify';

// HTML-escape helper for raw code when hljs isn't available
function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// Eagerly load highlight.js + common languages on import so it's ready
// by the time Claude sends code blocks (typically after a few seconds)
let hljs: typeof import('highlight.js').default | null = null;
void import('highlight.js/lib/core').then(async (mod) => {
  hljs = mod.default;
  // Register common languages for Claude Code output
  const [ts, js, json, bash, css, html, python, go, rust, swift, yaml, sql, diff] =
    await Promise.all([
      import('highlight.js/lib/languages/typescript'),
      import('highlight.js/lib/languages/javascript'),
      import('highlight.js/lib/languages/json'),
      import('highlight.js/lib/languages/bash'),
      import('highlight.js/lib/languages/css'),
      import('highlight.js/lib/languages/xml'),
      import('highlight.js/lib/languages/python'),
      import('highlight.js/lib/languages/go'),
      import('highlight.js/lib/languages/rust'),
      import('highlight.js/lib/languages/swift'),
      import('highlight.js/lib/languages/yaml'),
      import('highlight.js/lib/languages/sql'),
      import('highlight.js/lib/languages/diff'),
    ]);
  hljs.registerLanguage('typescript', ts.default);
  hljs.registerLanguage('ts', ts.default);
  hljs.registerLanguage('javascript', js.default);
  hljs.registerLanguage('js', js.default);
  hljs.registerLanguage('json', json.default);
  hljs.registerLanguage('bash', bash.default);
  hljs.registerLanguage('sh', bash.default);
  hljs.registerLanguage('shell', bash.default);
  hljs.registerLanguage('css', css.default);
  hljs.registerLanguage('html', html.default);
  hljs.registerLanguage('xml', html.default);
  hljs.registerLanguage('python', python.default);
  hljs.registerLanguage('py', python.default);
  hljs.registerLanguage('go', go.default);
  hljs.registerLanguage('rust', rust.default);
  hljs.registerLanguage('swift', swift.default);
  hljs.registerLanguage('yaml', yaml.default);
  hljs.registerLanguage('yml', yaml.default);
  hljs.registerLanguage('sql', sql.default);
  hljs.registerLanguage('diff', diff.default);
}).catch(() => {
  // highlight.js failed to load — rendering still works without highlighting
});

// Display names for common language aliases
const LANG_DISPLAY: Record<string, string> = {
  ts: 'TypeScript', typescript: 'TypeScript',
  js: 'JavaScript', javascript: 'JavaScript',
  json: 'JSON', bash: 'Bash', sh: 'Bash', shell: 'Shell',
  css: 'CSS', html: 'HTML', xml: 'XML',
  python: 'Python', py: 'Python',
  go: 'Go', rust: 'Rust', swift: 'Swift',
  yaml: 'YAML', yml: 'YAML', sql: 'SQL', diff: 'Diff',
};

const marked = new Marked({
  renderer: {
    code({ text, lang }: { text: string; lang?: string }) {
      // Sanitize lang to prevent attribute injection
      const safeLang = lang && /^[a-zA-Z0-9_+-]+$/.test(lang) ? lang : undefined;
      let highlighted: string;
      if (hljs && safeLang) {
        try {
          highlighted = hljs.highlight(text, { language: safeLang, ignoreIllegals: true }).value;
        } catch {
          highlighted = escapeHtml(text);
        }
      } else if (hljs) {
        try {
          highlighted = hljs.highlightAuto(text).value;
        } catch {
          highlighted = escapeHtml(text);
        }
      } else {
        highlighted = escapeHtml(text);
      }
      const langClass = safeLang ? ` class="language-${safeLang}"` : '';
      const langLabel = safeLang ? LANG_DISPLAY[safeLang] ?? safeLang : '';
      // Encode raw text as base64 for the copy button (avoids escaping issues)
      const bytes = new TextEncoder().encode(text);
      const encoded = btoa(String.fromCharCode(...bytes));
      const header = `<div class="code-header"><span class="code-lang">${escapeHtml(langLabel)}</span><button class="code-copy-btn" data-code="${encoded}" type="button">Copy</button></div>`;
      return `<div class="code-block-wrap">${header}<pre><code${langClass}>${highlighted}</code></pre></div>`;
    },
  },
  gfm: true,
  breaks: true,
});

export function renderMarkdown(content: string): string {
  const raw = marked.parse(content) as string;
  return DOMPurify.sanitize(raw, {
    ADD_ATTR: ['data-code'],
  });
}

/** Attach click handlers to all code copy buttons inside a container element.
 *  Call after mounting/updating {@html rendered} content. */
export function attachCopyHandlers(container: HTMLElement) {
  for (const btn of container.querySelectorAll<HTMLButtonElement>('.code-copy-btn')) {
    if (btn.dataset.bound) continue;
    btn.dataset.bound = '1';
    btn.addEventListener('click', () => {
      try {
        const encoded = btn.dataset.code;
        if (!encoded) return;
        const bytes = Uint8Array.from(atob(encoded), (c) => c.charCodeAt(0));
        const text = new TextDecoder().decode(bytes);
        navigator.clipboard.writeText(text).then(() => {
          btn.textContent = 'Copied!';
          setTimeout(() => { btn.textContent = 'Copy'; }, 1500);
        });
      } catch {
        // Decoding or clipboard failed — silently ignore
      }
    });
  }
}
