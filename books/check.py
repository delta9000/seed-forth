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
    "tools/tcc-compile.fth": "c7804bdcb5ef7ebb6b1d774af175558013eb50be",
    "book/21-arena-and-io-buffers.md": "55d0af2ee7e885fd8f9f100e2be8376422c30559",
    "140-cc-link.fth": "57d274b12b643dda55400967c953ff42b0553875",
    "131-cc-aggregate-abi.fth": "1189822f2d8b5c79875aad99d046656b8e1d68ca",
    "129-cc-bitfield.fth": "2c959b8f86f2269da089775573e0822676f2a4fa",
    "128-cc-float-literal.fth": "31d954c700e1f82b0647898193af446e07fb4889",
    "127-cc-binary64.fth": "9ab64f4538ca10effae0167345cb79ae71d1d4fa",
    "126-cc-varargs.fth": "be1d9358ca78310addc8115d8e12549c86d5c357",
    "125-cc-consteval.fth": "cfb027acbd3502e4853847b629918702f2119693",
    "123-cc-object-program.fth": "0cb9ae99d22e6d05b827fb8559842746173b63b9",
    "122-cc-sysv-runtime.fth": "40c378cc6daae1210cd61c3d5569a6e97b00729f",
    "118-cc-native-init.fth": "f744a33e34982966e484178a8e94af9891792904",
    "116-cc-prog.fth": "28ef4a5db2bf7fec9ea3e4f324b79e42b534866f",
    "114-cc-func.fth": "031ca4a33124b075f4416c5f38781673616af8c4",
    "112-cc-stmt.fth": "ff9f637d7f2d617ef85bbaad2bbd6ba28da519f2",
    "110-cc-decl.fth": "779eeac5c753c141cb7e50b8454f42e666518a3b",
    "100-cc-expr.fth": "29ca0e38f19907fc4fd18286e22a0518072ad181",
    "090-cc-emit.fth": "55d922e8f36c1367fe27629cbd2edd8d8a577b84",
    "081-cc-object.fth": "5e5baa07cd19962f5f4a21eddb8e915abb7f69eb",
    "000-seed.hex0": "67df9029071a6513a20b3c7695e057925b4f4b9a",
    "010-lib.fth": "f0d58f4f90fc462db97fbc0028f1318fe6d94fc0",
    "020-cc-arena.fth": "7b4b41d4bc252eb6bbe65b99e8e69c1c39e631d1",
    "030-cc-io.fth": "b06d403c546f143a66b25add8ebb9568da3a2e17",
    "040-cc-prep.fth": "72ddd8beb9aeed867fdfe5cc1c62ab09cf41bb91",
    "050-cc-lex.fth": "72e785b9c996da9ebaf7db93b3ff360692bf40e3",
    "060-cc-types.fth": "b71cfd5e88ee99a94f8ebc0ac5b5e2dffb5d5c0d",
    "070-cc-sym.fth": "c9bc6dde33ea1cd30bae9965e9119c2540d4b6a5",
    "080-cc-elf.fth": "f4946890c4a2fde5a1e809ce6ae649fd20f6ca0e",
    "115-cc-native.fth": "bae8d62dfb9abe96da9b09c3e0ff413bd50f938d",
    "117-cc-native-program.fth": "dd17a74854225da077aeb627b660749898e72ad4",
    "119-cc-native-runtime.fth": "072cd8f8e8aa64260e28bc79e1c8b08a75faa250",
    "120-cc-main.fth": "3ce930098c5f6c97db0e6b6d358e8a862d2389e3",
    "121-cc-sysv.fth": "69a923a1356032e7c684abfdedb90c40516905c7",
    "124-cc-target.fth": "072acd33f8dbeb5335ec3bac3c96821f8661019c",
    "tools/compiler-layers.sh": "2a55fa711df62bf3ac43b674009a0db057b66496",
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


