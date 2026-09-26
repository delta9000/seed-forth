#!/usr/bin/env python3
"""tools/gen-index.py — generate book/WORD-INDEX.md, the book's alphabetical index.

    tools/gen-index.py            rewrite book/WORD-INDEX.md
    tools/gen-index.py --check    exit 1 (with a diff) if book/WORD-INDEX.md is stale
    tools/gen-index.py --stdout   print the index instead of writing it

Every entry links to the chapter section where the name is defined or
explained, using mdBook's heading-anchor rules.  Two sources feed it:

  * Definitions, derived from the book's literate source.  Every
    ```lang file=F / chunk=C fence is scanned (chapters are globbed, so a new
    chapter is picked up automatically):
      - 000-seed.hex0 chunks: each header's `; name  = "X"` is a seed
        primitive, each `;; ----- label @ 0xADDR` is a seed label;
      - Forth fences: `: X`, `variable X`, `create X`, `constant X` and
        `defer X` outside a colon definition define X.  010-lib.fth words are
        library words; every other file's are compiler (or assembler) words.
    The defining chapter is the one whose fence holds the definition.  The
    section is the heading above that fence, unless that heading is a
    generic one ("Canonical source"): then it is the first numbered section
    of the chapter whose heading names the word, else whose code defines it,
    else whose prose mentions it in backticks.
  * Concepts, from the curated CONCEPTS table below: (term, [(chapter file
    prefix, heading substring), ...]).  A heading that no longer exists is an
    error, so the table cannot silently rot.
"""
import difflib
import glob
import os
import re
import sys
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOOK = os.path.join(ROOT, "book")
OUT = os.path.join(BOOK, "WORD-INDEX.md")

# Chapters and appendices, in reading order.  GLOSSARY/CONCEPTS/INDEX and the
# authoring notes are not chapters.
CHAPTER_RE = re.compile(r"^(\d\d|A\d)-.*\.md$")

GENERIC_HEADINGS = {"canonical source", "try it", "exercises", "takeaways",
                    "after this chapter"}

