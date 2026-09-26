#!/usr/bin/env python3
"""tools/check-links.py — check every link and anchor in book/*.md.

    tools/check-links.py              check the Markdown sources (fast, no mdBook)
    tools/check-links.py --verbose    also list every heading anchor per file
    tools/check-links.py --html DIR   additionally cross-check against an
                                      `mdbook build -d DIR` render: every
                                      anchor this script derives must exist
                                      as an id in the rendered page

What is checked, for every book/*.md file (fenced code blocks and inline
code spans are ignored):

  * inline links and images `[text](target)`, reference definitions
    `[ref]: target`, and raw-HTML `href="target"`;
  * a relative target must exist; `.md` targets from a chapter rendered by
    mdBook (one listed in SUMMARY.md) must themselves be in SUMMARY.md, since
    mdBook renders nothing else (create-missing = false);
  * a rendered chapter must not link outside book/: mdBook copies only
    book/ into the site, so `../000-seed.hex0` 404s there (use a full
    https://github.com/... URL instead);
  * a `#fragment` must match a heading anchor of the target page, computed
    with mdBook 0.4's rules (utils::unique_id_from_content): strip the
    heading's inline markup, keep alphanumerics, `_` and `-`, map
    whitespace to `-`, lowercase ASCII, and suffix repeats with -1, -2, ...
    Explicit `{#id}` heading attributes and raw-HTML id="..."/name="..."
    anchors count too;
  * every SUMMARY.md entry exists.

External (scheme:) links are not fetched.  Exit 0 iff no problem is found.
"""
import html
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOOK = os.path.join(ROOT, "book")

FENCE = re.compile(r"^ *(`{3,}|~{3,})")
ATX = re.compile(r"^ {0,3}(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$")
SETEXT = re.compile(r"^ {0,3}(=+|-+)[ \t]*$")
ATTR = re.compile(r"\s*\{#([^\s}]+)[^}]*\}\s*$")
HTML_ID = re.compile(r"""\b(?:id|name)\s*=\s*["']([^"']+)["']""")
HREF = re.compile(r"""\bhref\s*=\s*["']([^"']+)["']""")
REFDEF = re.compile(r"^ {0,3}\[([^\]]+)\]:\s*<?(\S+?)>?(?:\s+.*)?$")
SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


def strip_code_spans(text, keep=False):
    """Remove (or, with keep, unwrap) `code` spans, per CommonMark's
    matching-backtick-run rule."""
    out, i = [], 0
    while i < len(text):
        if text[i] == "\\" and i + 1 < len(text):
            out.append(text[i:i + 2]); i += 2; continue
        if text[i] == "`":
            j = i
            while j < len(text) and text[j] == "`":
                j += 1
            run = text[i:j]
            k = text.find(run, j)
            # the closing run must be exactly as long
            while k != -1 and k + len(run) < len(text) and text[k + len(run)] == "`":
                k = text.find(run, k + len(run) + 1)
            if k == -1:
                out.append(run); i = j; continue
            body = text[j:k]
            if keep:
                if body.strip() and body[0] == " " and body[-1] == " ":
                    body = body[1:-1]
                out.append("\x00" + body + "\x01")
            else:
                out.append("C" * max(1, len(body)))
            i = k + len(run); continue
        out.append(text[i]); i += 1
    return "".join(out)


def heading_plain(raw):
    """Approximate the text mdBook's id_from_content sees: the heading's
    rendered HTML minus <em>/<code>/<strong> tags and a few entities."""
    t = strip_code_spans(raw, keep=True)
    # links/images: keep the link text
    t = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", t)
    t = re.sub(r"!?\[([^\]]*)\]\[[^\]]*\]", r"\1", t)
    parts = re.split(r"(\x00[^\x01]*\x01)", t)
    res = []
    for p in parts:
        if p.startswith("\x00"):
            res.append(p[1:-1])                      # code: literal
            continue
        p = re.sub(r"\\([!-/:-@\[-`{-~])", "\x02\\1", p)   # escaped punct
        p = p.replace("*", "")                      # emphasis markers
        # `_` delimits emphasis only when not intraword (CommonMark)
        p = re.sub(r"(?<![0-9A-Za-z])_+|_+(?![0-9A-Za-z])", "", p)
        p = p.replace("\x02", "")
        p = re.sub(r"<[^>]+>", lambda m: m.group(0) if not re.match(
            r"</?(em|code|strong)>", m.group(0)) else "", p)
        p = html.unescape(p)
        res.append(p)
    return "".join(res)


def normalize_id(content):
    out = []
    for ch in content.strip().lstrip("#").strip():
        if ch.isalnum() or ch in "_-":
            out.append(ch.lower() if ch.isascii() else ch)
        elif ch.isspace():
            out.append("-")
    return "".join(out)


