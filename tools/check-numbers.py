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
      - header form   "## N. `foo_code` in K bytes"  (also `+`, `nand`, ...)
      - offset form   "K-byte ... at offset `0xADDR`"
  * code-body offsets
      - "`foo_code` ... at offset `0xADDR`"
  * exact source-file line counts
      - "`NNN-cc-x.fth` ... K lines", "K-line file"  (approximate "~K"/"about
        K" is checked within tolerance and only warned, never failed)

Body sizes come from the `@ 0xADDR` comments in 000-seed.hex0: a label's size
is the distance to the next labelled offset (bodies and dictionary entries are
interleaved, so "next label" is the right boundary).  The last label's end is
the built seed's byte size.

Claims the script cannot confidently resolve are reported as "unchecked",
never as failures.  Exit status is non-zero only on a confident MISMATCH.

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

# Word / dictionary name -> the `_code` body label whose size the book quotes.
# (A word like `+` also has a *dictionary entry* at its own offset; the byte
# count the book teaches is always the body, so map to the body label.)
ALIAS = {
    "+": "plus_code", "nand": "nand_code", "0=": "zeq_code",
    "/": "divide_code", "*": "star_code",
    "@": "fetch_code", "!": "store_code", "c@": "cfetch_code", "c!": "cstore_code",
    "dup": "dup_code", "drop": "drop_code", "swap": "swap_code",
    ">r": "to_r_code", "r>": "r_from_code", "r@": "r_at_code",
    "bye": "bye_code", "emit": "emit_code", "key": "key_code",
    "syscall6": "syscall6_code", "find": "find_code", "here": "here_code",
    ",": "comma_code", "execute": "execute_code",
    ":": "colon_code", ";": "semicolon_code", "lit": "lit_code", "[lit]": "lit_code",
    "branch": "branch_code", "0branch": "zbranch_code",
    "state": "state_code", "latest": "latest_code", "'": "tick_code",
    "parse_decimal": "parse_decimal_code", "bracket_lit": "bracket_lit_code",
}

LABEL_RE = re.compile(r";;\s*-+\s*(\S+)\s+@\s+0x([0-9A-Fa-f]+)")


def build_seed_table():
    """Return {label: (offset, size)} derived from 000-seed.hex0."""
    labels = []  # (offset, name)
    with open(SEED, encoding="utf-8") as f:
        for line in f:
            m = LABEL_RE.search(line)
            if m:
                labels.append((int(m.group(2), 16), m.group(1)))
    labels.sort()
    # End sentinel: the built seed's size (the last label runs to EOF).
    end = os.path.getsize(SEED_BIN) if os.path.exists(SEED_BIN) else None
    table = {}
    for i, (off, name) in enumerate(labels):
        if i + 1 < len(labels):
            size = labels[i + 1][0] - off
        elif end is not None:
            size = end - off
        else:
            size = None
        # First definition wins (labels are unique offsets anyway).
        table.setdefault(name, (off, size))
    return table, {off: name for off, name in labels}


def resolve(entity, table):
    # A bare word like `dup` exists both as a `_code` body (the size the book
    # teaches) and as a dictionary entry at its own offset.  The alias map
    # points at the body, so it must win over the literal table lookup.
    entity = entity.strip()
    if entity in ALIAS:
        return ALIAS[entity]
    if entity in table:
        return entity
    return None


def source_files():
    names = set()
    for p in glob.glob(os.path.join(ROOT, "*.fth")):
        names.add(os.path.basename(p))
    names.add("000-seed.hex0")
    return {n: os.path.join(ROOT, n) for n in names}


def line_count(path):
    with open(path, encoding="utf-8") as f:
        return sum(1 for _ in f)


def num(s):
    return int(s.replace(",", ""))


# --- claim patterns ----------------------------------------------------------
# Header size:  "## 3. `0=` in 15 bytes"  (only on heading lines, where the
# entity-in-K-bytes is unambiguous and singular — avoids prose "in 70 bytes
# total" over a comma list).
HDR_SIZE_RE = re.compile(r"`([^`]+)`\s+in\s+(\d+)\s+bytes\b")
# Offset-anchored size:  "9-byte machine-code routine at offset `0x1A1`"
OFF_SIZE_RE = re.compile(r"(\d+)-byte\b[^.]{0,80}?\boffset\s+`0x([0-9A-Fa-f]+)`")
# Label at offset:  "`plus_code` ... at offset `0x1A1`"
LABEL_OFF_RE = re.compile(r"`([a-z0-9_]+_code)`[^.]{0,80}?\boffset\s+`0x([0-9A-Fa-f]+)`")

APPROX = re.compile(r"(~|\babout\b|\broughly\b|\bnearly\b|\balmost\b|\bover\b|\bunder\b)")
# File-*total* line-count forms (a span like "851 lines: file header" is NOT
# one of these, and is deliberately left unchecked).
TOTAL_LINE_A = re.compile(r"(\d[\d,]*)-line\s+file\b")        # "the entire 630-line file"
TOTAL_LINE_B = re.compile(r"\bat\s+(\d[\d,]*)\s+lines\b")      # "the longest file ... at 2752 lines"


def addr_size(table, off2name, addr):
    """Size of the label sitting exactly at `addr` (also tries vaddr form)."""
    for a in (addr, addr - 0x400000):
        name = off2name.get(a)
        if name:
            return table[name][1], name
    return None, None


def check():
    table, off2name = build_seed_table()
    files = source_files()
    file_re = re.compile(
        r"`(" + "|".join(re.escape(n) for n in files) + r")`")
    findings = []  # (severity, file, line, msg)
    seen = set()

    def emit(sev, fpath, lineno, msg, key):
        if key in seen:
            return
        seen.add(key)
        findings.append((sev, os.path.relpath(fpath, ROOT), lineno, msg))

    for md in sorted(glob.glob(os.path.join(BOOK, "*.md"))):
        lines = open(md, encoding="utf-8").read().splitlines()
        for i, line in enumerate(lines):
            window = line if i + 1 >= len(lines) else line + " " + lines[i + 1]

            def report_line(token):
                return i + 1 if token in line else i + 2

            # --- header size claims (heading lines only) ---
            if line.lstrip().startswith("#"):
                for ent, k in HDR_SIZE_RE.findall(line):
                    lab = resolve(ent, table)
                    if not lab or table.get(lab, (None, None))[1] is None:
                        continue
                    true = table[lab][1]
                    claimed = int(k)
                    key = (md, i, "hdrsize", lab, claimed)
                    if claimed != true:
                        emit("MISMATCH", md, i + 1,
                             f"`{ent}` claimed {claimed} bytes; {lab} is {true} bytes", key)
                    else:
                        emit("OK", md, i + 1, f"`{ent}` = {true} bytes", key)

            # --- offset-anchored size claims ---
            for k, addr in OFF_SIZE_RE.findall(window):
                size, name = addr_size(table, off2name, int(addr, 16))
                if size is None:
                    continue
                claimed = int(k)
                ln = report_line(k + "-byte")
                key = (md, "offsize", addr, claimed)
                if claimed != size:
                    emit("MISMATCH", md, ln,
                         f"{claimed}-byte at 0x{addr.upper()} ({name}) — true size {size}", key)
                else:
                    emit("OK", md, ln, f"{claimed}-byte at 0x{addr.upper()} ({name})", key)

            # --- label-offset claims ---
            for lab, addr in LABEL_OFF_RE.findall(window):
                if lab not in table:
                    continue
                true_off = table[lab][0]
                claimed = int(addr, 16)
                ln = report_line("`" + lab + "`")
                key = (md, "laboff", lab, claimed)
                if claimed != true_off:
                    emit("MISMATCH", md, ln,
                         f"`{lab}` claimed at 0x{claimed:X}; true offset 0x{true_off:X}", key)
                else:
                    emit("OK", md, ln, f"`{lab}` at 0x{true_off:X}", key)

            # --- file line counts ---
            # Only the phrasings that assert a file's *total* length, with a
            # resolvable filename in the window.  "N lines" near a filename
            # usually means a SPAN the chapter covers ("these 24 lines",
            # "851 lines: file header", "1,314 lines of foo.fth") — not the
            # file size — so those are deliberately left unchecked.
            fm = file_re.search(window)
            if fm:
                fname = fm.group(1)
                actual = line_count(files[fname])
                totals = list(TOTAL_LINE_A.finditer(window))      # "630-line file"
                totals += list(TOTAL_LINE_B.finditer(window))     # "...at 2752 lines"
                if "entire file" in window:                       # "37 lines ... (entire file)"
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
                                 f"{fname} ~{claimed} lines; actual {actual} (approx, off by "
                                 f"{abs(claimed - actual)})", key)
                    else:
                        emit("MISMATCH", md, ln,
                             f"{fname} claimed {claimed} lines; actual {actual}", key)

    return findings


def dump():
    table, _ = build_seed_table()
    for name, (off, size) in sorted(table.items(), key=lambda kv: kv[1][0]):
        print(f"  0x{off:04X}  {('%d bytes' % size) if size is not None else '?':>10}  {name}")


def main():
    if "--dump" in sys.argv:
        dump()
        return 0
    findings = check()
    mism = [f for f in findings if f[0] == "MISMATCH"]
    warn = [f for f in findings if f[0] == "WARN"]
    ok = [f for f in findings if f[0] == "OK"]
    for sev, fpath, lineno, msg in mism + warn:
        print(f"{sev}: {fpath}:{lineno}  {msg}")
    print(f"check-numbers: {len(ok)} OK, {len(warn)} WARN, {len(mism)} MISMATCH "
          f"(numeric claims verified against source)")
    return 1 if mism else 0


if __name__ == "__main__":
    sys.exit(main())