# ---------------------------------------------------------------------------
# Curated concepts: term -> [(chapter file prefix, heading substring)].
# The heading substring is matched against the heading's plain text.
# ---------------------------------------------------------------------------
CONCEPTS = [
    ("Stack-effect notation", [("01-", "Stack-effect comments")]),
    ("Reverse Polish notation", [("01-", "Reverse Polish")]),
    ("Data stack", [("01-", "Reverse Polish"), ("14-", "The push and pop shapes")]),
    ("Return stack", [("04-", "Why two stacks at all"), ("14-", "bridging the two stacks")]),
    ("HERE (dictionary pointer)", [("02-", "Why a \"HERE\" exists"), ("17-", "here_code")]),
    ("[lit] convention (explicit literals)", [("02-", "one-line preview"), ("20-", "Why no auto-number")]),
    ("Functional completeness of NAND", [("03-", "Why \"logic from nand\" matters")]),
    ("De Morgan's law", [("03-", "`or` in six words")]),
    ("Two's complement", [("04-", "from `+` and `nand`")]),
    ("Primitive vs derived word (the byte trade)", [("03-", "What this buys"), ("04-", "Why subtraction isn't a primitive")]),
    ("Syscall ABI (x86-64 Linux)", [("05-", "sidebar on the syscall ABI"), ("16-", "Why six args")]),
    ("Range-check trick", [("06-", "The range-check trick")]),
    ("Sign test by division (2^63)", [("07-", "The `2^63` trick")]),
    ("Forth boolean (-1 / 0)", [("07-", "canonicalisation")]),
    ("Canonicalisation (0= 0=)", [("07-", "canonicalisation")]),
    ("Signed-overflow domain of <", [("07-", "The cascade")]),
    ("Little-endian cell writers", [("09-", "cell-sized emission")]),
    ("Division as a right shift", [("09-", "Why divide by 256")]),
    ("STATE (interpret vs compile mode)", [("10-", "and the two modes"), ("18-", "colon_code")]),
    ("IMMEDIATE flag", [("10-", "The IMMEDIATE flag"), ("18-", "Why `;` is IMMEDIATE")]),
    ("Dictionary header layout", [("10-", "Dictionary header layout"), ("17-", "The header layout")]),
    ("Runtime body (push-imm64)", [("10-", "runtime body")]),
    ("Execution token (xt)", [("11-", "load-time snapshot"), ("17-", "tick_code")]),
    ("Fixup on the stack", [("11-", "Forward branches")]),
    ("Emit, remember, patch", [("11-", "Forward branches"), ("25-", "Branches and `rel32` placeholders"), ("30-", "The forward reference")]),
    ("Chained fixups (else,)", [("11-", "chained fixups")]),
    ("Backward loops", [("11-", "Backward loops")]),
    ("Early exit (exit,)", [("11-", "`until,`, `again,` and `exit,`")]),
    ("Deferred words", [("12-", "`defer` and `is`")]),
    ("Counted names as data (s,)", [("12-", "names as data")]),
    ("ELF header and program header", [("13-", "The ELF magic"), ("13-", "The single `Elf64_Phdr`"), ("25-", "the ELF wrapper")]),
    ("Entry point (_start)", [("13-", "at `0x400078`")]),
    ("Sysvar page (STATE, LATEST, HERE, LAST_FOUND)", [("13-", "The sysvar init"), ("A1-", "A note on the sysvar page")]),
    ("TOS in rdi / data stack at rbp", [("14-", "The push and pop shapes")]),
    ("Subroutine threading", [("18-", "compile_call")]),
    ("Inline cell after a CALL", [("18-", "inline-cell trick"), ("19-", "The compiled shape")]),
    ("Consumed-slot property", [("19-", "The consumed-slot property")]),
    ("push rax; ret (indirect jump)", [("19-", "Why `push rax; ret`")]),
    ("Token reader and comment skipping", [("17-", "the token reader")]),
    ("Loud token errors (token?, exit 2)", [("17-", "failing out loud"), ("A7-", "The seed's own code")]),
    ("Linear dictionary search", [("17-", "`find_code`"), ("17-", "The chain")]),
    ("Number parser", [("20-", "parse_decimal_code")]),
    ("REPL (interpret/compile loop)", [("20-", "The REPL loop")]),
    ("Memory map", [("A2-", "The seed-Forth memory map"), ("A2-", "The C-compiler runtime heap")]),
    ("Arena (bump allocator)", [("21-", "The arena")]),
    ("Lexer state block", [("21-", "The lexer's state block"), ("23-", "putback, mark and reset")]),
    ("Error codes and cc-die", [("21-", "Failing: `cc-die`"), ("A7-", "How the codes are organised")]),
    ("Input, source and output buffers", [("21-", "The input and source buffers"), ("21-", "The output buffer")]),
    ("One buffer instead of streaming", [("21-", "Why one big buffer")]),
    ("Preprocessor", [("22-", "The pass driver")]),
    ("Macro table", [("22-", "Macro storage")]),
    ("#include and the include pool", [("22-", "`#include` and the four-slot include pool")]),
    ("#define (integer macros)", [("22-", "`#define`")]),
    ("Token kinds", [("23-", "Token kinds and punctuation IDs")]),
    ("Keyword table", [("23-", "The keyword table")]),
    ("Putback, mark and reset", [("23-", "putback, mark and reset"), ("27-", "One token of putback")]),
    ("Type encoding (one word per type)", [("24-", "The one-word type encoding")]),
    ("Symbol table", [("24-", "The symbol-table parallel arrays"), ("24-", "Adding and finding symbols")]),
    ("Scope stack", [("24-", "Scopes are a stack of integers")]),
    ("Struct descriptor", [("24-", "How types and symbols connect"), ("29-", "Struct definitions")]),
    ("Register convention (rdi accumulator)", [("25-", "register convention")]),
    ("Local-variable addressing (rbp - 8n)", [("25-", "Local-variable addressing")]),
    ("Forward-call fixup list", [("26-", "forward-call fixup list")]),
    ("libc shims", [("26-", "The libc shims")]),
    ("Escape decoding (string literals)", [("26-", "String-literal bytes")]),
    ("Global-address fixups", [("26-", "deferred vaddr fixups"), ("31-", "File-scope globals")]),
    ("Precedence cascade", [("27-", "The level template"), ("27-", "The cascade in motion")]),
    ("Operator table", [("27-", "The operator table")]),
    ("Left associativity", [("27-", "just like `mul`"), ("A4-", "Where left-associativity comes from")]),
    ("Short-circuit && and ||", [("27-", "Short-circuit")]),
    ("Lvalue tracking", [("28-", "Lvalue tracking")]),
    ("Postfix operators", [("28-", "The postfix operators")]),
    ("Assignment (snapshot, recurse, store)", [("28-", "Assignment: snapshot")]),
    ("Expectation helpers", [("29-", "Expectation helpers")]),
    ("Function pointers", [("29-", "Function pointers and the declaration engine")]),
    ("Break/continue fixup lists", [("30-", "Break/continue fixup lists")]),
    ("for-step rewind", [("30-", "with step rewind")]),
    ("switch with deferred dispatch", [("30-", "`switch` with deferred dispatch")]),
    ("Labels and goto", [("30-", "Labels and `goto`")]),
    ("Function frame (256 bytes, 32 slots)", [("31-", "Parameter lists and the spill"), ("29-", "File header and bookkeeping")]),
    ("Calling convention (six register arguments)", [("31-", "The call codegen")]),
    ("Entry stub", [("31-", "The entry stub")]),
    ("Top-level classification", [("31-", "Top-level elision")]),
    ("Enums and typedefs", [("31-", "Enums and typedefs")]),
    ("Stage-A parity proof", [("32-", "Stage A: the parity proof")]),
    ("Bootstrap chain", [("32-", "The wider chain"), ("A3-", "The chain at a glance")]),
    ("GCC-free build", [("A3-", "The GCC-free build")]),
    ("Diverse double-compiling", [("A3-", "diverse double-compiling")]),
    ("C subset (what is supported)", [("A6-", "Types"), ("A6-", "What an ISO C programmer")]),
]


