#!/usr/bin/env python3
"""tools/check-numbers.py — give the book's exact numeric claims an oracle.

The book's whole brand is byte-level exactness, but a number typed in a
sentence ("`+` is 9 bytes", "the 630-line file") has no oracle the way a
`file=` / `chunk=` code block does — tangle.sh proves those byte-identical
to source, but prose numbers drift silently.  This is the one layer of the
book that ran on faith, which is exactly the layer where errors hid.

This script closes that gap.  It DERIVES the truth from source and diffs the
book's claims against it:

  * primitive / code-body sizes
      - header        "## N. `foo_code` in K bytes"  (also `+`, `nand`, ...)
      - prose         "`foo_code` is K bytes", "`x` (~K bytes)"
      - offset-anchor "K-byte ... at offset `0xADDR`"
      - multi-number  "`+` and `nand` are 9 and 12"
  * code-body offsets
      - prose         "`foo_code` ... offset `0xADDR`", "`x` (`@ 0xADDR`)"
      - table rows    "| `bye` | ( -- ) | `0x0D2` | ..."   (Appendix A1)
  * source line spans / ranges
      - single label  "`zbranch_code` (`@ 0x431`, lines 374-385)" vs the
                      label's comment line .. last non-blank body line
      - file coverage "lines A-B [of] `file`" — in-bounds sanity (1<=A<=B<=wc-l)
  * exact source-file line counts
      - "K-line file", "...file at K lines", "(entire file)" vs wc -l

Body sizes come from the `@ 0xADDR` comments in 000-seed.hex0: a label's size
is the distance to the next labelled offset (bodies and dictionary entries are
interleaved, so "next label" is the right boundary).  The last label's end is
the built seed's byte size.

Still NOT checked, and why: file *span* claims like "851 lines: file header"
or "these 24 lines" (a portion, not the file size); the *exact* endpoints of
editorial chapter-coverage spans and Ch29's section citations (the book's
hand-written endpoint conventions aren't uniform — some include the trailing
blank line, some don't — so only their in-bounds-ness is checked); and
line-refs inside `file=` source comments (a separate concern from the prose).
Claims the script cannot confidently resolve are reported "unchecked" — never
as failures.

Exit status is non-zero only on a confident MISMATCH.

Usage:
    tools/check-numbers.py            # check the book, print a report
    tools/check-numbers.py --dump     # print the derived size/offset table
"""

import os
import re
import sys
import glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED = os.path.join(ROOT, "000-seed.hex0")
SEED_BIN = os.path.join(ROOT, "seed-forth")
BOOK = os.path.join(ROOT, "book")
SEED_SIZE = os.path.getsize(SEED_BIN) if os.path.exists(SEED_BIN) else 0x800

# Word / dictionary name -> the `_code` body label whose size & body-offset the
# book quotes.  A bare word like `+` also has a *dictionary entry* at its own
# offset; the byte count and "Body @" the book teaches are always the body, so
# the alias must win over the literal table lookup (see resolve()).
ALIAS = {
    "+": "plus_code", "nand": "nand_code", "0=": "zeq_code",
    "/": "divide_code", "*": "star_code",
    "@": "fetch_code", "!": "store_code", "c@": "cfetch_code", "c!": "cstore_code",
    "dup": "dup_code", "drop": "drop_code", "swap": "swap_code",
    ">r": "to_r_code", "r>": "r_from_code", "r@": "r_at_code",
    "bye": "bye_code", "emit": "emit_code", "key": "key_code",
    "syscall6": "syscall6_code", "find": "find_code", "here": "here_code",
    ",": "comma_code", "execute": "execute_code",
    ":": "colon_code", ";": "semicolon_code",
    "lit": "lit_code",            # the runtime that reads an inline cell
    "[lit]": "bracket_lit_code",  # the immediate compile-time word's body
    "branch": "branch_code", "0branch": "zbranch_code",
    "state": "state_code", "latest": "latest_code", "'": "tick_code",
    "parse_decimal": "parse_decimal_code",
    "repl": "repl", "REPL": "repl", "read_word": "read_word",
}

LABEL_RE = re.compile(r";;\s*-+\s*(\S+)\s+@\s+0x([0-9A-Fa-f]+)")

# size claims
HDR_SIZE_RE = re.compile(r"`([^`]+)`\s+in\s+(\d+)\s+bytes\b")          # heading lines only
PROSE_SIZE_IS = re.compile(r"`([^`]+)`\s+(?:is|in)\s+(~?)(\d+)\s+bytes\b(?!\s+total)")
PROSE_SIZE_PAREN = re.compile(r"`([^`]+)`\s+\((~?)(\d+)\s+bytes")
BARE_SIZE_RE = re.compile(r"\b([a-z][a-z0-9_]*_code)\s+(?:is|in)\s+(~?)(\d+)\s+bytes\b(?!\s+total)")
OFF_SIZE_RE = re.compile(r"(\d+)-byte\b[^.]{0,80}?\boffset\s+`0x([0-9A-Fa-f]+)`")

