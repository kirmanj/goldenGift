"""Build the public legal pages from their Markdown sources.

    docs/legal/privacy_policy.md   → mobile/web/privacy.html  (served at /privacy)
    docs/legal/terms_of_service.md → mobile/web/terms.html    (served at /terms)

Flutter copies mobile/web/* into build/web, and firebase.json rewrites /privacy
and /terms on the goldengift-iq Hosting site to these files (docs/RELEASE.md).

Run from the repo root after editing a source (Python 3.9+, stdlib only):
    python3 docs/tools/build_legal_pages.py          # write the pages
    python3 docs/tools/build_legal_pages.py --check  # exit 1 if a page is stale

Source format: everything before the first `<!-- lang:xx -->` marker is notes
for the owner and is not published. Each language block (en, ar, ckb) holds:
`## ` page title, `### ` section headings, `> ` callout (the draft banner),
paragraphs, `- ` bullets (two-space indent = nested), a paragraph that is all
**bold** (the first one = "last updated", later ones = sub-headings), and
inline **bold**, `code` and [links](url).

The page is static: no external scripts, fonts or styles. One language shows
at a time (CSS :target on empty anchors at the top of the page, picked by the
language pills or #en / #ar / #ckb in the URL; a tiny inline script picks Arabic
or Kurdish from ?lang= or the browser language). Section links such as
/privacy#en-s7 (account deletion) open the right language at that heading.
Browsers without :has() show all three languages one after another.
"""
import argparse
import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

PAGES = [
    {
        'source': ROOT / 'docs/legal/privacy_policy.md',
        'target': ROOT / 'mobile/web/privacy.html',
        'title': 'Privacy Policy',
        'description': 'How Golden Gift collects, uses and protects your personal data.',
    },
    {
        'source': ROOT / 'docs/legal/terms_of_service.md',
        'target': ROOT / 'mobile/web/terms.html',
        'title': 'Terms of Service',
        'description': 'The terms for using Golden Gift and ordering personalized gifts.',
    },
]

LANGS = [
    # code, label in its own language, direction
    ('en', 'English', 'ltr'),
    ('ar', 'العربية', 'rtl'),
    ('ckb', 'کوردی', 'rtl'),
]

LANG_MARKER = re.compile(r'^<!--\s*lang:([a-z]+)\s*-->\s*$')
WHOLE_BOLD = re.compile(r'^\*\*(.+)\*\*$')
SECTION_NUMBER = re.compile(r'^(\d+)\.')


def inline(text: str) -> str:
    out = html.escape(text, quote=False)
    out = re.sub(r'`([^`]+)`', r'<code>\1</code>', out)
    out = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', out)

    def link(m: 're.Match[str]') -> str:
        href = html.escape(html.unescape(m.group(2)), quote=True)
        return f'<a href="{href}">{m.group(1)}</a>'

    return re.sub(r'\[([^\]]+)\]\(([^)\s]+)\)', link, out)


def split_languages(markdown: str) -> dict:
    blocks: dict = {}
    current = None
    for line in markdown.splitlines():
        marker = LANG_MARKER.match(line.strip())
        if marker:
            current = marker.group(1)
            blocks[current] = []
        elif current is not None:
            blocks[current].append(line)
    return blocks


def render_block(lang: str, lines: list) -> str:
    """One language block → the inner HTML of its <section>."""
    out = []
    paragraph: list = []
    list_items: list = []  # [(level, text)]
    seen_section = False
    seen_updated = False

    def flush_paragraph():
        nonlocal seen_updated
        if not paragraph:
            return
        text = ' '.join(s.strip() for s in paragraph)
        paragraph.clear()
        whole = WHOLE_BOLD.match(text)
        if whole and '**' not in whole.group(1):
            if not seen_section and not seen_updated:
                seen_updated = True
                out.append(f'<p class="updated">{inline(whole.group(1))}</p>')
            else:
                out.append(f'<h3>{inline(whole.group(1))}</h3>')
        else:
            out.append(f'<p>{inline(text)}</p>')

    def flush_list():
        if not list_items:
            return
        parts = ['<ul>']
        level = 0
        for i, (item_level, text) in enumerate(list_items):
            if item_level > level:
                parts.append('<ul>')
            elif item_level < level:
                parts.append('</li></ul></li>')
            elif i > 0:
                parts.append('</li>')
            parts.append(f'<li>{inline(text)}')
            level = item_level
        parts.append('</li>' + ('</ul></li>' if level else '') + '</ul>')
        list_items.clear()
        out.append(''.join(parts))

    callout: list = []

    def flush_callout():
        if callout:
            out.append(f'<aside class="draft" role="note"><p>{inline(" ".join(callout))}</p></aside>')
            callout.clear()

    for raw in lines + ['']:
        line = raw.rstrip()
        stripped = line.strip()
        bullet = re.match(r'^( *)- (.*)$', line)
        if not stripped:
            flush_paragraph()
            flush_list()
            flush_callout()
        elif stripped.startswith('> '):
            flush_paragraph()
            flush_list()
            callout.append(stripped[2:])
        elif line.startswith('## '):
            flush_paragraph()
            flush_list()
            out.append(f'<h1>{inline(line[3:].strip())}</h1>')
        elif line.startswith('### '):
            flush_paragraph()
            flush_list()
            seen_section = True
            heading = line[4:].strip()
            number = SECTION_NUMBER.match(heading)
            anchor = f' id="{lang}-s{number.group(1)}"' if number else ''
            out.append(f'<h2{anchor}>{inline(heading)}</h2>')
        elif bullet:
            flush_paragraph()
            level = 1 if len(bullet.group(1)) >= 2 else 0
            list_items.append((level, bullet.group(2)))
        elif list_items and line.startswith('  '):
            level, text = list_items[-1]
            list_items[-1] = (level, f'{text} {stripped}')
        else:
            flush_list()
            paragraph.append(stripped)
    return '\n'.join(out)