def scan(path):
    """Return (anchors, links) for one Markdown file.
    anchors: set of ids; links: list of (lineno, target)."""
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    anchors, links, counts = set(), [], defaultdict(int)
    fence = None
    prev = ""

    def add_heading(text):
        m = ATTR.search(text)
        if m:
            anchors.add(m.group(1)); return
        base = normalize_id(heading_plain(text))
        n = counts[base]
        counts[base] += 1
        anchors.add(base if n == 0 else f"{base}-{n}")

    for no, line in enumerate(lines, 1):
        m = FENCE.match(line)
        if fence:
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) \
                    and line.strip() == m.group(1):
                fence = None
            prev = ""
            continue
        if m:
            fence = m.group(1); prev = ""; continue
        h = ATX.match(line)
        if h and not line.startswith("    "):
            add_heading(h.group(2) or "")
        elif SETEXT.match(line) and prev.strip() and not ATX.match(prev) \
                and not prev.lstrip().startswith(("-", "*", "+", "|", ">")) \
                and not re.match(r"^\s*\d+[.)]\s", prev):
            add_heading(prev.strip())
        code_free = strip_code_spans(line)
        for a in HTML_ID.findall(code_free):
            anchors.add(a)
        for t in HREF.findall(code_free):
            links.append((no, t))
        r = REFDEF.match(code_free)
        if r:
            links.append((no, r.group(2)))
        else:
            for t in re.findall(r"\]\(\s*<?([^()\s<>]*(?:\([^()\s]*\)[^()\s<>]*)*)>?(?:\s+[\"'][^\"']*[\"'])?\s*\)",
                                code_free):
                links.append((no, t))
        prev = line
    return anchors, links


def summary_files():
    files = []
    with open(os.path.join(BOOK, "SUMMARY.md"), encoding="utf-8") as f:
        for no, line in enumerate(f, 1):
            for t in re.findall(r"\]\(([^)]+)\)", strip_code_spans(line)):
                files.append((no, t))
    return files


def main():
    args = sys.argv[1:]
    verbose = "--verbose" in args
    html_dir = None
    if "--html" in args:
        html_dir = args[args.index("--html") + 1]

    mds = sorted(f for f in os.listdir(BOOK) if f.endswith(".md"))
    info = {f: scan(os.path.join(BOOK, f)) for f in mds}
    problems = []

    rendered = set()
    for no, t in summary_files():
        p = t.split("#")[0]
        if not os.path.exists(os.path.join(BOOK, p)):
            problems.append(f"book/SUMMARY.md:{no}: entry {t!r} does not exist")
        rendered.add(os.path.normpath(p))

    nlinks = nanch = 0
    for f in mds:
        anchors, links = info[f]
        if verbose:
            print(f"{f}: {' '.join(sorted(anchors))}")
        for no, t in links:
            if not t or SCHEME.match(t):
                continue
            nlinks += 1
            path, _, frag = t.partition("#")
            where = f"book/{f}:{no}"
            if path:
                full = os.path.normpath(os.path.join(BOOK, path))
                if full.endswith(".html") and full.startswith(BOOK + os.sep):
                    full = full[:-5] + ".md"
                rel = os.path.relpath(full, BOOK)
                if not os.path.exists(full):
                    problems.append(f"{where}: link target {t!r} does not exist")
                    continue
                if f in rendered and rel.startswith(".."):
                    problems.append(f"{where}: {t!r} points outside book/; "
                                    "it 404s on the rendered site (use a GitHub URL)")
                    continue
                if f in rendered and rel.endswith(".md") and rel not in rendered:
                    problems.append(f"{where}: {t!r} is not in SUMMARY.md, "
                                    "so mdBook does not render it")
                    continue
                target = rel if rel.endswith(".md") and not rel.startswith("..") else None
            else:
                target = f
            if frag and target:
                nanch += 1
                if target not in info:
                    continue
                if frag not in info[target][0]:
                    problems.append(f"{where}: anchor #{frag} not found in book/{target}")

    if html_dir:
        for f in mds:
            page = os.path.join(html_dir, f[:-3] + ".html")
            if f == "README.md":
                page = os.path.join(html_dir, "index.html")
            if f not in rendered or not os.path.exists(page):
                continue
            with open(page, encoding="utf-8") as fh:
                ids = set(re.findall(r'<h[1-6] id="([^"]+)"', fh.read()))
            heads = {a for a in info[f][0]}
            for a in sorted(ids - heads):
                problems.append(f"book/{f}: rendered heading id #{a} not derived "
                                "by check-links (slug rule mismatch)")

    for p in problems:
        print(p)
    print(f"check-links: {len(mds)} files, {nlinks} local links, {nanch} anchors, "
          f"{len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
