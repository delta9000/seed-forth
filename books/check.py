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
    '141-archive.fth': 'c4e9091af15b787c6385b1a01127f537dcf0dcb3',
    'runtime/gcc-seed/startup.c': '3cd5b0d45a64fa5b3a711496ba0e06802342fbcf',
    'runtime/gcc-seed/environment.c': '55ea94386905ae2b5e2d92aad18d54cdb5a3201c',
    'gcc-direct/driver.py': '5db06a189474f8e90e46040e4409f093193f4e12',
    'gcc-direct/lexers.py': 'b238798ed0b421548f940ee00045d31481d3f4e6',
    'gcc-direct/stage-c.py': 'dc3152b6ad22c7c8994d8b702db76be88c069fe0',
    'gcc-direct/stage-d.py': 'aa21424781eff6eaaae944bd04051cb75edcc386',
    'k1/README.md': 'd02441ae729e4089efed80b2a603b3c96ce9250f',
    'tests/pnut/sf-pnut-check.sh': '067f2f4bc367276b7ecf04092d9e170ecc4dc919',
    'tools/amd64.recipe': 'fd525c5e478266aff55e3e102af34aea0567349d',
    'tools/gcc-direct-cc.py': '9fd1d063b2984d979cde7c89b75e9b557b9b5a07',
    'tools/tcc.recipe': '9efffbd59dcc223e13ccc35ad73004a5d3d5bac7',
    '130-asm.fth': 'f1aec439017467a377af636b3b619e7cbb72188a',
    'book/33-the-assembler.md': '6e3d80fcbcd1247c59eb627d361445cd40d9e2d8',
    'tests/asm/die-gates.sh': '2d952e9c417a579d431bd68e68298d77d28dc612',
    'tests/asm/exit42-check.sh': '04da9dcec07b3a030c1429ef07c4d2a8fa3f3b97',
    'tests/asm/exit42.M1': '4e13975caa7c6f4283d23594ee6cfffe00f37515',
    'tests/asm/jump42-check.sh': '70aa18447ed079f6c2652b3d31d088ee9c88e05f',
    'tests/asm/jump42.hex2': '91750f0cd818a6ca8a880feca1aad75f31ed8d19',
    'tests/asm/m1-jump42-check.sh': 'be2c7cbbf8b8440739c895d75922ab017edba2d6',
    'tests/asm/m1-jump42.M1': '2acbec7a76922bd82bdeacda6665dc0450cdd7f7',
    'tests/asm/m2planet-check.sh': '76bc61c54bf54695fa3315e90dd0692380f1ce54',
    'tests/asm/mescc-tools-check.sh': '6385162dd729981496061d524c06bc8ae23b0820',
    'README.md': 'b4a167739d8c47dc2338cfde5f915bb9aca566f7',
    'REPRODUCIBLE.md': '5bfd46d7bbdc90e375fe378da30cae3fa617af32',
    'book/00-prologue.md': '91b3ee2a06373f3d1b6234d9abed0a6c0008184b',
    'book/32-main-and-bootstrap-chain.md': 'dc0666d9b8da3e61ccdd953309dfe371f3aa719e',
    'book/A3-reproducibility-chain.md': 'e044d26829ac588354cdaaf7b3021ea59b0d4b4b',
    'bootstrap.sh': '14986352c5ee2d24746dabf038099d9e430fc11a',
    'build.sh': '47b9c426aaa17bed389119b89f313a7107b9d15c',
    'tests/cc/bootstrap-chain.sh': '1cf990022c967b655e40fcf596c1550c3d79b3f7',
    'tests/cc/build-gcc-refs.sh': '01b4b996cc1a923b010049b569880d4a3cfb4be4',
    'tests/cc/build-m2planet-monolith.sh': 'a6adc796e998b0d5802051e9d0673b43bf33b85f',
    'tests/cc/cc_globals.h': '0633b632d001175429a8217653a0e1b3b89300b7',
    'tests/cc/stage-a-check.sh': '5a73cde4d041f0fb9058f40147f329c363d26236',
    'verify.sh': 'f66ba07d4b9ab9fb884b1952b68204bf8ae3b673',
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
        # Inline code such as `m[2][3]` is not a reference link.
        for used in re.findall(r"\[[^\]]+\]\[([^\]]+)\]", re.sub(r"`[^`\n]*`", "", prose)):
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
        exercise_count = {5: 6, 6: 7, 7: 7, 8: 8, 9: 8, 10: 9, 11: 8, 12: 8, 13: 7, 14: 10, 15: 7, 16: 8, 17: 8, 18: 9, 19: 7, 20: 8, 21: 10, 22: 12, 23: 10, 24: 10}.get(number, 5)
        c_pairs += exercise_count
        expected = {f"C{number}-{i:02}" for i in range(1, exercise_count+1)}
        for file in [chapter, solution]:
            found = set(re.findall(rf"\bC{number}-\d{{2}}\b", file.read_text()))
            assert found == expected, (file, found)
    g_pairs = 0
    for chapter in sorted((ROOT / "gcc-toolchain/chapters").glob("[0-9][0-9]-*.md")):
        number = int(chapter.name[:2])
        counts = {1: 7}
        assert number in counts, f"Declare exercise coverage for toolchain chapter {number}"
        expected = {f"G{number}-{i:02}" for i in range(1, counts[number]+1)}
        solution = ROOT / f"gcc-toolchain/practice/{number:02}-solutions.md"
        for file in [chapter, solution]:
            assert file.is_file(), f"Missing toolchain companion: {file}"
            found = set(re.findall(rf"\bG{number}-\d{{2}}\b", file.read_text()))
            assert found == expected, (file, found)
        g_pairs += counts[number]
    entrance_ids = {"H1-01", "H1-02", "H2-01", "H2-02"}
    for file in [ROOT / "FIRST-RESULTS.md", ROOT / "practice/first-results-solutions.md"]:
        found = set(re.findall(r"\bH[12]-\d{2}\b", file.read_text()))
        assert found == entrance_ids, (file, found)
    pairs = 95 + c_pairs + g_pairs
    print(f"PASS: {len(files)} Markdown files; {checked_links} links; {pairs} chapter exercise ID pairs; {len(entrance_ids)} entrance pairs")