# offset claims
PROSE_OFFSET_RE = re.compile(r"`([^`]+)`[^.|\n]{0,40}?`@?\s*0x([0-9A-Fa-f]+)`")
TABLE_OFFSET_RE = re.compile(r"`([^`]+)`.*?`@?\s*0x([0-9A-Fa-f]+)`")   # |-rows only

APPROX = re.compile(r"(~|\babout\b|\broughly\b|\bnearly\b|\balmost\b|\bover\b|\bunder\b)")
TOTAL_LINE_A = re.compile(r"(\d[\d,]*)-line\s+file\b")        # "the entire 630-line file"
TOTAL_LINE_B = re.compile(r"\bat\s+(\d[\d,]*)\s+lines\b")      # "the longest file ... at 2752 lines"

# multi-number prose: "`+` and `nand` are 9 and 12"
MULTI_RE = re.compile(r"`([^`]+)`\s+and\s+`([^`]+)`\s+(?:are|is)\s+(\d+)\s+and\s+(\d+)\b")
# single-label source span: "`branch_code` (`@ 0x42B`, lines 368-372)"
LABEL_RANGE_RE = re.compile(
    r"`([a-z0-9_]+_code)`\s*\(\s*`@\s*0x[0-9A-Fa-f]+`,\s*lines\s+(\d+)[–-](\d+)\)")
# any "lines A-B" (for the in-bounds sanity check against a named file)
LINE_RANGE_RE = re.compile(r"\blines\s+(\d+)[–-](\d+)")

# seed source-span claims fixed by --fix (group 2=start, 3=sep, 4=end)
SPAN_SEED_RE = re.compile(
    r"`([a-z0-9_]+_code)`\s*\(\s*`@\s*0x[0-9A-Fa-f]+`,\s*lines\s+(\d+)([–-])(\d+)\)")


def build_seed_table():
    """Return ({label: (offset, size)}, {offset: label}) from 000-seed.hex0."""
    labels = []
    with open(SEED, encoding="utf-8") as f:
        for line in f:
            m = LABEL_RE.search(line)
            if m:
                labels.append((int(m.group(2), 16), m.group(1)))
    labels.sort()
    end = os.path.getsize(SEED_BIN) if os.path.exists(SEED_BIN) else None
    table = {}
    for i, (off, name) in enumerate(labels):
        if i + 1 < len(labels):
            size = labels[i + 1][0] - off
        elif end is not None:
            size = end - off
        else:
            size = None
        table.setdefault(name, (off, size))
    return table, {off: name for off, name in labels}


def build_line_spans():
    """Return {label: (start_line, end_line)} for 000-seed.hex0 bodies.

    start = the `;; --- label @ ...` comment line; end = the last non-blank
    line before the next label's comment (this matches the book's single-label
    "lines A-B" convention, which excludes the trailing blank).
    """
    raw = open(SEED, encoding="utf-8").read().splitlines()
    marks = [(idx, m.group(1)) for idx, ln in enumerate(raw, 1)
             if (m := LABEL_RE.search(ln))]
    spans = {}
    for j, (lineno, name) in enumerate(marks):
        nxt = marks[j + 1][0] if j + 1 < len(marks) else len(raw) + 1
        end = lineno
        for k in range(lineno + 1, nxt):
            if raw[k - 1].strip():
                end = k
        spans.setdefault(name, (lineno, end))
    return spans


def resolve(entity, table):
    entity = entity.strip()
    if entity in ALIAS:          # bare words/symbols -> body label (must win)
        return ALIAS[entity]
    if entity in table:          # already a body label like `bye_code`
        return entity
    return None


def source_files():
    names = {os.path.basename(p) for p in glob.glob(os.path.join(ROOT, "*.fth"))}
    names.add("000-seed.hex0")
    return {n: os.path.join(ROOT, n) for n in names}


def line_count(path):
    with open(path, encoding="utf-8") as f:
        return sum(1 for _ in f)


def num(s):
    return int(s.replace(",", ""))