def all_fenced_blocks(text):
    language, lines = None, []
    for line in text.splitlines():
        if line.startswith("```"):
            if language is None:
                language, lines = line[3:].strip(), []
            else:
                yield language, "\n".join(lines)
                language, lines = None, []
        elif language is not None:
            lines.append(line)


def forth_blocks(text):
    for language, block in all_fenced_blocks(text):
        if language in {"", "forth"}:
            yield block


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
        references = {name.strip().lower(): target for name, target in
                      re.findall(r"^\[([^\]]+)\]:\s+(\S+)", prose, re.M)}
        for used in re.findall(r"\[[^\]]+\]\[([^\]]+)\]", prose):
            assert used.strip().lower() in references, f"Undefined reference {path.name}: {used}"
        targets = re.findall(r"\]\(([^\s)]+)\)", prose) + list(references.values())
        for target in targets:
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
                         (15, "dictionary-and-token-input"), (16, "native-colon-compiler"),
                         (17, "inline-branch-operands"), (18, "decimal-parser-and-repl"),
                         (19, "audit-synthesis-and-capstone")]:
        chapter = ROOT / f"seed-forth/chapters/{number:02}-{name}.md"
        solutions = ROOT / f"seed-forth/practice/{number:02}-solutions.md"
        expected = {f"S{number}-{i:02}" for i in range(1, 6)}
        for file in [chapter, solutions]:
            found = set(re.findall(rf"\bS{number}-\d{{2}}\b", file.read_text()))
            assert found == expected, (file, found)
    c_chapters = sorted((ROOT / "c-compiler/chapters").glob("[0-9][0-9]-*.md"))
    c_pairs = 0
    for chapter in c_chapters:
        number = int(chapter.name[:2])
        if number == 0:
            continue
        solution = ROOT / f"c-compiler/practice/{number:02}-solutions.md"
        assert solution.is_file(), f"Missing practice companion: {chapter}"
        exercise_count = {5: 6, 6: 7, 7: 7, 8: 8, 9: 8, 10: 9, 11: 8, 12: 8, 13: 7, 14: 10, 15: 7}.get(number, 5)
        c_pairs += exercise_count
        expected = {f"C{number}-{i:02}" for i in range(1, exercise_count+1)}
        for file in [chapter, solution]:
            found = set(re.findall(rf"\bC{number}-\d{{2}}\b", file.read_text()))
            assert found == expected, (file, found)
    pairs = 95 + c_pairs
    print(f"PASS: {len(files)} Markdown files; {checked_links} links; {pairs} exercise ID pairs")


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
        assert row["migration_status"] in {"draft_covered", "partial", "planned"}, row
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
    """Normalize displayed Forth without discarding literal delimiter tokens.

    This is a bounded textual excerpt check, not a Forth interpreter. A
    [char] operand (and top-level char/s, payload) can itself be '(' or '\\';
    it must not be mistaken for an explanatory comment.
    """
    words, position = [], 0
    in_definition, definition_name, literal_next = False, False, False
    while position < len(text):
        if text[position].isspace():
            position += 1
            continue
        if not literal_next and text[position] == "\\":
            end = text.find("\n", position)
            position = len(text) if end < 0 else end+1
            continue
        if not literal_next and text[position] == "(":
            end = text.find(")", position+1)
            assert end >= 0, "Unclosed Forth comment in excerpt/source"
            position = end+1
            continue
        end = position
        while end < len(text) and not text[end].isspace():
            end += 1
        word = text[position:end]
        words.append(word)
        position = end
        if literal_next:
            literal_next = False
            continue
        if definition_name:
            definition_name = False
            continue
        if word == ":" and not in_definition:
            in_definition, definition_name = True, True
        elif word == ";":
            in_definition = False
        elif word == "[char]" or (not in_definition and word in {"char", "s,"}):
            literal_next = True
    return words


def definition_end(words, start=0):
    """Find this dialect's definition terminator, ignoring [char] operands."""
    position = start+2  # Skip ':' and the name, which may itself be punctuation.
    while position < len(words):
        if words[position] == "[char]":
            position += 2
        elif words[position] == ";":
            return position
        else:
            position += 1
    return None