def pinned_source_path(source_root, name):
    """Keep historical README evidence separate from the live reader gateway."""
    if name == "README.md":
        path = (ROOT / "source-edition/README-7d7e199.md.txt").resolve()
        assert path.is_relative_to(ROOT), "README evidence escaped the manuscript tree"
    else:
        path = (source_root / name).resolve()
        assert path.is_relative_to(source_root.resolve()), name
    assert path.is_file(), f"Missing pinned source: {name}"
    return path


def check_pinned_source_links(source_root):
    """Check source locators against the pinned files, without network or execution."""
    prefix = f"https://github.com/delta9000/seed-forth/blob/{REV}/"
    pattern = re.compile(re.escape(prefix) + r"([^\s)#]+)#L(\d+)(?:-L(\d+))?")
    lengths, checked = {}, 0
    for path in ROOT.rglob("*.md"):
        prose = "\n".join(visible_lines(path.read_text()))
        for match in pattern.finditer(prose):
            name = unquote(match.group(1))
            source = pinned_source_path(source_root, name)
            if name not in lengths:
                lengths[name] = len(source.read_text().splitlines())
            start = int(match.group(2))
            end = int(match.group(3) or start)
            assert 1 <= start <= end <= lengths[name], (path, name, start, end, lengths[name])
            checked += 1
    print(f"PASS: {checked} pinned-source line locators stay within their source files")


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



