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


def forth_blocks(text):
    language, lines = None, []
    for line in text.splitlines():
        if line.startswith("```"):
            if language is None:
                language, lines = line[3:].strip(), []
            else:
                if language in {"", "forth"}:
                    yield "\n".join(lines)
                language, lines = None, []
        elif language is not None:
            lines.append(line)


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
                         (3, "bits-and-subtraction"), (4, "return-stack-and-shuffles"),
                         (5, "comparisons-and-characters"), (6, "memory-updates-and-writers"),
                         (7, "linux-io-contracts"), (8, "defining-words-and-phases"),
                         (9, "control-flow-by-patching"), (10, "storage-deferred-words-and-bytes"),
                         (11, "executable-and-entry"), (12, "physical-stacks-and-memory"),
                         (13, "arithmetic-in-instruction-bytes"), (14, "physical-io-and-exit"),
                         (15, "dictionary-and-token-input"), (16, "native-colon-compiler")]:
        chapter = ROOT / f"seed-forth/chapters/{number:02}-{name}.md"
        solutions = ROOT / f"seed-forth/practice/{number:02}-solutions.md"
        expected = {f"S{number}-{i:02}" for i in range(1, 6)}
        for file in [chapter, solutions]:
            found = set(re.findall(rf"\bS{number}-\d{{2}}\b", file.read_text()))
            assert found == expected, (file, found)
    print(f"PASS: {len(files)} Markdown files; {checked_links} links; 80 exercise ID pairs")


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


def check_prerequisites():
    graph = {}
    for line in (ROOT / "COVERAGE.md").read_text().splitlines():
        if not re.match(r"^\| [SCGK]\d{2} —", line):
            continue
        fields = line.split("|")
        unit = re.search(r"[SCGK]\d{2}", fields[1]).group()
        graph[unit] = set(re.findall(r"[SCGK]\d{2}", fields[2]))
    assert len(graph) == 77, f"Expected 77 teaching units, got {len(graph)}"
    for unit, required in graph.items():
        assert required <= graph.keys(), (unit, required - graph.keys())
    done, visiting = set(), set()
    def visit(unit):
        assert unit not in visiting, f"Prerequisite cycle at {unit}"
        if unit in done:
            return
        visiting.add(unit)
        for prerequisite in graph[unit]:
            visit(prerequisite)
        visiting.remove(unit)
        done.add(unit)
    for unit in graph:
        visit(unit)
    print(f"PASS: {len(graph)} defined teaching units; acyclic prerequisite graph")


def source_words(text):
    text = re.sub(r"\\[^\n]*", "", text)
    text = re.sub(r"\([^)]*\)", "", text)
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
    required = ["here-addr", "c,", "and", "or", "-", "over", "rot", "nip",
                 "2dup", "2drop", "true", "=", "<>", "2^63", "0<", "<", ">", "<=", ">=",
                 "digit?", "alpha-lower?", "alpha-upper?", "alpha?", "space?", "+!", "-!", ",4", ",8"]
    names = re.findall(r"^:\s+(\S+)", (source_root / "010-lib.fth").read_text(), re.M)
    unquoted = []
    for name in names:
        start = next(i for i in range(len(library)-1)
                     if library[i:i+2] == [":", name])
        end = library.index(";", start)
        expected = library[start:end+1]
        found = False
        for path in (ROOT / "seed-forth/chapters").glob("*.md"):
            for block in forth_blocks(path.read_text()):
                words = source_words(block)
                if "___" in block:
                    continue
                # A colon inside an existing definition is an ordinary compiled
                # word here; it must not be mistaken for a second definition.
                i = 0
                while i < len(words)-1:
                    if words[i] != ":":
                        i += 1
                        continue
                    if ";" not in words[i+2:]:
                        break  # A labeled fragment is not a full definition.
                    end = words.index(";", i+2)
                    if words[i+1] == name:
                        assert words[i:end+1] == expected, f"Changed excerpt for {name}: {path}"
                        found = True
                    i = end+1
        if name in required:
            assert found, f"Missing source excerpt: {name}"
        if found:
            count += 1
        else:
            unquoted.append(name)
    print(f"PASS: 2 pinned source blobs; 1772 source bytes; 32 primitive headers; {count} excerpts")
    print("Source-byte SHA256:", hashlib.sha256(image).hexdigest())
    if unquoted:
        print("Source definitions not quoted in full:", ", ".join(unquoted))