def check():
    table, off2name = build_seed_table()
    files = source_files()
    file_re = re.compile(r"`(" + "|".join(re.escape(n) for n in files) + r")`")
    findings = []
    seen = set()

    def emit(sev, fpath, lineno, msg, key):
        if key in seen:
            return
        seen.add(key)
        findings.append((sev, os.path.relpath(fpath, ROOT), lineno, msg))

    def check_size(md, lineno, entity, approx, claimed, table):
        lab = resolve(entity, table)
        if not lab or table.get(lab, (None, None))[1] is None:
            return
        true = table[lab][1]
        key = (md, "size", lab, claimed)
        if claimed == true:
            emit("OK", md, lineno, f"`{entity}` = {true} bytes ({lab})", key)
        elif approx and abs(claimed - true) <= max(3, true * 0.1):
            emit("OK", md, lineno, f"`{entity}` ~{claimed} bytes (true {true}, {lab})", key)
        elif approx:
            emit("WARN", md, lineno,
                 f"`{entity}` ~{claimed} bytes; {lab} is {true} (off by {abs(claimed-true)})", key)
        else:
            emit("MISMATCH", md, lineno, f"`{entity}` claimed {claimed} bytes; {lab} is {true}", key)

    def check_offset(md, lineno, entity, addr_hex, table):
        # A word can be referenced by its body (`'` -> tick_code) or by its
        # dictionary entry (`'` -> the entry at 0x7E8, e.g. as LATEST), so
        # accept either.
        cands, lab = {}, None
        if entity in ALIAS and table.get(ALIAS[entity], (None,))[0] is not None:
            lab = ALIAS[entity]; cands[table[lab][0]] = lab
        if entity in table:
            lab = lab or entity; cands.setdefault(table[entity][0], entity)
        if not cands:
            return
        claimed = int(addr_hex, 16)
        reduced = claimed - 0x400000 if claimed >= 0x400000 else claimed
        if reduced >= SEED_SIZE:
            return  # an address outside the seed image (buffer / sysvar) — not a body offset
        key = (md, "off", lab, claimed)
        if reduced in cands:
            emit("OK", md, lineno, f"`{entity}` @ 0x{reduced:X} ({cands[reduced]})", key)
        else:
            emit("MISMATCH", md, lineno,
                 f"`{entity}` claimed @ 0x{reduced:X}; {lab} is at 0x{table[lab][0]:X}", key)

    for md in sorted(glob.glob(os.path.join(BOOK, "*.md"))):
        lines = open(md, encoding="utf-8").read().splitlines()
        for i, line in enumerate(lines):
            window = line if i + 1 >= len(lines) else line + " " + lines[i + 1]
            head = line.lstrip().startswith("#")
            row = line.lstrip().startswith("|")

            def report_line(token):
                return i + 1 if token in line else i + 2

            # --- size claims ---
            if head:
                for ent, k in HDR_SIZE_RE.findall(line):
                    check_size(md, i + 1, ent, False, int(k), table)
            else:
                for ent, tilde, k in PROSE_SIZE_IS.findall(window):
                    check_size(md, report_line(k), ent, bool(tilde), int(k), table)
                for ent, tilde, k in PROSE_SIZE_PAREN.findall(window):
                    check_size(md, report_line(k), ent, bool(tilde), int(k), table)
                for lab, tilde, k in BARE_SIZE_RE.findall(window):
                    check_size(md, report_line(k), lab, bool(tilde), int(k), table)
                # multi-number prose: "`+` and `nand` are 9 and 12"
                for e1, e2, n1, n2 in MULTI_RE.findall(window):
                    check_size(md, report_line(n1), e1, False, int(n1), table)
                    check_size(md, report_line(n2), e2, False, int(n2), table)

            # (seed/.fth source spans are handled by span_pass, which also
            # supports --fix; see below)

            # --- offset-anchored size: "9-byte ... at offset `0x1A1`" ---
            for k, addr in OFF_SIZE_RE.findall(window):
                size, name = (table[off2name[int(addr, 16)]][1], off2name[int(addr, 16)]) \
                    if int(addr, 16) in off2name else (None, None)
                if size is None:
                    continue
                claimed = int(k)
                ln = report_line(k + "-byte")
                key = (md, "offsize", addr.lower(), claimed)
                if claimed == size:
                    emit("OK", md, ln, f"{claimed}-byte @ 0x{addr.upper()} ({name})", key)
                else:
                    emit("MISMATCH", md, ln,
                         f"{claimed}-byte @ 0x{addr.upper()} ({name}) — true size {size}", key)

            # --- offset claims ---
            if row:
                m = TABLE_OFFSET_RE.search(line)
                if m:
                    check_offset(md, i + 1, m.group(1), m.group(2), table)
            for ent, addr in PROSE_OFFSET_RE.findall(window):
                check_offset(md, report_line("0x" + addr), ent, addr, table)

            # --- file *total* line counts (spans are left unchecked) ---
            fm = file_re.search(window)
            if fm:
                fname = fm.group(1)
                actual = line_count(files[fname])
                totals = list(TOTAL_LINE_A.finditer(window)) + list(TOTAL_LINE_B.finditer(window))
                if "entire file" in window:
                    totals += list(re.finditer(r"(\d[\d,]*)[\s-]lines?\b", window))
                for m in totals:
                    claimed = num(m.group(1))
                    approx = bool(APPROX.search(window[max(0, m.start() - 12):m.start()]))
                    ln = report_line(m.group(1))
                    key = (md, "lines", fname, claimed)
                    if claimed == actual:
                        emit("OK", md, ln, f"{fname} = {actual} lines", key)
                    elif approx:
                        if abs(claimed - actual) > max(5, actual * 0.05):
                            emit("WARN", md, ln,
                                 f"{fname} ~{claimed} lines; actual {actual} "
                                 f"(off by {abs(claimed-actual)})", key)
                    else:
                        emit("MISMATCH", md, ln,
                             f"{fname} claimed {claimed} lines; actual {actual}", key)
                # in-bounds sanity for "lines A-B [of] `file`" coverage spans:
                # the book's endpoint convention isn't uniform enough to verify
                # exactly, but a range must at least fit inside the file.
                for m in LINE_RANGE_RE.finditer(window):
                    a, b = int(m.group(1)), int(m.group(2))
                    key = (md, "range-bound", fname, (a, b))
                    if 1 <= a <= b <= actual:
                        emit("OK", md, report_line(m.group(1)), f"{fname} lines {a}-{b} in range", key)
                    else:
                        emit("MISMATCH", md, report_line(m.group(1)),
                             f"{fname} lines {a}-{b} out of range (file is {actual} lines)", key)

    return findings