def check_narrative_map(map_path=None):
    """Ensure the short reading route preserves every full-depth unit."""
    units = {}
    for line in (ROOT / "COVERAGE.md").read_text().splitlines():
        if re.match(r"^\| [SCGK]\d{2} —", line):
            fields = [field.strip() for field in line.split("|")[1:-1]]
            unit = re.search(r"[SCGK]\d{2}", fields[0]).group()
            units[unit] = fields[-1]
    with (map_path or ROOT / "narrative-map.csv").open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    mapped = [row["unit"] for row in rows]
    assert len(mapped) == len(set(mapped)), "Duplicate narrative-map unit"
    assert set(mapped) == set(units), "Narrative map must retain every declared unit"
    allowed_roles = {"orientation", "main_story", "bridge", "audit_depth",
                     "audit_capstone", "optional_route", "replacement_case",
                     "toolchain_capstone", "continuation"}
    allowed_milestones = {"Preview", "H1", "H2", "H3", "H4", "H5",
                          "Audit", "Alternate", "Continuation"}
    for row in rows:
        assert row["manuscript_status"] == units[row["unit"]], row["unit"]
        assert row["first_reading_role"] in allowed_roles, row
        assert set(row["milestones"].split(";")) <= allowed_milestones, row
        for field in ("title", "first_session", "retained_depth", "route_status"):
            assert row[field].strip(), (row["unit"], field)
        if row["manuscript_status"] == "drafted":
            path = (ROOT / row["chapter_path"]).resolve()
            assert path.is_relative_to(ROOT.resolve()) and path.is_file(), row
            assert path.suffix == ".md", row
        else:
            assert not row["chapter_path"], "Planned unit must not imply an existing chapter"
    print(f"PASS: {len(rows)} narrative assignments preserve unit identities, states and chapter paths")


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
        data = pinned_source_path(source_root, name).read_bytes()
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
    # Narrative files can contain historical fragments; use implementation bodies.
    for name in SOURCE_BLOBS:
        if not name.endswith(".fth"):
            continue
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
                 "090-cc-emit.fth", "100-cc-expr.fth", "110-cc-decl.fth",
                 "112-cc-stmt.fth", "114-cc-func.fth", "116-cc-prog.fth", "117-cc-native-program.fth",
                 "118-cc-native-init.fth", "119-cc-native-runtime.fth", "120-cc-main.fth", "130-asm.fth"]:
        expected = set(re.findall(r"^:\s+(\S+)", (source_root/name).read_text(), re.M))
        actual = {word for file, word in seen if file == name}
        assert actual == expected, (name, actual ^ expected)
    print(f"PASS: {len(rows)} compiler/assembler source-map definitions; complete named implementation inventories")


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


def check_control_map(source_root):
    path = ROOT / "c-compiler/control-map.csv"
    if not path.exists():
        return
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    names = ["112-cc-stmt.fth", "114-cc-func.fth", "116-cc-prog.fth", "120-cc-main.fth"]
    expected, sources = {}, {}
    for name in names:
        sources[name] = (source_root/name).read_text().splitlines()
        for number, line in enumerate(sources[name], 1):
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
    declaration_kinds = {"colon", "create", "variable", "constant", "defer"}
    seen, forms, states, counts = set(), set(), {}, {}
    for row in rows:
        name, kind = row["source_path"], row["declaration_kind"]
        start, end = int(row["source_line"]), int(row["source_end_line"])
        assert name in sources and 1 <= start <= end <= len(sources[name]), row
        counts[kind] = counts.get(kind, 0) + 1
        if kind in declaration_kinds:
            key = (name, row["name"])
            assert key not in seen and expected[key] == (start, kind), row
            seen.add(key)
            if kind == "colon":
                words = source_words("\n".join(sources[name][start-1:end]))
                assert definition_end(words) == len(words)-1, row
        else:
            key = (name, start, end, kind)
            assert key not in forms, row
            forms.add(key)
        assert row["source_revision"] == REV
        assert row["source_blob_sha"] == SOURCE_BLOBS[name]
        assert row["source_url"] == f"https://github.com/delta9000/seed-forth/blob/{REV}/{name}#L{start}-L{end}"
        assert row["teaching_unit"] in {"C16", "C17", "C18", "C19"}
        for field in ["state_owner", "semantic_purpose", "teaching_depth", "interface_notes"]:
            assert row[field].strip(), (field, row)
        chapter = (ROOT / "c-compiler" / row["manuscript_path"]).resolve()
        assert chapter.is_relative_to(ROOT) and chapter.is_file(), row
        state = row["coverage_status"]
        assert state in {"taught", "pending-chapter"}, row
        states[state] = states.get(state, 0) + 1
        if state == "taught":
            assert row["teaching_anchor"] in anchors(chapter.read_text()), row
            assert row["teaching_section"].strip(), row
    assert seen == expected.keys() and len(seen) == 160
    assert counts == {"colon": 82, "variable": 32, "create": 40, "constant": 5,
                      "defer": 1, "initialization": 8, "binding": 1, "execution": 1}, counts
    expected_forms = {("112-cc-stmt.fth", n, n, "initialization") for n in [637, 641, 645, 649, 653, 657]}
    expected_forms |= {("112-cc-stmt.fth", 905, 905, "binding"),
                       ("116-cc-prog.fth", 766, 774, "initialization"),
                       ("120-cc-main.fth", 24, 26, "initialization"),
                       ("120-cc-main.fth", 40, 40, "execution")}
    assert forms == expected_forms, forms
    print(f"PASS: {len(seen)} control/function/program declarations and {len(forms)} top-level forms; states {states}")