def check_audit_partition(source_root):
    with (ROOT / "seed-forth/source-audit.csv").open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    source = (source_root / "000-seed.hex0").read_text().splitlines()
    offset, starts, image = 0, [], bytearray()
    for line in source:
        if line.startswith(";;") and (m := re.search(r"@ 0x([0-9A-Fa-f]+)", line)):
            assert int(m.group(1), 16) == offset
            starts.append(offset)
        data = re.split(r"[;#]", line)[0].strip()
        if data:
            decoded = bytes.fromhex(data)
            offset += len(decoded)
            image.extend(decoded)
    assert len(rows) == len(starts) == 76
    cursor = 0
    for i, row in enumerate(rows):
        start, end = int(row["start_offset"], 16), int(row["end_offset_exclusive"], 16)
        assert start == starts[i] == cursor
        assert end-start == int(row["bytes"]) > 0
        assert row["source_revision"] == REV
        assert row["manuscript_status"] in {"drafted", "planned"}
        if row["kind"] == "dictionary_header":
            name_size = image[start+9]
            name = bytes(image[start+10:start+10+name_size]).decode("ascii")
            assert row["section"] == "dictionary_header:"+name, row
            assert end-start == 10+name_size, row
        cursor = end
    assert cursor == offset == 1772
    drafted = sum(int(row["bytes"]) for row in rows if row["manuscript_status"] == "drafted")
    print(f"PASS: 76 source-offset regions partition 1772 bytes; {drafted} bytes assigned to drafted audit units")


