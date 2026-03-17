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
}).catch(() => {
  // highlight.js failed to load — rendering still works without highlighting
});

const marked = new Marked({
  renderer: {
    code({ text, lang }: { text: string; lang?: string }) {
      let highlighted: string;
      if (hljs && lang) {
        try {
          highlighted = hljs.highlight(text, { language: lang, ignoreIllegals: true }).value;
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
      const langClass = lang ? ` class="language-${lang}"` : '';
      return `<pre><code${langClass}>${highlighted}</code></pre>`;
    },
  },
  gfm: true,
  breaks: true,
});

export function renderMarkdown(content: string): string {
  const raw = marked.parse(content) as string;
  return DOMPurify.sanitize(raw);
}