def check_pipeline_map(source_root):
    path = ROOT / "c-compiler/pipeline-map.csv"
    if not path.exists():
        return
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    expected_lengths = {
        "tests/cc/stage-a-check.sh": 78,
        "tests/cc/build-m2planet-monolith.sh": 106,
        "tests/cc/build-gcc-refs.sh": 50,
        "tools/compiler-layers.sh": 10,
        "build.sh": 29,
    }
    for name, length in expected_lengths.items():
        assert len((source_root/name).read_text().splitlines()) == length, name
    next_line = {name: 1 for name in expected_lengths}
    ids, states = set(), {}
    for row in rows:
        name = row["source_path"]
        assert name in expected_lengths and row["region_id"] not in ids, row
        ids.add(row["region_id"])
        start, end = int(row["start_line"]), int(row["end_line"])
        assert start == next_line[name] and start <= end <= expected_lengths[name], row
        next_line[name] = end+1
        assert row["source_revision"] == REV and row["source_blob_sha"] == SOURCE_BLOBS[name], row
        assert row["source_url"] == f"https://github.com/delta9000/seed-forth/blob/{REV}/{name}#L{start}-L{end}"
        assert row["teaching_unit"] == "C20" and row["evidence_kind"] == "inspected-recipe", row
        for field in ["semantic_purpose", "inputs", "outputs", "state_owner", "exact_action",
                      "acceptance_predicate", "profile_assumptions", "teaching_depth",
                      "run_evidence", "claim_limit"]:
            assert row[field].strip(), (field, row)
        chapter = (ROOT / "c-compiler" / row["manuscript_path"]).resolve()
        assert chapter.is_relative_to(ROOT) and chapter.is_file(), row
        state = row["coverage_status"]
        assert state in {"taught", "partial-prose", "pending-prose"}, row
        states[state] = states.get(state, 0) + 1
        if state == "taught" or row["teaching_anchor"]:
            assert row["teaching_anchor"] in anchors(chapter.read_text()), row
            assert row["teaching_section"].strip(), row
    assert next_line == {name: end+1 for name, end in expected_lengths.items()}
    assert len(rows) == 33
    print(f"PASS: {len(rows)} pipeline regions partition {sum(expected_lengths.values())} lines in five recipes; states {states}")


def check_c_pipeline_models(source_root):
    path = ROOT / "c-compiler/chapters/20-complete-compiler-and-stage-a.md"
    if not path.exists():
        return
    blocks = list(all_fenced_blocks(path.read_text()))
    text_blocks = [block.strip().splitlines() for language, block in blocks if language == "text"]
    layers = sorted(p.name for p in source_root.glob("[0-9][0-9][0-9]-cc-*.fth"))
    assert len(layers) == 30 and "120-cc-main.fth" in layers
    ordered = ["010-lib.fth"] + [name for name in layers if name != "120-cc-main.fth"] + ["120-cc-main.fth"]
    assert ordered in text_blocks and len(ordered) == 31
    # Read shell text as data. These expressions do not execute either helper.
    mono = (source_root / "tests/cc/build-m2planet-monolith.sh").read_text()
    header_line = next(line for line in mono.splitlines() if line.strip().startswith('cat "$M2/cc.h"'))
    headers = re.findall(r'\$M2/([^"\s]+)', header_line)
    c_loop = re.search(r"for f in (.*?); do", mono, re.S).group(1)
    c_files = c_loop.replace("\\\n", " ").split()
    assert len(headers) == 4 and headers in text_blocks
    assert len(c_files) == 9 and c_files in text_blocks
    stage = (source_root / "tests/cc/stage-a-check.sh").read_text()
    comparison = re.search(r"m2_srcs=\((.*?)\)", stage, re.S).group(1).split()
    assert len(comparison) == 11
    arguments = ["--architecture amd64 --expand-includes"] + [f"-f {name}" for name in comparison]
    assert arguments in text_blocks
    assert comparison != c_files and "130-asm.fth" not in ordered
    original_lines = (source_root / "book/00-prologue.md").read_text().splitlines()
    fibonacci_source = "\n".join(original_lines[8:17]).strip()
    assert fibonacci_source.startswith("int fib(") and fibonacci_source.endswith("}")
    assert sum(language == "c" and block.strip() == fibonacci_source for language, block in blocks) == 1
    sequence, a, b = [], 0, 1
    for _ in range(12):
        sequence.append(a)
        a, b = b, a+b
    assert len((" ".join(map(str, sequence))+"\n").encode()) == 29 and sequence[10] == 55
    assert len((" ".join(map(str, sequence[:10]))+"\n").encode()) == 23 and sequence[8] == 21
    # A small model of the displayed harness branches, not a compiler/runtime test.
    def classify(left_status, right_status, comparison_status=None):
        if left_status == right_status and left_status != 0:
            return "both-fail"
        if left_status == right_status == 0 and comparison_status == 0:
            return "identical"
        return "differ"
    cases = [(124, 124, None), (7, 8, None), (0, 0, 1), (0, 0, 0)]
    results = [classify(*case) for case in cases]
    assert [results.count(name) for name in ["identical", "both-fail", "differ"]] == [1, 1, 2]
    assert classify(0, 0, 2) == "differ"  # Comparison error is not necessarily unequal bytes.
    assert int(bool(8) and bool(1)) == 1 and (8 & 1) == 0
    assert b"A\n" != b"A \n" and b"" == b""
    print("PASS: C20's three displayed input lists and Fibonacci source match pinned text; bounded counts/status models agree")