# ---------------------------------------------------------------------------
# mdBook heading ids
# ---------------------------------------------------------------------------
def heading_text(md):
    """The rendered text of a heading's inline markdown."""
    t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", md)       # [text](url) -> text
    t = t.replace("`", "")
    t = re.sub(r"(\*\*|__|\*)", "", t)
    return t.strip()


def normalize_id(text):
    """mdBook's normalize_id: keep alphanumerics, '_' and '-' (ASCII
    lowercased), turn whitespace into '-', drop everything else."""
    out = []
    for ch in text:
        if ch.isalnum() or ch in "_-":
            out.append(ch.lower() if ch.isascii() else ch)
        elif ch.isspace():
            out.append("-")
    return "".join(out)


class Chapter:
    def __init__(self, path):
        self.path = path
        self.file = os.path.basename(path)
        self.lines = open(path, encoding="utf-8").read().split("\n")
        stem = self.file.split("-", 1)[0]
        if stem.startswith("A"):
            self.label = "App. " + chr(ord("A") + int(stem[1:]) - 1)
            self.order = 100 + int(stem[1:])
        else:
            n = int(stem)
            self.label = "Prologue" if n == 0 else "Ch %d" % n
            self.order = n
        self.headings = []      # (line_idx, level, raw, text, anchor)
        self.fences = []        # (start_idx, end_idx, lang, kind, name)
        counts = {}
        in_fence = False
        start = None
        info = None
        for i, line in enumerate(self.lines):
            if line.startswith("```"):
                if not in_fence:
                    in_fence, start, info = True, i, line[3:].strip()
                else:
                    in_fence = False
                    m = re.match(r"([A-Za-z0-9_-]*)\s+(file|chunk)=(\S+)", info)
                    if m:
                        self.fences.append((start, i, m.group(1), m.group(2), m.group(3)))
                continue
            if in_fence:
                continue
            m = re.match(r"^(#{1,6})\s+(.*?)\s*#*\s*$", line)
            if m:
                text = heading_text(m.group(2))
                base = normalize_id(text)
                n = counts.get(base, 0)
                counts[base] = n + 1
                anchor = base if n == 0 else "%s-%d" % (base, n)
                self.headings.append((i, len(m.group(1)), m.group(2), text, anchor))

    def heading_at(self, idx):
        """The nearest heading above line idx."""
        best = self.headings[0]
        for h in self.headings:
            if h[0] <= idx:
                best = h
        return best

    def sections(self):
        """(heading, first line, last line) for each level >= 2 heading."""
        hs = [h for h in self.headings if h[1] >= 2]
        for k, h in enumerate(hs):
            end = hs[k + 1][0] if k + 1 < len(hs) else len(self.lines)
            yield h, h[0], end

    def find_heading(self, needle):
        for h in self.headings:
            if needle.lower() in h[3].lower() or needle in h[2]:
                return h
        return None


def load_chapters():
    paths = sorted(p for p in glob.glob(os.path.join(BOOK, "*.md"))
                   if CHAPTER_RE.match(os.path.basename(p)))
    chs = [Chapter(p) for p in paths]
    chs.sort(key=lambda c: c.order)
    return chs


# ---------------------------------------------------------------------------
# Definitions from the literate fences
# ---------------------------------------------------------------------------
SKIP_NEXT = {"[char]", "char", "'", "[lit]", "is"}
DEFINERS = {":": "word", "variable": "variable", "create": "create",
            "constant": "constant", "defer": "defer"}