CSS = """
:root {
  color-scheme: light dark;
  --bg: #FAFAF7; --card: #FFFFFF; --text: #1E1E2A; --muted: #6B6F80; --line: #E6E3D8;
  --gold: #C9A227; --gold-text: #8A6A0F; --gold-soft: #FBF4DC; --on-gold: #1F1A08;
  --warn: #E08A1E; --warn-soft: #FFF4E5;
  --header: linear-gradient(135deg, #9C7A14 0%, #E3C04A 55%, #C9A227 100%);
  --latin: "Nunito", system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  --arabic: "Vazirmatn", "Noto Sans Arabic", "Segoe UI", Tahoma, "Geeza Pro", sans-serif;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0E0E0F; --card: #1A1A1C; --text: #F4F1E8; --muted: #B0ADA3; --line: #343438;
    --gold: #E3C04A; --gold-text: #E3C04A; --gold-soft: #2E2710; --warn-soft: #3A2A10;
  }
}
* { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; scroll-padding-top: 80px; }
body { position: relative; }
body { margin: 0; background: var(--bg); color: var(--text); font: 16px/1.65 var(--latin); overflow-wrap: break-word; }
a { color: var(--gold-text); text-underline-offset: 2px; }
a:focus-visible { outline: 2px solid var(--gold); outline-offset: 2px; border-radius: 4px; }
.top { background: var(--header); color: var(--on-gold); }
.top .inner { max-width: 820px; margin: 0 auto; padding: 18px 16px; display: flex; align-items: center; gap: 10px; }
.brand { color: var(--on-gold); font-weight: 800; font-size: 20px; letter-spacing: .2px; text-decoration: none; display: inline-flex; align-items: center; gap: 10px; }
.brand svg { width: 28px; height: 28px; flex: none; }
.langs { position: sticky; top: 0; z-index: 2; background: var(--bg); border-bottom: 1px solid var(--line); }
.langs .inner { max-width: 820px; margin: 0 auto; padding: 10px 16px; display: flex; gap: 8px; flex-wrap: wrap; }
.langs a { display: inline-block; min-height: 44px; padding: 10px 18px; border-radius: 999px; border: 1px solid var(--line);
  background: var(--card); color: var(--text); text-decoration: none; font-weight: 700; line-height: 22px; }
.langs a[lang="ar"], .langs a[lang="ckb"] { font-family: var(--arabic); }
main { max-width: 820px; margin: 0 auto; padding: 20px 16px 8px; }
.doc { background: var(--card); border: 1px solid var(--line); border-radius: 18px; padding: 24px 20px; margin: 0 0 20px; }
.doc[dir="rtl"] { font-family: var(--arabic); line-height: 1.85; }
h1 { font-size: 28px; line-height: 1.25; margin: 0 0 14px; }
h2 { font-size: 19px; line-height: 1.35; margin: 30px 0 10px; padding-inline-start: 12px; border-inline-start: 4px solid var(--gold); }
h3 { font-size: 16px; margin: 20px 0 6px; color: var(--gold-text); }
p { margin: 0 0 12px; }
ul { margin: 0 0 12px; padding-inline-start: 22px; }
li { margin: 4px 0; }
li::marker { color: var(--gold); }
code { font-size: .92em; background: var(--gold-soft); padding: 1px 5px; border-radius: 6px; }
.updated { color: var(--muted); font-weight: 700; }
.draft { background: var(--warn-soft); border: 1px solid var(--warn); border-radius: 14px; padding: 12px 14px; margin: 0 0 16px; }
.draft p { margin: 0; }
footer { max-width: 820px; margin: 0 auto; padding: 8px 16px 40px; color: var(--muted); font-size: 14px; text-align: center; }
footer a { color: var(--gold-text); }
@media (min-width: 640px) { .doc { padding: 32px 36px; } h1 { font-size: 32px; } }
.lang-anchor { position: absolute; top: 0; }
@supports selector(:has(*)) {
  .doc { display: none; }
  body:has(#en:target) .doc[lang="en"], body:has(#ar:target) .doc[lang="ar"],
  body:has(#ckb:target) .doc[lang="ckb"], .doc:has(:target), body:not(:has(:target)) .doc[lang="en"] {
    display: block;
  }
  body:has(#en:target) .langs a[href="#en"], body:has(.doc[lang="en"] :target) .langs a[href="#en"],
  body:not(:has(:target)) .langs a[href="#en"],
  body:has(#ar:target) .langs a[href="#ar"], body:has(.doc[lang="ar"] :target) .langs a[href="#ar"],
  body:has(#ckb:target) .langs a[href="#ckb"], body:has(.doc[lang="ckb"] :target) .langs a[href="#ckb"] {
    background: var(--gold); border-color: var(--gold); color: var(--on-gold);
  }
}
@media print {
  .langs, .top { display: none; }
  .doc { display: block !important; border: 0; padding: 0; break-before: page; }
  body { background: #fff; color: #000; }
}
"""