def check_assembler_regions(source_root):
    path = ROOT / "c-compiler/assembler-regions.csv"
    if not path.exists():
        return
    with path.open(newline="") as stream:
        rows = list(csv.DictReader(stream))
    name = "130-asm.fth"
    lines = (source_root/name).read_text().splitlines()
    assert len(lines) == 785
    next_line, seen, initialization_rows = 1, set(), []
    counts, owners = {}, {"C21": 0, "C22": 0}
    for row in rows:
        start, end = int(row["start_line"]), int(row["end_line"])
        assert start == next_line and start <= end <= len(lines), row
        next_line = end+1
        assert row["source_path"] == name and row["source_revision"] == REV
        assert row["source_blob_sha"] == SOURCE_BLOBS[name]
        expected = []
        for line in lines[start-1:end]:
            line = line.split("\\", 1)[0]
            direct = re.match(r"^\s*(:|create|variable)\s+(\S+)", line)
            constant = re.search(r"\bconstant\s+(\S+)", line)
            if direct:
                kind, word = direct.groups()
                kind = "colon" if kind == ":" else kind
            elif constant:
                kind, word = "constant", constant.group(1)
            else:
                continue
            expected.append(word)
            counts[kind] = counts.get(kind, 0)+1
        actual = row["declarations"].split("; ") if row["declarations"] else []
        assert actual == expected and not seen.intersection(actual), row
        seen.update(actual)
        unit = row["primary_unit"]
        assert unit in owners
        owners[unit] += len(actual)
        for word in actual:
            assert word in row["declaration_notes"], (word, row)
        for field in ["phase", "state_owner", "mechanism", "assumptions", "teaching_section"]:
            assert row[field].strip(), (field, row)
        if row["initialization_forms"]:
            initialization_rows.append((start, end, row["initialization_forms"]))
        assert row["manuscript_status"] == "taught", row
        chapter = (ROOT / "c-compiler" / row["manuscript_path"]).resolve()
        assert chapter.is_relative_to(ROOT) and chapter.is_file(), row
        assert row["teaching_anchor"] in anchors(chapter.read_text()), row
        for target in filter(None, row["related_teaching"].split("; ")):
            url = urlsplit(target)
            related = (ROOT / "c-compiler" / url.path).resolve()
            assert related.is_relative_to(ROOT) and related.is_file(), target
            assert url.fragment in anchors(related.read_text()), target
        assert row["source_url"] == f"https://github.com/delta9000/seed-forth/blob/{REV}/{name}#L{start}-L{end}"
    assert next_line == 786 and len(rows) == 42 and len(seen) == 99
    assert counts == {"colon": 50, "variable": 34, "create": 8, "constant": 7}, counts
    assert owners == {"C21": 56, "C22": 43}
    assert len(initialization_rows) == 2
    assert any(start <= 45 <= end and "skip-vm-pages" in text for start, end, text in initialization_rows)
    assert any(start <= 172 <= end and "6291456" in text for start, end, text in initialization_rows)
    print("PASS: 42 assembler regions partition 785 lines and explain 99 declarations plus two initialization forms")


