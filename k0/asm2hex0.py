#!/usr/bin/env python3
"""Write k0.hex0 from k0.asm, in the style of 000-seed.hex0.

k0.hex0 is what gets built: stage0's hex0-seed turns it into k0.bin
with no other tool.  This script is how it is kept in step with the
readable k0.asm; k0/check.sh proves the two give identical bytes.

Every emitted line is one instruction or one data field.  Its comment
gives the file offset (the image loads at 0x100000, so offset 0xNNN is
address 0x100NNN), the source line, each relative branch's arithmetic,
and the value of each label or constant an operand names.

Usage: asm2hex0.py k0.asm k0.hex0   (needs nasm)
"""
import re, subprocess, sys, tempfile, os

ORG = 0x100000

def main():
    src, out = sys.argv[1], sys.argv[2]
    with tempfile.TemporaryDirectory() as t:
        lst, binf = os.path.join(t, "l"), os.path.join(t, "b")
        subprocess.run(["nasm", "-f", "bin", "-l", lst, "-o", binf, src],
                       check=True)
        image = open(binf, "rb").read()
        listing = open(lst).read().splitlines()
    source = open(src).read().splitlines()

    # Constants (equ) evaluated in order, for operand annotations.
    consts = {}
    for line in source:
        m = re.match(r"\s*(\w+)\s+equ\s+([^;]+)", line)
        if m:
            expr = m.group(2).strip()
            try:
                consts[m.group(1)] = eval(re.sub(r"\b[A-Za-z_]\w*\b",
                    lambda w: str(consts[w.group(0)]), expr))
            except Exception:
                pass

    # Listing rows: (source line number, offset, byte count, macro, text).
    row = re.compile(r"^\s*(\d+) (?:([0-9A-F]{8}) ([0-9A-F\[\]()]+)(-?))?"
                     r"\s*(<\d+>)?\s?(.*)$")
    items, labels, pending = [], {}, []
    cont = False
    for line in listing:
        m = row.match(line)
        if not m:
            continue
        num, off, hexes, more, macro, text = m.groups()
        if off is not None:
            n = len(re.sub(r"[\[\]()]", "", hexes)) // 2
            if cont:
                items[-1][2] += n
            else:
                items.append([int(num), int(off, 16), n, bool(macro), text])
            cont = bool(more)
            continue
        cont = False
        items.append([int(num), None, 0, bool(macro), text])
    # Label offsets: a label's offset is that of the next byte.
    for i, it in enumerate(items):
        m = re.match(r"\s*([.\w]+):", it[4])
        if m and not it[3]:
            off = it[1]
            j = i
            while off is None and j < len(items):
                off = items[j][1]
                j += 1
            if off is None:
                off = len(image)        # a label at the very end
            name = m.group(1)
            if not name.startswith("."):
                scope = name
            labels[name if not name.startswith(".") else scope + name] = off
            it.append(name if name.startswith(".") else name)
    out_lines = []
    emit = out_lines.append
    scope = None

    def fmt(bs, comment):
        h = " ".join(f"{b:02X}" for b in bs)
        emit(f"{h:<42}; {comment}".rstrip())

    def labelname(off):
        for k, v in labels.items():
            if v == off and (k.startswith(scope + ".") or "." not in k):
                return k.split(".", 1)[1] if k.startswith(scope + ".") \
                    else k
        return None

    def annotate(code, off, bs):
        notes = []
        mn = code.split()[0] if code.split() else ""
        if mn.startswith(("j", "call", "loop")) and ":" not in code:
            b = bs[1:] if bs[0] == 0x67 else bs
            nxt = off + len(bs)
            rel = None
            if b[0] in (0xEB, 0xE2, 0xE3) or 0x70 <= b[0] <= 0x7F:
                rel, w = int.from_bytes(b[1:2], "little", signed=True), 8
            elif b[0] in (0xE8, 0xE9):
                rel, w = int.from_bytes(b[1:5], "little", signed=True), 32
            elif b[0] == 0x0F and 0x80 <= b[1] <= 0x8F:
                rel, w = int.from_bytes(b[2:6], "little", signed=True), 32
            if rel is not None:
                notes.append(f"rel{w} = 0x{nxt + rel:03X} - 0x{nxt:03X}")
        for w in re.findall(r"(?<![.\w])[A-Za-z_]\w*", code.split(";")[0]):
            if w in labels and w != mn:
                notes.append(f"{w} = 0x{ORG + labels[w]:X}")
            elif w in consts and w != mn:
                v = consts[w]
                notes.append(f"{w} = {'-' if v < 0 else ''}0x{abs(v):X}")
        return f"  ({'; '.join(notes)})" if notes else ""

    srcmac = None
    for it in items:
        num, off, n, macro, text = it[:5]
        stripped = re.sub(r"^\s*[.\w]+:\s*", "", text) if len(it) > 5 \
            else text.strip()
        if len(it) > 5:
            name = it[5]
            if not name.startswith("."):
                scope = name
                if out_lines and out_lines[-1] != "":
                    emit("")
                emit(f";; ----- {name} @ 0x{labels[name]:03X} -----")
            else:
                emit(f";;   {name} @ 0x{labels[scope + name]:03X}")
        if off is None:
            s = stripped.strip()
            if macro:
                continue
            if re.match(r"(bits|org|default|%macro|%endmacro)\b", s):
                continue
            m = re.match(r"(\w+)\s+equ\s+([^;]*?)\s*(;.*)?$", s)
            if m:
                v = consts[m.group(1)]
                val = f"{'-' if v < 0 else ''}0x{abs(v):X}"
                expr = m.group(2)
                text = f"{m.group(1)} = {expr}" + \
                    (f" = {val}" if expr.lower() != val.lower() else "")
                emit(f";;   {text:<38}{m.group(3) or ''}".rstrip())
                continue
            if s.startswith(";"):
                emit(";" + s)
            elif s.startswith("SC "):
                srcmac = s
            elif not s:
                if out_lines and out_lines[-1] != "":
                    emit("")
            continue
        bs = image[off:off + n]
        if macro and srcmac:            # one syscall-table entry
            if n == 1:
                first = bs
                continue
            nr, h = srcmac[3:].split(",")
            h = h.split(";")[0].strip()
            fmt(first + bs, f"0x{off - 1:03X}  syscall {nr.strip()} -> {h}"
                f" (handlers + 0x{int.from_bytes(bs, 'little'):X})")
            continue
        code = stripped.strip()
        dm = re.match(r"(db|dw|dd|dq)\s+(.*)", code)
        if dm and "," in dm.group(2).split(";")[0] and '"' not in code:
            size = {"db": 1, "dw": 2, "dd": 4, "dq": 8}[dm.group(1)]
            parts = [p.strip() for p in dm.group(2).split(";")[0].split(",")]
            cmt = code.split(";", 1)[1].strip() if ";" in code else ""
            for k, p in enumerate(parts):
                o = off + k * size
                fmt(bs[k * size:(k + 1) * size],
                    f"0x{o:03X}  {dm.group(1)} {p}"
                    f"{annotate(p, o, bs)}" + (f"  ; {cmt}" if cmt and k == 0
                                                else ""))
            continue
        body, _, cmt = code.partition(";")
        note = annotate(body.strip(), off, bs)
        line = f"0x{off:03X}  {body.strip()}{note}"
        if cmt.strip():
            line += f"  ; {cmt.strip()}"
        fmt(bs, line)
    total = len(image)
    header = HEADER.format(size=total, end=ORG + total)
    text = re.sub(r"\n{3,}", "\n\n", "\n".join(out_lines).strip("\n"))
    open(out, "w").write(header + "\n" + text + "\n")