def check_audit_listings(source_root):
    source = (source_root / "000-seed.hex0").read_text()
    image = bytes.fromhex("".join(re.split(r"[;#]", line)[0] for line in source.splitlines()))
    with (ROOT / "seed-forth/source-audit.csv").open(newline="") as stream:
        regions = list(csv.DictReader(stream))
    for number, filename in [(11, "executable-and-entry"), (12, "physical-stacks-and-memory"),
                              (13, "arithmetic-in-instruction-bytes"), (14, "physical-io-and-exit"),
                              (15, "dictionary-and-token-input"), (16, "native-colon-compiler")]:
        path = ROOT / f"seed-forth/chapters/{number:02}-{filename}.md"
        expected = set()
        for row in regions:
            if row["unit"] == f"S{number}":
                expected.update(range(int(row["start_offset"], 16), int(row["end_offset_exclusive"], 16)))
        seen, count, headers = set(), 0, []
        for line in path.read_text().splitlines():
            parts = [part.strip() for part in line.strip().split("|")[1:-1]]
            header = None
            if number == 15 and len(parts) >= 7:
                offset = re.fullmatch(r"`([0-9A-Fa-f]{4})`", parts[0])
                link = re.fullmatch(r"`0x([0-9A-Fa-f]+)`", parts[1])
                flags = re.fullmatch(r"`([0-9A-Fa-f]{2})`", parts[2])
                length = re.fullmatch(r"`([0-9A-Fa-f]{2})` \((\d+)\)", parts[3])
                name_bytes = re.fullmatch(r"`([0-9A-Fa-f ]+)`", parts[4])
                if all([offset, link, flags, length, name_bytes]):
                    name = bytes.fromhex(name_bytes.group(1))
                    n = int(length.group(1), 16)
                    assert n == int(length.group(2)) == len(name), line
                    displayed_name = re.search(r"`([^`]+)`", parts[5]).group(1)
                    assert name.decode("ascii") == displayed_name, line
                    start = int(offset.group(1), 16)
                    data = int(link.group(1), 16).to_bytes(8, "little") + bytes([int(flags.group(1), 16), n]) + name
                    code_start = 0x400000 + start + len(data)
                    displayed_xt = [int(m.group(1), 16) for part in parts[6:]
                                    if (m := re.fullmatch(r"`0x([0-9A-Fa-f]+)`", part))]
                    assert displayed_xt == [code_start], line
                    displayed_offsets = [int(m.group(1), 16) for part in parts[6:]
                                         if (m := re.fullmatch(r"`([0-9A-Fa-f]{3,4})`", part))]
                    if displayed_offsets:
                        assert displayed_offsets == [start+len(data)], line
                    header = (start, data)
                    headers.append((start, int(link.group(1), 16)))
            half_open = re.match(r"^\[([0-9A-Fa-f]{3,4}),([0-9A-Fa-f]{3,4})\)\s+((?:[0-9A-Fa-f]{2}\s+)+)", line)
            match = re.match(r"^([0-9A-Fa-f]{3,4})(?:[–-]([0-9A-Fa-f]{3,4}))?:?\s+((?:[0-9A-Fa-f]{2}\s+)+)", line)
            if header:
                start, data = header
            elif half_open:
                start, data = int(half_open.group(1), 16), bytes.fromhex(half_open.group(3))
                assert int(half_open.group(2), 16)-start == len(data), line
            elif match:
                start, data = int(match.group(1), 16), bytes.fromhex(match.group(3))
                if match.group(2):
                    assert int(match.group(2), 16)-start+1 == len(data), line
            else:
                field = re.match(r"^\| `([0-9A-Fa-f]{3,4})` \| (\d+) \| `([0-9A-Fa-f ]+)` \|", line)
                if not field:
                    continue
                start, data = int(field.group(1), 16), bytes.fromhex(field.group(3))
                assert len(data) == int(field.group(2)), line
            assert image[start:start+len(data)] == data, f"Byte mismatch in {path.name}: {line}"
            positions = set(range(start, start+len(data)))
            assert not seen & positions, f"Repeated byte range in {path.name}: {line}"
            seen.update(positions)
            count += 1
        assert seen == expected, f"Listing coverage mismatch in {path.name}: {len(seen)} versus {len(expected)}"
        if number == 15:
            assert len(headers) == 32
            for i, (offset, link) in enumerate(headers):
                assert link == (0 if i == 0 else 0x400000 + headers[i-1][0])
            assert headers[-1][0] == 0x617
        print(f"PASS: S{number} has {count} source-matched field/instruction rows covering {len(seen)} bytes")


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
    # The second unit extends the same stated model; these are not VM runs.
    h = 1 << 63
    less = lambda a, b: bool(((a-b) & u) // h)
    for a in [-h, -10, -1, 0, 1, 10, h-1]:
        for b in [-h, -10, -1, 0, 1, 10, h-1]:
            if -h <= a-b <= h-1:
                assert less(a, b) == (a < b)
            if abs(a-b) < h:
                assert less(b, a) == (a > b)
    assert less(h-1, -1) is True  # Deliberate out-of-domain counterexample.
    assert less(-h, 0) and less(0, -h)
    interval = lambda c, base, width: ((c-base) & u) // width == 0
    for c in range(256):
        assert interval(c, 48, 10) == (48 <= c <= 57)
        assert interval(c, 97, 26) == (97 <= c <= 122)
        assert interval(c, 65, 26) == (65 <= c <= 90)
        assert interval(c, 48, 8) == (48 <= c <= 55)
    assert ((7+3) & u) == 10 and subtract(7, 4) == 3
    assert bytes((305419896 >> (8*i)) & 255 for i in range(4)) == bytes.fromhex("78 56 34 12")
    assert bytes((72623859790382856 >> (8*i)) & 255 for i in range(8)) == bytes.fromhex("08 07 06 05 04 03 02 01")
    assert ((1 << 32)+1) & ((1 << 32)-1) == 1
    # Definition and control-flow byte ledgers are arithmetic models too.
    assert 10 + len("seven") == 15
    assert 4+4+2+8 == 18 and 18+1 == 19
    assert 1000 + 15 + 19 == 1034
    assert 5+13+13+5+13+1 == 50
    assert 2000+5+8+13 == 2026
    assert 18+5+5+1 == 29  # Deferred-word code before its cell.
    assert 5000+1 == 5001 and 3-1 == 2
    print("PASS: bounded arithmetic, bitwise, byte-width, comparison, classifier and layout assertions")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=ROOT.parent)
    args = parser.parse_args()
    check_documents()
    check_coverage()
    check_prerequisites()
    check_sources(args.source_root)
    check_models()
    check_audit_partition(args.source_root)
    check_audit_listings(args.source_root)
    print("These checks do not execute Forth, compile C, run a bootstrap, or establish reader learning.")


if __name__ == "__main__":
    main()