def check_assembler_paper_models():
    path = ROOT / "c-compiler/chapters/21-assembler-input-and-expansion.md"
    if not path.exists():
        return
    text = path.read_text()
    # Fenced presentation ends with a newline; preserve the meaningful final space.
    raw_blocks = re.findall(r"^```text[ \t]*\n(.*?)^```[ \t]*$", text, re.M | re.S)
    displayed = [block[:-1] if block.endswith("\n") else block for block in raw_blocks]
    expanded = ":top EB !end 41 00 :end 90 EB !top "
    assert expanded in displayed and len(expanded.encode("ascii")) == 35
    single = ":top EB !end 41 :end 90 EB !top "
    assert single in displayed and len(single.encode("ascii")) == 32
    assert len(":top EB !end 41 42 00 :end 90 EB !top ") == 38
    assert len(":top EB !end 41 42 43 00 :end 90 EB !top ") == 41
    raw = b'DEFINE jump EB\nDEFINE nop 90\n:top jump !end "A"\n:end nop jump !top\n'
    assert raw[7:11] == b"jump" and raw[12:14] == b"EB"
    assert raw[22:25] == b"nop" and raw[26:28] == b"90"
    # These are supplied field/byte calculations, not an assembler or execution.
    assert 4-(1+1) == 2 and 0-(6+1) == -7
    fragment = bytes([0xEB, 2, 0x41, 0, 0x90, 0xEB, (-7)&255])
    assert fragment == bytes.fromhex("EB 02 41 00 90 EB F9")
    assert ((-8)&255) == 0xF8 and ((-9)&255) == 0xF7
    assert (256&255) == 0 and ((-129)&255) == 0x7F
    assert (0x100000000 & 0xFFFFFFFF) == 0  # Four-byte low-field representation.
    assert 120+7+7+5+7+2 == 148 and 146-(135+4) == 7
    assert (0x600000+120).to_bytes(4, "little") == bytes.fromhex("78 00 60 00")
    assert (148).to_bytes(4, "little") == bytes.fromhex("94 00 00 00")
    assert len(b"/tmp/asm-out\0") == 13
    assert 8192*24 == 196608
    print("PASS: exact displayed assembler expansion, raw slices, and bounded field/header arithmetic agree")


def check_tinycc_paper_models(source_root):
    """C23/C24 image offsets rebuilt from 117/118/119 emission rules (paper only)."""
    c23 = ROOT / "c-compiler/chapters/23-the-direct-tinycc-profile.md"
    c24 = ROOT / "c-compiler/chapters/24-tinycc-initialization-runtime-and-closure.md"
    if not (c23.exists() and c24.exists()):
        return
    text23 = c23.read_text() + (ROOT / "c-compiler/practice/23-solutions.md").read_text()
    text24 = c24.read_text() + (ROOT / "c-compiler/practice/24-solutions.md").read_text()
    runtime = (source_root / "119-cc-native-runtime.fth").read_text()
    counts = [int(k) for k in re.findall(
        r"cc-native-name-\S+\s+\[lit\] \d+ ty-\S+ \[lit\] \d+ \[lit\] (\d) cc-native-primitive", runtime)]
    refused = [int(n) for n in re.findall(
        r"cc-native-name-\S+ \[lit\] (\d+) ty-\S+ \[lit\] \d ty-make cc-native-unavailable", runtime)]
    assert len(counts) == 13 and len(refused) == 3, (counts, refused)
    prefix = len(b"seed-forth bootstrap: unsupported ")
    stub, kernels = 31, sum(23 + 5*k for k in counts)
    refusals = sum(prefix + n + 1 + 41 for n in refused)
    assert (prefix, kernels, refusals) == (34, 434, 249)
    def fields(main_at, dispatcher_at):
        return f"{dispatcher_at}−125={dispatcher_at-125}", f"{main_at}−141={main_at-141}"
    for floatbits in (1, 0):
        main_at = 120 + stub + kernels + refusals*floatbits
        dispatcher, size = main_at + 37, main_at + 38
        for shown in fields(main_at, dispatcher) + (str(size),):
            assert shown in text23, (floatbits, shown)
    # C24: a five-byte jmp before each queued routine, then main, CALLs, data.
    def image(routines, main_size=70):
        at, starts = 834, []
        for size in routines:
            starts.append(at + 5)
            at += 5 + size
        main_at = at
        dispatcher = main_at + main_size
        calls = [f"{start}−{dispatcher+5*(i+1)}=−{dispatcher+5*(i+1)-start}"
                 for i, start in enumerate(starts)]
        return main_at, dispatcher, dispatcher + 5*len(starts) + 1, calls
    scalar, pointer, byte = 10+1+7+1+2+1, 10+1+10+1+3+1, 10+1+7+1+3+1
    main_at, dispatcher, data, calls = image([scalar, pointer])
    assert (main_at, dispatcher, data) == (892, 962, 973)
    assert data + 8 + 8 == 989 and hex(0x400000 + data) == "0x4003cd"
    for shown in calls + list(fields(main_at, dispatcher)) + ["861−839=22", "892−866=26"]:
        assert shown in text24, shown
    main_at, dispatcher, data, calls = image([scalar, pointer, byte])
    assert (main_at, dispatcher, data, data + 17) == (920, 990, 1006, 1023)
    for shown in calls + list(fields(main_at, dispatcher)):
        assert shown in text24, shown
    print("PASS: C23/C24 image offsets and rel32 fields match rules rebuilt from 117/118/119")