def forth_definitions(body_lines):
    """Yield (line offset, name, form) for each definition in Forth text."""
    in_colon = False
    in_paren = False
    skip = False
    pending = None
    for off, line in enumerate(body_lines):
        for tok in line.split():
            if in_paren:
                if tok.endswith(")"):
                    in_paren = False
                continue
            if tok == "\\":
                break
            if tok == "(":
                in_paren = True
                continue
            if skip:
                skip = False
                continue
            if pending is not None:
                if not re.match(r"^<<.*>>$", tok):
                    yield off, tok, pending
                if pending == "word":
                    in_colon = True
                pending = None
                continue
            if in_colon:
                if tok == ";":
                    in_colon = False
                elif tok in SKIP_NEXT:
                    skip = True
                continue
            if tok in SKIP_NEXT:
                skip = True
            elif tok in DEFINERS:
                pending = DEFINERS[tok]


def chunk_owners(chapters):
    """chunk name -> file that (transitively) includes it."""
    refs = {}
    for ch in chapters:
        for s, e, lang, kind, name in ch.fences:
            for line in ch.lines[s + 1:e]:
                m = re.match(r"^\s*<<(\S+)>>\s*$", line)
                if m:
                    refs.setdefault(m.group(1), (kind, name))
    owners = {}
    for chunk in refs:
        k, n, seen = refs[chunk][0], refs[chunk][1], set()
        while k == "chunk" and n in refs and n not in seen:
            seen.add(n)
            k, n = refs[n]
        if k == "file":
            owners[chunk] = n
    return owners


def pick_section(ch, fence_start, name):
    h = ch.heading_at(fence_start)
    if h[3].lower() not in GENERIC_HEADINGS:
        return h
    q = re.escape(name)
    tick = re.compile(r"`" + q + r"[`\s]")
    defin = re.compile(r"^\s*(:|variable|create|defer)\s+" + q + r"(\s|$)|\sconstant\s+" + q + r"(\s|$)")
    secs = [s for s in ch.sections() if s[0][3].lower() not in GENERIC_HEADINGS]
    for hh, a, b in secs:
        if tick.search(hh[2]):
            return hh
    spaced = name.replace("_", " ").lower()
    for hh, a, b in secs:
        if "_" in name and spaced in hh[3].lower():
            return hh
    for hh, a, b in secs:
        if any(defin.search(l) for l in ch.lines[a:b]):
            return hh
    for hh, a, b in secs:
        if any(tick.search(l) for l in ch.lines[a:b]):
            return hh
    return h


def collect_definitions(chapters):
    owners = chunk_owners(chapters)
    entries = {}    # name -> list of (kind, detail, chapter, heading)

    def add(name, kind, ch, h):
        lst = entries.setdefault(name, [])
        key = (kind, ch.file, h[4])
        if key not in [(k, c.file, hh[4]) for k, c, hh in lst]:
            lst.append((kind, ch, h))

    for ch in chapters:
        for s, e, lang, fkind, fname in ch.fences:
            target = fname if fkind == "file" else owners.get(fname, "")
            body = ch.lines[s + 1:e]
            if target == "000-seed.hex0" or lang == "hex0":
                for off, line in enumerate(body):
                    m = re.search(r';\s*name\s*=\s*"([^"]+)"', line)
                    if m:
                        add(m.group(1), "seed primitive", ch, pick_section(ch, s, m.group(1)))
                    m = re.match(r"^;; ----- (\S+) @ 0x", line)
                    if m:
                        add(m.group(1), "seed label", ch, pick_section(ch, s, m.group(1)))
                continue
            if not target.endswith(".fth"):
                continue
            if target == "010-lib.fth":
                who = "Forth word"
            elif "asm" in target:
                who = "assembler word"
            else:
                who = "compiler word"
            for off, name, form in forth_definitions(body):
                kind = "%s (%s, `%s`)" % (who, form, target) if form != "word" \
                    else "%s (`%s`)" % (who, target)
                add(name, kind, ch, pick_section(ch, s, name))
    return entries


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------
def md_escape_text(s):
    """Escape brackets outside code spans, for use inside link text."""
    parts = re.split(r"(`[^`]*`)", s)
    return "".join(p if p.startswith("`") else p.replace("[", "\\[").replace("]", "\\]")
                   for p in parts)


