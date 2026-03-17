// Markdown rendering with syntax highlighting and XSS sanitization

import { Marked } from 'marked';
import DOMPurify from 'dompurify';

// Lazy-load highlight.js only when needed
let hljs: typeof import('highlight.js').default | null = null;
const hljsReady = import('highlight.js/lib/core').then(async (mod) => {
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
});

const marked = new Marked({
  renderer: {
    code({ text, lang }: { text: string; lang?: string }) {
      let highlighted = text;
      if (hljs && lang) {
        try {
          const result = hljs.highlight(text, { language: lang, ignoreIllegals: true });
          highlighted = result.value;
        } catch {
          // Language not registered, fall back to plain
        }
      } else if (hljs) {
        try {
          const result = hljs.highlightAuto(text);
          highlighted = result.value;
        } catch {
          // Auto-detect failed, fall back to plain
        }
      }
      const langClass = lang ? ` class="language-${lang}"` : '';
      return `<pre><code${langClass}>${highlighted}</code></pre>`;
    },
  },
  gfm: true,
  breaks: true,
});

// Wait for highlight.js to load, then we're good
export async function initMarkdown(): Promise<void> {
  await hljsReady;
}

// Start loading immediately on import
initMarkdown();

export function renderMarkdown(content: string): string {
  const raw = marked.parse(content) as string;
  return DOMPurify.sanitize(raw);
}