# Picks Arabic / Kurdish from ?lang= or the browser language when the URL has no #section.
SCRIPT = """
(function () {
  if (location.hash.length > 1) return;
  var m = /[?&]lang=([A-Za-z-]+)/.exec(location.search);
  var pref = (m ? m[1] : ((navigator.languages && navigator.languages[0]) || navigator.language || 'en')).toLowerCase();
  var pick = pref.indexOf('ar') === 0 ? 'ar' : (pref.indexOf('ckb') === 0 || pref.indexOf('ku') === 0) ? 'ckb' : '';
  if (pick) location.replace('#' + pick);
})();
"""

GIFT_ICON = (
    '<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" '
    'stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="8" width="18" height="4" rx="1"/>'
    '<path d="M5 12v8h14v-8M12 8v12M12 8c-1.5-3-5-3.5-5-1.2C7 8 9.5 8 12 8zm0 0c1.5-3 5-3.5 5-1.2C17 8 14.5 8 12 8z"/></svg>'
)


def build_page(page: dict) -> str:
    source = page['source']
    blocks = split_languages(source.read_text(encoding='utf-8'))
    missing = [code for code, _, _ in LANGS if code not in blocks]
    if missing:
        sys.exit(f'{source.relative_to(ROOT)}: missing language block(s): {", ".join(missing)}')

    sections = []
    for code, _, direction in LANGS:
        body = render_block(code, blocks[code])
        sections.append(f'<section class="doc" id="doc-{code}" lang="{code}" dir="{direction}">\n{body}\n</section>')
    pills = '\n'.join(
        f'    <a href="#{code}" hreflang="{code}" lang="{code}" dir="{direction}">{html.escape(label)}</a>'
        for code, label, direction in LANGS
    )
    # #en / #ar / #ckb are empty anchors at the very top, so switching language
    # never scrolls the page; section links (#ar-s7) scroll to their heading.
    anchors = '\n'.join(f'<span class="lang-anchor" id="{code}"></span>' for code, _, _ in LANGS)
    title = html.escape(page['title'])
    return f"""<!DOCTYPE html>
<!-- Generated by docs/tools/build_legal_pages.py from {source.relative_to(ROOT)} — edit the Markdown, not this file. -->
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="theme-color" content="#C9A227">
<meta name="description" content="{html.escape(page['description'])}">
<title>{title} · Golden Gift</title>
<link rel="icon" type="image/png" href="/favicon.png">
<style>{CSS}</style>
</head>
<body>
{anchors}
<header class="top"><div class="inner"><a class="brand" href="/">{GIFT_ICON}<span>Golden Gift</span></a></div></header>
<nav class="langs" aria-label="Language"><div class="inner">
{pills}
</div></nav>
<main>
{chr(10).join(sections)}
</main>
<footer>
  <a href="/privacy">Privacy Policy</a> · <a href="/terms">Terms of Service</a> ·
  <a href="mailto:support@goldengift.app">support@goldengift.app</a>
</footer>
<script>{SCRIPT}</script>
</body>
</html>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--check', action='store_true', help='fail when a page is out of date')
    args = parser.parse_args()
    stale = []
    for page in PAGES:
        content = build_page(page)
        target = page['target']
        if args.check:
            if not target.exists() or target.read_text(encoding='utf-8') != content:
                stale.append(str(target.relative_to(ROOT)))
        else:
            target.write_text(content, encoding='utf-8')
            print(f'wrote {target.relative_to(ROOT)}')
    if stale:
        print('out of date (run python3 docs/tools/build_legal_pages.py): ' + ', '.join(stale))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