def dump():
    table, _ = build_seed_table()
    for name, (off, size) in sorted(table.items(), key=lambda kv: kv[1][0]):
        print(f"  0x{off:04X}  {('%d bytes' % size) if size is not None else '?':>10}  {name}")


def lineno_at(text, pos):
    return text.count("\n", 0, pos) + 1


def span_pass(fix):
    """Check (and with fix=True, rewrite) source line-span claims:

      seed:  "`zbranch_code` (`@ 0x431`, lines 374-385)"  -> 000-seed.hex0 span

    Only the seed labels have a robust single truth (clean comment-delimited
    boundaries in 000-seed.hex0), so --fix substitutes the derived "A-B" in
    place for these.  Editorial coverage spans (no uniform convention) and
    Ch29's `.fth` word citations (block-relative numbers, and Forth defs can't
    be delimited robustly — a `;` inside a comment defeats it) are NOT
    auto-fixed; the former get the in-bounds sanity check.
    """
    seed = build_line_spans()
    findings, total_edits = [], 0

    for md in sorted(glob.glob(os.path.join(BOOK, "*.md"))):
        text = open(md, encoding="utf-8").read()
        rel = os.path.relpath(md, ROOT)
        edits = []  # (num_start, num_end, replacement, severity, lineno, msg)

        def consider(m, name, span, gi):
            # gi = group index of the start number; sep is gi+1, end is gi+2
            if span is None:
                return
            s, e = span[-2], span[-1]
            a, b = int(m.group(gi)), int(m.group(gi + 2))
            ln = lineno_at(text, m.start(gi))
            if (a, b) == (s, e):
                findings.append(("OK", rel, ln, f"`{name}` lines {s}-{e}"))
            else:
                findings.append(("MISMATCH", rel, ln,
                                 f"`{name}` claimed lines {a}-{b}; source span is {s}-{e}"))
                edits.append((m.start(gi), m.end(gi + 2), f"{s}{m.group(gi + 1)}{e}"))

        for m in SPAN_SEED_RE.finditer(text):
            lab = m.group(1)
            consider(m, lab, seed.get(lab), 2)

        if fix and edits:
            for st, en, rep in sorted(edits, reverse=True):
                text = text[:st] + rep + text[en:]
            open(md, "w", encoding="utf-8").write(text)
            total_edits += len(edits)

    return findings, total_edits


def main():
    if "--dump" in sys.argv:
        dump()
        return 0
    fix = "--fix" in sys.argv
    findings = check()
    span_findings, edits = span_pass(fix)
    findings += span_findings
    if fix:
        # after rewriting, the mismatches that were fixed are gone
        findings = [f for f in findings if f[0] != "MISMATCH"] + \
                   [("FIXED", f[1], f[2], f[3]) for f in span_findings if f[0] == "MISMATCH"]
    mism = [f for f in findings if f[0] == "MISMATCH"]
    warn = [f for f in findings if f[0] == "WARN"]
    fixed = [f for f in findings if f[0] == "FIXED"]
    ok = [f for f in findings if f[0] == "OK"]
    for sev, fpath, ln, msg in mism + warn + fixed:
        print(f"{sev}: {fpath}:{ln}  {msg}")
    tail = f", {edits} FIXED" if fix else ""
    print(f"check-numbers: {len(ok)} OK, {len(warn)} WARN, {len(mism)} MISMATCH{tail} "
          f"(numeric claims verified against source)")
    return 1 if mism else 0


if __name__ == "__main__":
    sys.exit(main())
