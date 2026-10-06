#!/usr/bin/env python3
"""Check this teaching edition's document contracts; never execute seed code.

Run from any directory: python3 books/check.py
Use --source-root PATH when checking a separately materialized source snapshot.
This is a bounded manuscript checker, not a compiler test or learning study.
"""

import argparse
import csv
import hashlib
import re
from pathlib import Path
from urllib.parse import unquote, urlsplit


REV = "7d7e1996d1753118181d43e1a413960d3a1ec24b"
ROOT = Path(__file__).resolve().parent
SOURCE_BLOBS = {
    "000-seed.hex0": "67df9029071a6513a20b3c7695e057925b4f4b9a",
    "010-lib.fth": "f0d58f4f90fc462db97fbc0028f1318fe6d94fc0",
}


def visible_lines(text):
    """Ignore fenced bodies when inspecting prose links and headings."""
    inside = False
    for line in text.splitlines():
        if line.startswith("```"):
            inside = not inside
            continue
        if not inside:
            yield line


def slug(heading):
    # GitHub's heading convention for the characters used in these chapters.
    heading = re.sub(r"[`*_]", "", heading).strip().lower()
    heading = "".join(c for c in heading if c.isalnum() or c in " -_")
    return heading.replace(" ", "-")


def anchors(text):
    result = set()
    counts = {}
    for line in visible_lines(text):
        if re.match(r"^#{1,6} ", line):
            key = slug(re.sub(r"^#+ ", "", line))
            count = counts.get(key, 0)
            counts[key] = count + 1
            result.add(key if count == 0 else f"{key}-{count}")
    return result


def check_documents():
    files = sorted(ROOT.rglob("*.md"))
    checked_links = 0
    for path in files:
        text = path.read_text()
        fences = [line for line in text.splitlines() if line.startswith("```")]
        assert len(fences) % 2 == 0, f"Unbalanced fence: {path}"
        assert not any(re.search(r"(?:file|chunk)=", f) for f in fences), path
        prose = "\n".join(visible_lines(text))
        for target in re.findall(r"\]\(([^\s)]+)\)", prose):
            checked_links += 1
            url = urlsplit(target)
            if url.scheme:
                if "github.com/delta9000/seed-forth/blob/" in target:
                    assert f"/blob/{REV}/" in target, f"Unpinned source: {target}"
                continue
            destination = (path.parent / unquote(url.path)).resolve() if url.path else path
            assert destination.is_relative_to(ROOT), f"Link escapes teaching tree: {target}"
            assert destination.is_file(), f"Missing {path.name} -> {target}"
            if url.fragment:
                assert unquote(url.fragment) in anchors(destination.read_text()), (
                    f"Missing anchor {path.name} -> {target}"
                )
    for number, name in [(1, "values-and-words"), (2, "addresses-and-bytes"),
                         (3, "bits-and-subtraction")]:
        chapter = ROOT / f"seed-forth/chapters/{number:02}-{name}.md"
        solutions = ROOT / f"seed-forth/practice/{number:02}-solutions.md"
        expected = {f"S{number}-{i:02}" for i in range(1, 6)}
        for file in [chapter, solutions]:
            found = set(re.findall(rf"\bS{number}-\d{{2}}\b", file.read_text()))
            assert found == expected, (file, found)
    print(f"PASS: {len(files)} Markdown files; {checked_links} links; 15 exercise ID pairs")


def check_coverage():
    with (ROOT / "coverage.csv").open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    paths = [row["source_path"] for row in rows]
    assert len(paths) == len(set(paths)), "Duplicate source inventory rows"
    numbered = {int(re.match(r"book/(\d\d)-", p).group(1))
                for p in paths if re.match(r"book/\d\d-", p)}
    appendices = {int(re.match(r"book/A(\d)-", p).group(1))
                  for p in paths if re.match(r"book/A\d-", p)}
    assert numbered == set(range(50)), numbered
    assert appendices == set(range(1, 8)), appendices
    for row in rows:
        assert row["source_revision"] == REV, row["source_path"]
        assert row["migration_status"] in {"partial", "planned"}, row
        assert row["remaining_scope"], row["source_path"]
    print(f"PASS: {len(rows)} source inventory rows include all 50 chapters and 7 appendices")