def check_sources(source_root):
    assert definition_end(source_words(": f [char] ; drop ;")) == 5
    assert definition_end(source_words(": f [char] ; drop")) is None
    assert source_words(": f [char] ( ;") == [":", "f", "[char]", "(", ";"]
    assert source_words("char ( ( comment )") == ["char", "("]
    assert source_words(": f ( stack comment ) dup ;") == [":", "f", "dup", ";"]
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
        end = definition_end(library, start)
        assert end is not None
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
                    end = definition_end(words, i)
                    if end is None:
                        break  # A labeled fragment is not a full definition.
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
    print(f"PASS: {len(SOURCE_BLOBS)} pinned source blobs; 1772 source bytes; 32 primitive headers; {count} library excerpts")
    print("Source-byte SHA256:", hashlib.sha256(image).hexdigest())
    if unquoted:
        print("Source definitions not quoted in full:", ", ".join(unquoted))


def check_c_excerpts(source_root):
    """Compare complete named C-compiler Forth excerpts, not pseudocode."""
    definitions = {}
    for name in SOURCE_BLOBS:
        if not re.match(r"[0-9]{3}-cc-.*\.fth$", name):
            continue
        text = (source_root / name).read_text()
        starts = list(re.finditer(r"^:\s+(\S+)", text, re.M))
        for i, start in enumerate(starts):
            region = text[start.start():starts[i+1].start() if i+1 < len(starts) else len(text)]
            words = source_words(region)
            end = definition_end(words)
            if end is not None:
                definitions.setdefault(start.group(1), []).append(words[:end+1])
    checked = set()
    for path in (ROOT / "c-compiler").rglob("*.md"):
        for language, block in all_fenced_blocks(path.read_text()):
            if language != "forth" or "___" in block:
                continue
            words = source_words(block)
            i = 0
            while i < len(words)-1:
                if words[i] != ":":
                    i += 1
                    continue
                end = definition_end(words, i)
                if end is None:
                    break  # A labeled partial excerpt needs manual review.
                name = words[i+1]
                if name in definitions:
                    assert words[i:end+1] in definitions[name], f"Changed C-compiler excerpt {name}: {path}"
                    checked.add((str(path.relative_to(ROOT)), name))
                i = end+1
    print(f"PASS: {len(checked)} complete named C-compiler excerpts match pinned source tokens")


def check_c_source_map(source_root):
    path = ROOT / "c-compiler/source-map.csv"
    if not path.exists():
        return
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    seen = set()
    for row in rows:
        key = (row["source_path"], row["word"])
        assert key not in seen, f"Duplicate C source-map word: {key}"
        seen.add(key)
        assert row["source_revision"] == REV
        assert row["source_blob_sha"] == SOURCE_BLOBS[row["source_path"]]
        lines = (source_root / row["source_path"]).read_text().splitlines()
        start, end = int(row["start_line"]), int(row["end_line"])
        assert 1 <= start <= end <= len(lines)
        assert re.match(r"^:\s+" + re.escape(row["word"]) + r"(?:\s|$)", lines[start-1]), row
        definition = source_words("\n".join(lines[start-1:end]))
        assert definition_end(definition) == len(definition)-1, row
        chapter = (ROOT / "c-compiler" / row["manuscript_path"]).resolve()
        assert chapter.is_relative_to(ROOT) and chapter.is_file(), row
        expected = f"https://github.com/delta9000/seed-forth/blob/{REV}/{row['source_path']}#L{start}-L{end}"
        assert row["source_url"] == expected, row
    for name in ["020-cc-arena.fth", "030-cc-io.fth", "050-cc-lex.fth",
                 "060-cc-types.fth", "070-cc-sym.fth", "080-cc-elf.fth",
                 "090-cc-emit.fth", "100-cc-expr.fth", "110-cc-decl.fth"]:
        expected = set(re.findall(r"^:\s+(\S+)", (source_root/name).read_text(), re.M))
        actual = {word for file, word in seen if file == name}
        assert actual == expected, (name, actual ^ expected)
    print(f"PASS: {len(rows)} C source-map definitions; complete infrastructure/representation/emission/parser definition inventories")