def link(ch, h):
    raw = h[2]
    m = re.match(r"^(\d+)\.\s+(.*)$", raw)
    if h[1] == 1:
        label = ch.label
    elif m:
        label = "%s §%s %s" % (ch.label, m.group(1), m.group(2))
    else:
        label = "%s, %s" % (ch.label, raw)
    anchor = "" if h[1] == 1 else "#" + h[4]
    return "[%s](%s%s)" % (md_escape_text(label), ch.file, anchor)


def code_span(name):
    return "`` %s ``" % name if "`" in name else "`%s`" % name


def sort_key(name):
    s = name.lstrip("_#")
    first = s[:1]
    return (0 if not first.isalpha() else 1, s.casefold(), name)


def group_of(name):
    s = name.lstrip("_#")
    return s[:1].upper() if s[:1].isalpha() else "Symbols and digits"


def render(chapters):
    defs = collect_definitions(chapters)
    by_file = {c.file: c for c in chapters}
    concept_rows = []
    errors = []
    for term, targets in CONCEPTS:
        links = []
        for prefix, needle in targets:
            ch = next((c for c in chapters if c.file.startswith(prefix)), None)
            h = ch.find_heading(needle) if ch else None
            if h is None:
                errors.append("concept %r: no heading containing %r in %s*.md"
                              % (term, needle, prefix))
                continue
            links.append(link(ch, h))
        concept_rows.append((term, links))
    if errors:
        for e in errors:
            print("gen-index: " + e, file=sys.stderr)
        sys.exit(2)

    items = []   # (sort key, markdown line)
    for name, lst in defs.items():
        kinds = []
        for k, _, _ in lst:
            if k not in kinds:
                kinds.append(k)
        links = []
        for k, ch, h in sorted(lst, key=lambda t: t[1].order):
            l = link(ch, h)
            if l not in links:
                links.append(l)
        if "seed primitive" in kinds:
            a1 = by_file.get(next((c.file for c in chapters if c.file.startswith("A1-")), ""), None)
            if a1 and a1.find_heading("The table"):
                links.append(link(a1, a1.find_heading("The table")))
        line = "- %s — *%s* — %s" % (code_span(name), "; ".join(kinds), " · ".join(links))
        items.append((sort_key(name), group_of(name), line))
    for term, links in concept_rows:
        line = "- **%s** — %s" % (term, " · ".join(links))
        items.append((sort_key(term), group_of(term), line))
    items.sort(key=lambda t: t[0])

    nwords = len(defs)
    out = [
        "# Index",
        "",
        "<!-- Generated by tools/gen-index.py; do not edit by hand.  Run",
        "     tools/gen-index.py after changing a chapter; check-all.sh runs",
        "     tools/gen-index.py --check. -->",
        "",
        "Every word the book defines, the seed's primitives and code labels,",
        "and the book's key ideas, with the chapter section that defines or",
        "explains each.  Names are in `code`; ideas are in **bold**.  A word's",
        "entry says what kind it is and which source file holds it:",
        "",
        "- *seed primitive* / *seed label*: a dictionary entry or a code label",
        "  in `000-seed.hex0` (Part II; the primitives are also tabled in",
        "  Appendix A);",
        "- *Forth word*: `010-lib.fth` (Part I);",
        "- *compiler word*: the C compiler, `020-cc-arena.fth` to",
        "  `120-cc-main.fth` (Part III);",
        "- *assembler word*: `130-asm.fth`.",
        "",
        "A kind in parentheses other than the file is the defining word used",
        "(`variable`, `constant`, `create`, `defer`); plain colon definitions",
        "carry none.  %d names and %d ideas." % (nwords, len(CONCEPTS)),
        "",
        "For a one-line definition of a term, see the [Glossary](GLOSSARY.md);",
        "for which chapter depends on which, the",
        "[concept graph](CONCEPTS.md).",
    ]
    group = None
    for key, g, line in items:
        if g != group:
            group = g
            out += ["", "## " + g, ""]
        out.append(line)
    return "\n".join(out) + "\n"


def main():
    args = sys.argv[1:]
    text = render(load_chapters())
    if "--stdout" in args:
        sys.stdout.write(text)
        return 0
    if "--check" in args:
        old = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
        if old == text:
            print("gen-index: book/WORD-INDEX.md is up to date")
            return 0
        sys.stdout.writelines(difflib.unified_diff(
            old.splitlines(True), text.splitlines(True),
            "book/WORD-INDEX.md (committed)", "book/WORD-INDEX.md (generated)", n=0))
        print("gen-index: book/WORD-INDEX.md is stale; run tools/gen-index.py")
        return 1
    open(OUT, "w", encoding="utf-8").write(text)
    print("gen-index: wrote book/WORD-INDEX.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