def check_c_models(source_root):
    chapter = ROOT / "c-compiler/chapters/01-compiler-entry-and-profile.md"
    if not chapter.exists():
        return
    original = (source_root / "book/21-arena-and-io-buffers.md").read_text()
    original_c = next(block for language, block in all_fenced_blocks(original) if language == "c")
    # The entry lesson may teach a small C slice before showing the full program.
    # Require the exact canonical program once; presentation order is not a contract.
    canonical = [block for language, block in all_fenced_blocks(chapter.read_text())
                 if language == "c" and block == original_c]
    assert len(canonical) == 1, "Expected one exact copy of the pinned recurring tri.c"
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
    # C16–C19: selected control/frame/placement arithmetic, never source execution.
    assert 3-1 == 2 and 1-0 == 1  # saved switch obligations crossed
    assert 10 + 0 + 0 + 12 + 13 == 35 and 0+2+3+4*10 == 45
    assert 1000-(1231+4) == -235
    assert (-235).to_bytes(4, "little", signed=True) == bytes.fromhex("15 FF FF FF")
    assert 16+256 == 272 and 32*8 == 256
    assert round8(1003+24) == 1032 and 1032-(1003+24) == 5
    assert (0x400000+1019).to_bytes(8, "little") == bytes.fromhex("FB 03 40 00 00 00 00 00")
    assert 8*32+8 == 264 and len(b"/tmp/cc-out\0") == 12
    print("PASS: canonical tri.c text and bounded C-unit paper calculations through control and program fixtures")


def check_c_program_capstone():
    path = ROOT / "c-compiler/chapters/19-translation-units-and-process-entry.md"
    if not path.exists():
        return
    text = path.read_text()
    body_rows, entry_rows = {}, {}
    for line in text.splitlines():
        body = re.match(r"^\| (\d+)–(\d+) \| `([0-9A-F ]+)` \|", line)
        entry = re.match(r"^\| (\d+) \| `([0-9A-F ]+)` \|", line)
        if body:
            start, end = int(body[1]), int(body[2])
            data = bytes.fromhex(body[3])
            assert end-start+1 == len(data), line
            assert start not in body_rows, line
            body_rows[start] = data
        elif entry:
            start, data = int(entry[1]), bytes.fromhex(entry[2])
            assert start not in entry_rows, line
            entry_rows[start] = data
    expected_body = {
        522: bytes.fromhex("55 48 89 E5 48 81 EC 00 01 00 00"),
        533: bytes.fromhex("48 C7 C7 07 00 00 00"),
        540: bytes.fromhex("48 89 F8"),
        543: bytes.fromhex("48 89 EC 5D C3"),
        548: bytes.fromhex("48 31 C0"),
        551: bytes.fromhex("48 89 EC 5D C3"),
    }
    expected_entry = {
        120: bytes.fromhex("48 8B 3C 24"),
        124: bytes.fromhex("48 8D 74 24 08"),
        129: bytes.fromhex("E8 00 00 00 00"),
        134: bytes.fromhex("48 89 C7"),
        137: bytes.fromhex("48 C7 C0 3C 00 00 00"),
        144: bytes.fromhex("0F 05"),
    }
    assert body_rows == expected_body and entry_rows == expected_entry
    for rows, start, end in [(body_rows, 522, 556), (entry_rows, 120, 146)]:
        cursor = start
        for offset, data in sorted(rows.items()):
            assert offset == cursor
            cursor += len(data)
        assert cursor == end
    assert (522-134).to_bytes(4, "little") == bytes.fromhex("84 01 00 00")
    assert (556).to_bytes(8, "little") == bytes.fromhex("2C 02 00 00 00 00 00 00")
    assert (81920).to_bytes(8, "little") == bytes.fromhex("00 40 01 00 00 00 00 00")
    assert 522+11+8 == 541  # Empty main retains only prologue and implicit return.
    assert 522+34+34 == 590 and 556-134 == 422  # CR6 helper before main.
    assert (422).to_bytes(4, "little") == bytes.fromhex("A6 01 00 00")
    print("PASS: displayed C19 entry/main bytes match independent paper construction and bounded changed layouts")


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