def check_preprocessor_regions(source_root):
    path = ROOT / "c-compiler/preprocessor-regions.csv"
    if not path.exists():
        return
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    source = (source_root / "040-cc-prep.fth").read_text().splitlines()
    next_line, names = 1, set()
    states = {"drafted": 0, "partial": 0, "planned": 0}
    for row in rows:
        assert row["source_path"] == "040-cc-prep.fth"
        assert row["source_revision"] == REV
        assert row["source_blob_sha"] == SOURCE_BLOBS[row["source_path"]]
        start, end = int(row["start_line"]), int(row["end_line"])
        assert start == next_line and start <= end <= len(source), row
        next_line = end+1
        expected = []
        for line in source[start-1:end]:
            line = line.split("\\", 1)[0]
            direct = re.match(r"^\s*(?::|create|variable|defer)\s+(\S+)", line)
            constant = re.search(r"\bconstant\s+(\S+)", line)
            if direct:
                expected.append(direct.group(1))
            elif constant:
                expected.append(constant.group(1))
        actual = row["declarations"].split("; ") if row["declarations"] else []
        assert actual == expected, (start, end, actual, expected)
        assert not names.intersection(actual), f"Repeated preprocessor declaration: {actual}"
        names.update(actual)
        assert row["primary_unit"] in {"C03", "C04", "C05"}
        status = row["manuscript_status"]
        assert status in states
        states[status] += 1
        if status != "planned":
            assert (ROOT / "c-compiler" / row["manuscript_path"]).is_file(), row
        assert row["source_url"] == f"https://github.com/delta9000/seed-forth/blob/{REV}/040-cc-prep.fth#L{start}-L{end}"
    assert next_line == len(source)+1
    assert len(rows) == 57 and len(names) == 325
    print(f"PASS: {len(rows)} preprocessor regions partition {len(source)} lines and {len(names)} declarations; states {states}")


def check_emission_map(source_root):
    path = ROOT / "c-compiler/emission-map.csv"
    if not path.exists():
        return
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    expected = {}
    for name in ["080-cc-elf.fth", "090-cc-emit.fth"]:
        for number, line in enumerate((source_root/name).read_text().splitlines(), 1):
            line = line.split("\\", 1)[0]
            direct = re.match(r"^\s*(:|create|variable|defer)\s+(\S+)", line)
            constant = re.search(r"\bconstant\s+(\S+)", line)
            if direct:
                kind, word = direct.groups()
                kind = "colon" if kind == ":" else kind
            elif constant:
                kind, word = "constant", constant.group(1)
            else:
                continue
            expected[(name, word)] = (number, kind)
    seen = set()
    for row in rows:
        key = (row["source_path"], row["name"])
        assert key not in seen
        seen.add(key)
        assert (int(row["source_line"]), row["declaration_kind"]) == expected[key], row
        assert row["source_revision"] == REV
        assert row["source_blob_sha"] == SOURCE_BLOBS[row["source_path"]]
        assert row["teaching_unit"] in {"C09", "C10", "C11"}
        assert (ROOT / "c-compiler" / row["manuscript_path"]).is_file(), row
        assert row["source_url"] == f"https://github.com/delta9000/seed-forth/blob/{REV}/{row['source_path']}#L{row['source_line']}"
    assert seen == expected.keys()
    assert len(rows) == 150
    print(f"PASS: {len(rows)} ELF/emitter declarations have source-matched teaching homes")


