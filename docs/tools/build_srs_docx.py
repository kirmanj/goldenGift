"""Regenerate docs/GoldenGift_SRS.docx from docs/GOLDENGIFT_SRS.md.

The existing .docx is its own template: styles, list numbering, header and
footer are kept, and only the body (word/document.xml) is rebuilt from the
Markdown. The page-header version ("Golden Gift — SRS vX.Y") follows the
Version row of the SRS metadata table.

Run from the repo root after every SRS edit (Python 3.9+, stdlib only):
    python3 docs/tools/build_srs_docx.py

Supported Markdown (everything the SRS uses): `# ` title, `## ` / `### `
headings (contents entries), paragraphs, `- ` bullets, `1. ` numbered lists,
pipe tables (an all-empty header row = table without header), ``` code
blocks, `---` page breaks (except the first), **bold** and `code` inline.
Open the .docx in Word and update fields (F9) to fill contents page numbers.
"""
import argparse
import re
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from xml.sax.saxutils import escape as _esc

DOCS = Path(__file__).resolve().parent.parent
PAGE_W = 9638  # A4 width minus 2 × 1134 margins (twips)

CONSOLAS = ('<w:rFonts w:ascii="Consolas" w:cs="Consolas" '
            'w:eastAsia="Consolas" w:hAnsi="Consolas"/>')