def check_entrance_paper_models():
    """Bounded arithmetic only; no Forth, generated instructions or linker run."""
    assert 32 * 2 + 1 == 65 and 321 % 256 == 65
    assert 120 + 26 + 376 == 522 and 522 + 34 == 556
    assert 522 - (130 + 4) == 388
    assert 556 + 34 == 590 and 556 - (130 + 4) == 422
    symbol, field, addend = 0x401090, 0x401081, -4
    displacement = symbol + addend - field
    assert displacement == 11 and (field + 4) + displacement == symbol
    assert displacement.to_bytes(4, "little", signed=True).hex(" ").upper() == "0B 00 00 00"
    assert symbol.to_bytes(8, "little").hex(" ").upper() == "90 10 40 00 00 00 00 00"
    assert 0x401150 - (0x401121 + 4) == 43
    assert (43).to_bytes(4, "little").hex(" ").upper() == "2B 00 00 00"
    assert symbol + addend - (field + 0x20) == -21
    assert (symbol + 0x30) + addend - field == 59
    assert (symbol + 0x20) + addend - (field + 0x20) == 11
    assert 0x8000 == 32768 and 0x8000 - 8 == 32760 == 0x7FF8
    assert 0x8008 == 32776 and 0x8008 - 8 == 32768
    assert 32768 % 16 == 0 and 32776 % 16 == 8
    entrance = (ROOT / "FIRST-RESULTS.md").read_text()
    g01 = (ROOT / "gcc-toolchain/chapters/01-a-program-from-two-files.md").read_text()
    c_inputs = [block for language, block in all_fenced_blocks(g01) if language == "c"]
    normalized = [" ".join(block.split()) for block in c_inputs]
    assert normalized[:2] == ["int answer(void) { return 7; }",
                              "extern int answer(void); int main(void) { return answer(); }"]
    forth_inputs = [" ".join(block.split()) for language, block in all_fenced_blocks(entrance)
                    if language == "forth"]
    assert forth_inputs == [": twice-plus-one dup + [lit] 1 + ;",
                            ": twice-plus-one dup + [lit] 1 + ; [lit] 99 [lit] 32 twice-plus-one emit bye"]
    for fragment in ("0B 00 00 00", "90 10 40 00 00 00 00 00", "P=0x401121", "S=0x401150"):
        assert fragment in g01, f"Review changed G01 model: {fragment}"
    for command in ('-nostdinc -c answer.c -o answer.o',
                    '-nostdinc -c main.c -o main.o', 'main.o answer.o -o seven'):
        assert command in g01, f"Review changed G01 command card: {command}"
    print("PASS: bounded H1/H2/G01 paper arithmetic, exact teaching inputs and displayed model fields")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=ROOT.parent)
    args = parser.parse_args()
    check_documents()
    check_coverage()
    check_prerequisites()
    check_narrative_map()
    check_sources(args.source_root)
    check_pinned_source_links(args.source_root)
    check_c_excerpts(args.source_root)
    check_c_source_map(args.source_root)
    check_preprocessor_regions(args.source_root)
    check_emission_map(args.source_root)
    check_parser_map(args.source_root)
    check_control_map(args.source_root)
    check_pipeline_map(args.source_root)
    check_assembler_regions(args.source_root)
    check_c_models(args.source_root)
    check_c_program_capstone()
    check_c_pipeline_models(args.source_root)
    check_assembler_paper_models()
    check_tinycc_paper_models(args.source_root)
    check_entrance_paper_models()
    check_models()
    check_audit_partition(args.source_root)
    check_audit_listings(args.source_root)
    check_reader_reference()
    check_capstone()
    print("These checks do not execute Forth, compile C, run a bootstrap, or establish reader learning.")


if __name__ == "__main__":
    main()