def check_parser_map(source_root):
    path = ROOT / "c-compiler/parser-map.csv"
    if not path.exists():
        return
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    expected = {}
    for name in ["100-cc-expr.fth", "110-cc-decl.fth"]:
        for number, line in enumerate((source_root/name).read_text().splitlines(), 1):
            line = line.split("\\", 1)[0]
            direct = re.match(r"^\s*(:|create|variable|defer)\s+(\S+)", line)
            constant = re.search(r"\bconstant\s+(\S+)", line)
            if direct:
                kind, word = direct.groups()
                kind = "colon" if kind == ":" else kind
            elif constant:
                kind, word = "constant", constant.group(1)
            else:
                continue
            expected[(name, word)] = (number, kind)
    seen = set()
    for row in rows:
        key = (row["source_path"], row["name"])
        assert key not in seen
        seen.add(key)
        assert (int(row["source_line"]), row["declaration_kind"]) == expected[key], row
        assert row["source_revision"] == REV
        assert row["source_blob_sha"] == SOURCE_BLOBS[row["source_path"]]
        assert row["teaching_unit"] in {"C10", "C12", "C13", "C14", "C15"}
        assert (ROOT / "c-compiler" / row["manuscript_path"]).is_file(), row
        assert row["source_url"] == f"https://github.com/delta9000/seed-forth/blob/{REV}/{row['source_path']}#L{row['source_line']}"
    assert seen == expected.keys()
    assert len(rows) == 333
    print(f"PASS: {len(rows)} expression/declaration names have source-matched teaching homes")