TBL_BORDERS = ('<w:tblBorders>' + ''.join(
    f'<w:{s} w:val="single" w:color="auto" w:sz="4"/>'
    for s in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV')) + '</w:tblBorders>')
TC_BORDERS = ('<w:tcBorders>' + ''.join(
    f'<w:{s} w:val="single" w:color="D9D9D9" w:sz="4"/>'
    for s in ('top', 'left', 'bottom', 'right')) + '</w:tcBorders>')
TC_MAR = ('<w:tcMar><w:top w:type="dxa" w:w="60"/><w:left w:type="dxa" w:w="100"/>'
          '<w:bottom w:type="dxa" w:w="60"/><w:right w:type="dxa" w:w="100"/></w:tcMar>')
CODE_MAR = ('<w:tcMar><w:top w:type="dxa" w:w="100"/><w:left w:type="dxa" w:w="140"/>'
            '<w:bottom w:type="dxa" w:w="100"/><w:right w:type="dxa" w:w="140"/></w:tcMar>')
SPACER = '<w:p><w:pPr><w:spacing w:after="120"/></w:pPr></w:p>'
PAGE_BREAK = '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'
FIRST_NUMBERED_ID = 2  # numId 1 = bullets; 2.. = one decimal list each (abstractNum 2)


def esc(s):
    return _esc(s, {'"': '&quot;', "'": '&apos;'})


def t(text):
    return f'<w:t xml:space="preserve">{esc(text)}</w:t>'


def runs(text, size=None, header=False):
    """Inline markdown (**bold**, `code`) → w:r elements."""
    out, bold = [], header
    for tok in re.split(r'(`[^`]+`|\*\*)', text):
        if not tok:
            continue
        if tok == '**':
            bold = True if header else not bold
            continue
        code = tok.startswith('`') and tok.endswith('`') and len(tok) > 1
        body = tok[1:-1] if code else tok
        props = CONSOLAS if code else ''
        if bold:
            props += '<w:b/><w:bCs/>'
        if code:
            props += '<w:color w:val="7A1F1F"/>'
        elif header:
            props += '<w:color w:val="FFFFFF"/>'
        sz = size or (18 if code else None)
        if sz:
            props += f'<w:sz w:val="{sz}"/><w:szCs w:val="{sz}"/>'
        rpr = f'<w:rPr>{props}</w:rPr>' if props else ''
        out.append(f'<w:r>{rpr}{t(body)}</w:r>')
    return ''.join(out)


def split_row(line):
    """Split a table row on pipes that are not inside code spans."""
    cells, cur, in_code = [], '', False
    for ch in line.strip()[1:-1]:
        if ch == '`':
            in_code = not in_code
        if ch == '|' and not in_code:
            cells.append(cur.strip())
            cur = ''
        else:
            cur += ch
    cells.append(cur.strip())
    # GitHub needs `\|` for a pipe inside a table cell (even in code); Word doesn't.
    return [c.replace('\\|', '|') for c in cells]


def col_widths(rows, n):
    """Column widths proportional to content, each between 18 % and 70 %."""
    lens = [0] * n
    for r in rows:
        for i, c in enumerate(r[:n]):
            lens[i] += len(re.sub(r'[`*]', '', c)) + 8
    share = [min(max(l / sum(lens), 0.18), 0.70) for l in lens]
    widths = [int(PAGE_W * x / sum(share)) for x in share]
    widths[-1] += PAGE_W - sum(widths)
    return widths


def table(header, rows):
    n = len(header)
    xml = ['<w:tbl><w:tblPr><w:tblW w:type="pct" w:w="5000"/>', TBL_BORDERS, '</w:tblPr><w:tblGrid>']
    xml += [f'<w:gridCol w:w="{w}"/>' for w in col_widths([header] + rows, n)]
    xml.append('</w:tblGrid>')
    if any(header):
        xml.append('<w:tr><w:trPr><w:tblHeader/></w:trPr>')
        for c in header:
            xml.append(f'<w:tc><w:tcPr>{TC_BORDERS}<w:shd w:fill="B8921F" w:color="auto" w:val="clear"/>'
                       f'{TC_MAR}</w:tcPr><w:p>{runs(c, 19, header=True)}</w:p></w:tc>')
        xml.append('</w:tr>')
    for r in rows:
        xml.append('<w:tr><w:trPr><w:tblHeader w:val="off"/></w:trPr>')
        for c in (r + [''] * n)[:n]:
            xml.append(f'<w:tc><w:tcPr>{TC_BORDERS}{TC_MAR}</w:tcPr><w:p>{runs(c, 19)}</w:p></w:tc>')
        xml.append('</w:tr>')
    xml.append('</w:tbl>')
    return ''.join(xml) + SPACER


def code_block(lines):
    xml = ['<w:tbl><w:tblPr><w:tblW w:type="pct" w:w="5000"/>', TBL_BORDERS,
           f'</w:tblPr><w:tblGrid><w:gridCol w:w="{PAGE_W}"/></w:tblGrid><w:tr><w:tc><w:tcPr>',
           TC_BORDERS, '<w:shd w:fill="F5F5F7" w:color="auto" w:val="clear"/>', CODE_MAR, '</w:tcPr>']
    for ln in lines:
        xml.append(f'<w:p><w:pPr><w:spacing w:after="0"/></w:pPr><w:r><w:rPr>{CONSOLAS}'
                   f'<w:sz w:val="17"/><w:szCs w:val="17"/></w:rPr>{t(ln)}</w:r></w:p>')
    xml.append('</w:tc></w:tr></w:tbl>')
    return ''.join(xml) + SPACER


def list_item(num_id, text):
    return ('<w:p><w:pPr><w:pStyle w:val="ListParagraph"/><w:numPr><w:ilvl w:val="0"/>'
            f'<w:numId w:val="{num_id}"/></w:numPr><w:spacing w:after="60"/></w:pPr>{runs(text)}</w:p>')


def contents(toc):
    tab = '<w:tabs><w:tab w:val="right" w:pos="9638" w:leader="dot"/></w:tabs>'
    xml = ['<w:p><w:pPr><w:spacing w:after="120" w:before="300"/></w:pPr><w:r><w:rPr><w:b/><w:bCs/>'
           '<w:color w:val="B8921F"/><w:sz w:val="28"/><w:szCs w:val="28"/></w:rPr>'
           '<w:t xml:space="preserve">Contents</w:t></w:r></w:p>'
           '<w:sdt><w:sdtPr><w:alias w:val="Contents"/></w:sdtPr><w:sdtContent>']
    for k, (level, text, tid) in enumerate(toc):
        ind = '<w:ind w:left="220"/>' if level == 2 else ''
        field = ('<w:r><w:fldChar w:fldCharType="begin" w:dirty="true"/><w:instrText xml:space="preserve">'
                 'TOC \\h \\o &quot;1-2&quot;</w:instrText><w:fldChar w:fldCharType="separate"/></w:r>'
                 if k == 0 else '')
        xml.append(f'<w:p><w:pPr><w:pStyle w:val="TOC{level}"/>{tab}{ind}</w:pPr>{field}'
                   f'<w:hyperlink w:history="1" w:anchor="_Toc{tid}"><w:r>{t(text)}</w:r><w:r><w:tab/></w:r>'
                   f'<w:r><w:fldChar w:fldCharType="begin" w:dirty="true"/><w:instrText xml:space="preserve">'
                   f'PAGEREF _Toc{tid} \\h</w:instrText><w:fldChar w:fldCharType="separate"/>'
                   f'<w:fldChar w:fldCharType="end"/></w:r></w:hyperlink></w:p>')
    xml.append('<w:p><w:r><w:fldChar w:fldCharType="end"/></w:r></w:p></w:sdtContent></w:sdt>')
    return ''.join(xml)


def build_body(md):
    """Return (body xml, highest numbered-list numId used)."""
    lines = md.split('\n')
    body, toc = [], []
    num_id, in_numbered, hr_seen, i = FIRST_NUMBERED_ID - 1, False, 0, 0
    while i < len(lines):
        ln = lines[i]
        if ln.startswith('```'):
            j = i + 1
            while not lines[j].startswith('```'):
                j += 1
            body.append(code_block(lines[i + 1:j]))
            i, in_numbered = j + 1, False
            continue
        if ln.startswith('|'):
            block = []
            while i < len(lines) and lines[i].startswith('|'):
                block.append(lines[i])
                i += 1
            rows = [split_row(r) for r in block
                    if not (re.match(r'^\|[\s:|-]+\|$', r) and '-' in r)]
            body.append(table(rows[0], rows[1:]))
            in_numbered = False
            continue
        if ln.strip() == '---':
            hr_seen += 1
            if hr_seen > 1:
                body.append(PAGE_BREAK)
            in_numbered = False
        elif ln.startswith('# '):
            body.append(f'<w:p><w:pPr><w:pStyle w:val="Title"/><w:jc w:val="center"/></w:pPr>'
                        f'<w:r>{t(ln[2:])}</w:r></w:p>__CONTENTS__')
        elif ln.startswith(('## ', '### ')):
            level = 1 if ln.startswith('## ') else 2
            text = ln.split(' ', 1)[1]
            toc.append((level, text, len(toc) + 1))
            tid = len(toc)
            body.append(f'<w:p><w:pPr><w:pStyle w:val="Heading{level}"/></w:pPr>'
                        f'<w:bookmarkStart w:name="_Toc{tid}" w:id="{tid}"/>'
                        f'<w:r>{t(text)}</w:r><w:bookmarkEnd w:id="{tid}"/></w:p>')
            in_numbered = False
        elif ln.startswith('- '):
            body.append(list_item(1, ln[2:]))
        elif re.match(r'^\d+\. ', ln):
            if not in_numbered:
                num_id, in_numbered = num_id + 1, True
            body.append(list_item(num_id, re.sub(r'^\d+\. ', '', ln)))
        elif ln.strip():
            body.append(f'<w:p><w:pPr><w:spacing w:after="120"/></w:pPr>{runs(ln)}</w:p>')
            in_numbered = False
        i += 1
    return ''.join(body).replace('__CONTENTS__', contents(toc)), num_id


def ensure_numbering(numbering, max_id):
    """Add restart-at-1 decimal list instances so every numbered list has its own numId."""
    have = max(int(n) for n in re.findall(r'<w:num w:numId="(\d+)"', numbering))
    extra = ''.join(
        f'<w:num w:numId="{n}"><w:abstractNumId w:val="2"/><w:lvlOverride w:ilvl="0">'
        f'<w:startOverride w:val="1"/></w:lvlOverride></w:num>'
        for n in range(have + 1, max_id + 1))
    return numbering.replace('</w:numbering>', extra + '</w:numbering>')


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--md', default=DOCS / 'GOLDENGIFT_SRS.md', type=Path)
    ap.add_argument('--docx', default=DOCS / 'GoldenGift_SRS.docx', type=Path,
                    help='template to read and file to overwrite')
    args = ap.parse_args()

    md = args.md.read_text(encoding='utf-8')
    with zipfile.ZipFile(args.docx) as z:
        parts = [(info, z.read(info.filename)) for info in z.infolist()]

    body, max_num = build_body(md)
    version = re.search(r'^\| Version \| ([\d.]+)', md, re.M)
    stamp = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z')

    out = []
    for info, data in parts:
        name, xml = info.filename, None
        if name == 'word/document.xml':
            orig = data.decode('utf-8')
            head = orig[:orig.index('<w:body>') + len('<w:body>')]
            sect = re.findall(r'<w:sectPr>.*?</w:sectPr>', orig, re.S)[-1]
            xml = head + body + sect + '</w:body></w:document>'
        elif name == 'word/numbering.xml':
            xml = ensure_numbering(data.decode('utf-8'), max_num)
        elif name == 'word/header1.xml' and version:
            xml = re.sub(r'SRS v[\d.]+', f'SRS v{version.group(1)}', data.decode('utf-8'))
        elif name == 'docProps/core.xml':
            xml = re.sub(r'(<dcterms:modified[^>]*>)[^<]*', rf'\g<1>{stamp}', data.decode('utf-8'))
        out.append((info.filename, xml.encode('utf-8') if xml is not None else data))

    with zipfile.ZipFile(args.docx, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, data in out:
            z.writestr(name, data)
    print(f'wrote {args.docx} (v{version.group(1) if version else "?"}, '
          f'{body.count("<w:tbl>")} tables, {body.count("_Toc") // 3} headings)')


if __name__ == '__main__':
    main()