HEADER = """\
;; k0.hex0 — K0, a single-task bootstrap kernel for seed-forth's amd64 route
;;
;; License: MIT (see /LICENSE)
;;
;; K0 boots under QEMU as a multiboot kernel and runs the seed-only
;; amd64 route (seed -> pnut -> TinyCC 0.9.27) by providing the 17 Linux
;; syscalls it uses, over a RAM file system.  k0/README.md describes the
;; design, the boot image and every assumption about the chain.
;;
;; How to read this file: every line is one instruction or one data
;; field; the text after ';' is a comment (hex0 ignores it).  Each
;; comment starts with the file offset; the image loads at 0x100000, so
;; offset 0xNNN is address 0x100NNN.  Relative branches show their
;; arithmetic, (rel8 = target - next instruction); operands that name a
;; label or constant show its value.  The file is {size} bytes, loaded
;; at 0x100000 to 0x{end:X}.
;;
;; Build:  hex0-seed k0/k0.hex0 k0.bin  (stage0-posix's 229-byte hex0)
;; k0/k0.asm is the same program as NASM source; k0/check.sh proves
;; nasm(k0.asm) and hex0(k0.hex0) are byte-identical.
;;
;; Fixed addresses (identity-mapped):
;;   0x00100000  K0 (this file)
;;   0x00400000  user images (0x400000.. and 0x40000000..)
;;   0x30000000  PB, the canonical-path buffer; 0x30010000 KB, argv block
;;   0x3FFF0000  SP0, a new program's initial rsp; argv strings above it
;;   0x50000000  FSIMG, the boot image from mkfs.py; rbp = 0x50000080
;;   0x80000000  anonymous mmap and fork snapshots, growing up
"""

main()