def check_c_models(source_root):
    chapter = ROOT / "c-compiler/chapters/01-compiler-entry-and-profile.md"
    if not chapter.exists():
        return
    original = (source_root / "book/21-arena-and-io-buffers.md").read_text()
    original_c = next(block for language, block in all_fenced_blocks(original) if language == "c")
    current_c = next(block for language, block in all_fenced_blocks(chapter.read_text()) if language == "c")
    assert current_c == original_c, "Recurring tri.c differs from its pinned source"
    # Paper C trace: arithmetic and loop requests, never compiled execution.
    def triangle(rows, offset=1):
        widths = [offset + 2*r for r in range(rows)]
        padding = [rows-1-r for r in range(rows)]
        stars = sum(widths)
        return widths, padding, stars, stars + sum(padding) + rows, stars if stars == rows*rows else 1
    assert triangle(4) == ([1,3,5,7], [3,2,1,0], 16, 26, 16)
    assert triangle(4, 2) == ([2,4,6,8], [3,2,1,0], 20, 30, 1)
    assert triangle(3) == ([1,3,5], [2,1,0], 9, 15, 9)
    assert 4*8 == 32 and 4*4 == 16
    # Bounded C02 state and byte calculations, not calls into source code.
    assert sum([3,4]) == 7 and 7+1 <= 8 and not 8+1 <= 8
    round8 = lambda n: (n+7)//8*8
    assert [round8(n) for n in [0,1,8,9]] == [0,8,8,16]
    assert 1000+round8(1)+round8(9) == 1024
    assert (1003+round8(9)) % 8 == 3
    assert list((1297).to_bytes(4, "little")) == [17,5,0,0]
    output = bytearray([65,66,17,5,0,0])
    output[0:4] = (305419896).to_bytes(4, "little")
    assert list(output) == [120,86,52,18,0,0]
    assert sum([3,7,4]) == 14
    assert (4097+4095)//4096*4096 == 8192
    assert (1 << 63)-4096 == 9223372036854771712
    # C03 and the first mixed check: exact fixture bytes and newline ownership.
    root = b'#include "a.h"\nR\n'
    parent = b'#include "b.h"\nA\n'
    child = b'B\n'
    assert [len(root), len(parent), len(child)] == [17, 17, 2]
    assert root.index(b'\n') == parent.index(b'\n') == 14
    flattened = child + parent[14:] + root[14:]
    assert flattened == b'B\n\nA\n\nR\n'
    assert len(flattened) == 8 and flattened.count(b'\n') == 5
    changed = child[:-1] + parent[14:] + root[14:]
    assert changed == b'B\nA\n\nR\n' and len(changed) == 7
    assert changed.count(b'\n') == 4
    assert len(b'Y\n\nX\n') == 5 and b'Y\n\nX\n'.count(b'\n') == 3
    assert len(b'tests/cc/') + len(b'a.h') + 1 == 13
    # C04/C05 byte/ownership examples remain bounded paper calculations.
    assert len(b'((\x01\x00)+(\x01\x01))') == 11
    prescan = b'  7  '
    substitute = b' ' + prescan + b' '
    final = b' ' + substitute + b' '
    assert [len(prescan), len(substitute), len(final)] == [5,7,9]
    assert 16*16 + 16 + len(prescan) == 277
    assert 277 + len(substitute) == 284
    assert len(b'  "a.h"  ') == 9
    assert len(b'  1 &&  4  ') == 11
    guarded = b'\n'*11 + b' 4 ' + b'\n'*4
    assert len(guarded) == 18 and guarded.count(b'\n') == 15
    assert 40-(1+1) == 38 and 2+38 == 40 and 3+38 == 41
    # C06–C08 representation calculations, not a substitute lexer/compiler.
    assert 8*8 == 64
    assert int("2147483648") == int("80000000", 16)
    assert len("2147483648") == len("0x80000000") == 10
    assert 6*65536 == 393216 and 11*65536 == 720896 and 2*65536 == 131072
    assert 56 + 8*40 + 16*40 == 1016
    assert 8*40 == 320 and 8*48 == 384
    capacities = [8,16,32,64,128,256,512,1023]
    assert sum(capacities) == 2039 and sum(capacities)*72+56 == 146864
    assert 1023*72 == 73656
    names = ["rows", "drawing", "rows"]
    find_name = lambda text: next((i for i in range(len(names)-1,-1,-1) if names[i] == text), -1)
    assert find_name("rows") == 2 and find_name("draw") == -1
    assert len("rows") == len("draw") == 4
    assert 8192*8 == 65536 and 64*8 == 512
    # C09–C11 emitted-data arithmetic, not execution of emitter words.
    pad = bytes.fromhex("48 8B 7D F8 57 48 C7 C7 01 00 00 00 48 89 F9 5F 48 29 CF 48 89 7D F8")
    assert len(pad) == 23 and 1024+len(pad) == 1047
    assert (-8*(15+1)) == -128 and (-8*(16+1)) == -136
    assert (-136).to_bytes(4, "little", signed=True) == bytes.fromhex("78 FF FF FF")
    assert 146-(1024+5) == -883
    assert (-883).to_bytes(4, "little", signed=True) == bytes.fromhex("8D FC FF FF")
    assert 1408-(1201+4) == 203
    assert (0x400000+1408).to_bytes(8, "little") == bytes.fromhex("80 05 40 00 00 00 00 00")
    eager_sizes = [29,10,48,33,29,51,12,20,30,113,1]
    assert sum(eager_sizes) == 376 and 120+26+sum(eager_sizes) == 522
    assert 146+sum(eager_sizes[:9]) == 408
    assert 408+97 == 505 and 408+105 == 513
    for start, displacement, target in [(2,88,97),(48,42,97),(55,43,105),(76,22,105),(89,9,105)]:
        assert start+7+displacement == target
    assert 5//2 == 2 and 5 <= 2*4 and 7 <= 1*10
    assert 511 & 255 == 255
    assert 17920*16 == 286720 and 286720//4096 == 70
    assert max(81920, 1024+24) == 81920
    assert max(81920, 81920+16) == 81936
    # C12–C15 paper fixtures: metadata/storage coordinates, not an evaluator.
    assert 9*8 == 72 and -8*(4+1) == -40
    assert -8*(3+1)+2*8 == -16
    assert 1+2*2 == 5 and (1+2)*2 == 6
    assert (9-3)-2 == 4 and 9-(3-2) == 8
    assert (2*65536)+1 == 131073 and 2*65536 == 131072
    assert 1+3 == 4 and (-32+3*8) == -8
    assert 31+1 == 32 and 32+3 > 32
    assert len(b"1 + 2") == 5 and 500+len(b"1 + 2") == 505
    assert 1+2 == 3 and bool(1 and (9//3)) == True
    print("PASS: canonical tri.c text and bounded C-unit paper calculations through expression and declaration fixtures")


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
                              (15, "dictionary-and-token-input"), (16, "native-colon-compiler"),
                              (17, "inline-branch-operands"), (18, "decimal-parser-and-repl")]:
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


def check_reader_reference():
    reference = (ROOT / "seed-forth/REFERENCE.md").read_text()
    cards = []
    for line in reference.splitlines():
        word = re.match(r"^\| (\d+) `([^`]+)`", line)
        body = re.search(r"\[`0x([0-9A-Fa-f]+)`\]\[([^\]]+)\]", line)
        if word and body:
            cards.append((int(word.group(1)), word.group(2), int(body.group(1), 16)))
    with (ROOT / "seed-forth/source-audit.csv").open(newline="") as stream:
        headers = [row for row in csv.DictReader(stream) if row["kind"] == "dictionary_header"]
    assert len(cards) == len(headers) == 32
    for number, (card, header) in enumerate(zip(cards, headers), 1):
        assert card == (number, header["section"].split(":", 1)[1], int(header["end_offset_exclusive"], 16))
    print("PASS: 32 primitive reference names and body offsets match the source ledger")


def check_capstone():
    def entry(name, start, link, value):
        encoded = name.encode("ascii")
        header = link.to_bytes(8, "little") + bytes([0, len(encoded)]) + encoded
        at = start+len(header)
        lit_call = bytes([0xE8]) + (0x4005A0-(at+5)).to_bytes(4, "little", signed=True)
        add_call = bytes([0xE8]) + (0x4001B7-(at+13+5)).to_bytes(4, "little", signed=True)
        return header + lit_call + value.to_bytes(8, "little") + add_call + bytes([0xC3])
    expected = [entry("inc", 0x401000, 0x400617, 1),
                entry("inc", 0x401000, 0x400617, 1),
                entry("up", 0x401000, 0x400617, 2),
                entry("inc", 0x401080, 0x400617, 1),
                entry("bump", 0x401020, 0x401000, 7)]
    found = []
    for relative in ["chapters/19-audit-synthesis-and-capstone.md", "practice/19-solutions.md"]:
        text = (ROOT / "seed-forth" / relative).read_text()
        for language, block in all_fenced_blocks(text):
            if language in {"text", ""} and re.fullmatch(r"(?:[0-9A-Fa-f]{2}\s*)+", block.strip()):
                found.append(bytes.fromhex(block))
    assert found == expected, "A displayed complete capstone entry differs from independent byte construction"
    print("PASS: 5 complete displayed capstone entries match independent header/CALL/literal construction")


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
    def decimal(token):
        value = 0
        if not token:
            return 0, 0
        for byte in token:
            if not 48 <= byte <= 57:
                return 0, 0
            value = (value*10 + byte-48) & u
        return value, u
    assert decimal(b"407") == (407, u)
    assert decimal(b"") == (0, 0) and decimal(b"1a") == (0, 0)
    assert decimal(str(m).encode()) == (0, u)
    assert decimal(str(u).encode()) == (u, u)
    assert decimal(b"0007") == (7, u)
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
    check_c_excerpts(args.source_root)
    check_c_source_map(args.source_root)
    check_preprocessor_regions(args.source_root)
    check_emission_map(args.source_root)
    check_parser_map(args.source_root)
    check_c_models(args.source_root)
    check_models()
    check_audit_partition(args.source_root)
    check_audit_listings(args.source_root)
    check_reader_reference()
    check_capstone()
    print("These checks do not execute Forth, compile C, run a bootstrap, or establish reader learning.")


if __name__ == "__main__":
    main()