def source_words(text):
    text = re.sub(r"\\[^\n]*", "", text)
    return text.split()


def check_sources(source_root):
    for name, wanted in SOURCE_BLOBS.items():
        data = (source_root / name).read_bytes()
        actual = hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()
        assert actual == wanted, f"Source edition mismatch: {name} {actual}"
    seed = (source_root / "000-seed.hex0").read_text()
    hexadecimal = "".join(re.split(r"[;#]", line)[0] for line in seed.splitlines())
    image = bytes.fromhex(hexadecimal)
    assert len(image) == 1772
    assert len(re.findall(r"^;; --- .* @ 0x[0-9A-F]+ --- header(?:  IMMEDIATE)?$", seed, re.M)) == 32
    assert int.from_bytes(image[0x60:0x68], "little") == 1772
    # Token-level comparison permits omitted comments/formatting in excerpts.
    library = source_words((source_root / "010-lib.fth").read_text())
    count = 0
    for name in ["here-addr", "c,", "and", "or", "-"]:
        start = next(i for i in range(len(library)-1)
                     if library[i:i+2] == [":", name])
        end = library.index(";", start)
        expected = library[start:end+1]
        found = False
        for path in (ROOT / "seed-forth/chapters").glob("*.md"):
            for block in re.findall(r"```forth\n(.*?)\n```", path.read_text(), re.S):
                words = source_words(block)
                if words[:2] == [":", name] and "___" not in block:
                    assert words == expected, f"Changed excerpt for {name}: {path}"
                    found = True
        assert found, f"Missing source excerpt: {name}"
        count += 1
    print(f"PASS: 2 pinned source blobs; 1772 source bytes; 32 primitive headers; {count} excerpts")
    print("Source-byte SHA256:", hashlib.sha256(image).hexdigest())


def check_models():
    """Assertions on the written mathematical model, not on the Forth seed."""
    m = 1 << 64
    u = m - 1
    nand = lambda a, b: (~(a & b)) & u
    conjunction = lambda a, b: nand(nand(a, b), nand(a, b))
    disjunction = lambda a, b: nand(nand(b, b), nand(a, a))
    inverse = lambda b: (nand(b, b) + 1) & u
    subtract = lambda a, b: (a + inverse(b)) & u
    for a, b in [(12, 10), (6, 3), (2, 4), (0, 0), (u, 0), (u, u)]:
        assert conjunction(a, b) == a & b
        assert disjunction(a, b) == a | b
    for a, b in [(7, 2), (2, 7), (15, 4), (1, 4), (u, 4)]:
        assert subtract(a, b) == (a-b) % m
    assert inverse(0) == 0 and inverse(5) == m-5
    assert inverse(1 << 63) == 1 << 63
    assert (3-10) % 256 == 249 and (10-3) % 256 == 7
    assert (3+4)*5 == 35 and 3+4*5 == 23
    assert 15//7 == 2 and 7//15 == 0 and 21//4 == 5 and 23//5 == 4
    assert ((2*u+1) & u) == u
    assert 52+18*256 == 4660 and 44+18*256 == 4652
    assert 300 % 256 == 44 and 511 % 256 == 255
    assert (4660 % 256, 4660//256) == (52, 18)
    assert (256 % 256, 256//256) == (0, 1)
    assert (1023 & ~255) | (1024 & 255) == 768
    print("PASS: bounded arithmetic, bitwise, byte-width and boundary assertions")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=ROOT.parent)
    args = parser.parse_args()
    check_documents()
    check_coverage()
    check_sources(args.source_root)
    check_models()
    print("These checks do not execute Forth, compile C, run a bootstrap, or establish reader learning.")


if __name__ == "__main__":
    main()
