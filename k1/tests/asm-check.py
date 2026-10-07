#!/usr/bin/env python3
"""Check k1/k1-asm.fth against k1/k1.S: the object the seed writes from the
Forth file must equal the one an assembler writes from k1.S.

  python3 k1/tests/asm-check.py [--as ASSEMBLER]   (from the repository root)

ASSEMBLER (default: as, GNU binutils) is run as ASSEMBLER k1/k1.S -o OUT.
Compared: the .text and .data bytes, each global symbol's section and offset,
and every relocation as (section, offset, type, target, addend), where a
target defined locally is spelled as its section plus offset (GNU as refers to
local labels through the section symbol, the Forth file through the label).
Requires ./seed-forth (./build.sh).
"""
import argparse, pathlib, struct, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
LAYERS = ["010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth", "081-cc-object.fth",
          "tools/obj-asm.fth", "k1/k1-asm.fth"]
TYPES = {1: "R_X86_64_64", 2: "R_X86_64_PC32", 4: "R_X86_64_PLT32"}


def parse(path):
    data = pathlib.Path(path).read_bytes()
    assert data[:4] == b"\x7fELF" and data[4] == 2 and data[16] == 1, path
    shoff, = struct.unpack_from("<Q", data, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", data, 0x3A)
    sh = [struct.unpack_from("<IIQQQQIIQQ", data, shoff + i * shentsize) for i in range(shnum)]
    def name(off, table):
        start = sh[table][4] + off
        return data[start:data.index(b"\0", start)].decode()
    names = [name(s[0], shstrndx) for s in sh]
    content = {names[i]: data[s[4]:s[4] + s[5]] for i, s in enumerate(sh) if s[1] != 8}
    symtab = next(i for i, s in enumerate(sh) if s[1] == 2)
    syms = []
    for k in range(sh[symtab][5] // 24):
        st_name, info, other, shndx, value, size = struct.unpack_from(
            "<IBBHQQ", data, sh[symtab][4] + 24 * k)
        syms.append((name(st_name, sh[symtab][6]), info >> 4, info & 15, shndx, value))
    globals_ = {}
    for n, bind, typ, shndx, value in syms:
        if bind == 1 and shndx:
            globals_[n] = (names[shndx], value)
    relocs = set()
    for i, s in enumerate(sh):
        if s[1] != 4:
            continue
        target_section = names[s[7]]
        for k in range(s[5] // 24):
            off, info, addend = struct.unpack_from("<QQq", data, s[4] + 24 * k)
            n, bind, typ, shndx, value = syms[info >> 32]
            if bind == 0:                   # local: section plus offset
                target, addend = names[shndx], value + addend
            else:
                target = n
            relocs.add((target_section, off, TYPES.get(info & 0xFFFFFFFF, info & 0xFFFFFFFF),
                        target, addend))
    return {"text": content[".text"], "data": content[".data"],
            "globals": globals_, "relocs": relocs}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--as", dest="assembler", default="as")
    args = ap.parse_args()
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        reference = tmp / "k1-S.o"
        subprocess.run([args.assembler, str(ROOT / "k1/k1.S"), "-o", str(reference)], check=True)
        out = tmp / "k1-asm.o"
        driver = (b"\ncreate check-output s, " + str(out).encode()
                  + b" [lit] 0 c,\ncheck-output cc-obj-write bye\n")
        stdin = b"".join((ROOT / f).read_bytes() for f in LAYERS) + driver
        run = subprocess.run([str(ROOT / "seed-forth")], input=stdin, capture_output=True)
        if run.returncode or run.stdout or run.stderr:
            sys.exit(f"asm-check: seed-forth exit {run.returncode}: "
                     f"{(run.stdout + run.stderr).decode(errors='replace')}")
        a, b = parse(reference), parse(out)
    failures = 0
    for key in ("text", "data", "globals", "relocs"):
        if a[key] != b[key]:
            failures += 1
            print(f"asm-check: {key} differs")
            if key in ("globals", "relocs"):
                left, right = (set(a[key].items()), set(b[key].items())) if key == "globals" \
                    else (a[key], b[key])
                for item in sorted(left - right, key=str):
                    print(f"  only in {args.assembler}: {item}")
                for item in sorted(right - left, key=str):
                    print(f"  only in k1-asm.fth: {item}")
            else:
                for i, (x, y) in enumerate(zip(a[key], b[key])):
                    if x != y:
                        print(f"  first difference at offset {i:#x}")
                        break
                if len(a[key]) != len(b[key]):
                    print(f"  sizes {len(a[key])} and {len(b[key])}")
    if failures:
        sys.exit(1)
    print(f"asm-check: k1-asm.fth equals {args.assembler} k1.S: {len(a['text'])} text bytes, "
          f"{len(a['data'])} data bytes, {len(a['globals'])} globals, {len(a['relocs'])} relocations")


if __name__ == "__main__":
    main()
