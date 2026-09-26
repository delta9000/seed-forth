#!/usr/bin/env python3
"""tools/check-tryit.py — run the book's "Try it" shell examples.

tangle.sh proves the book's `file=` code blocks are byte-identical to
source, and check-numbers.py proves its prose numbers — but the ```sh
blocks a reader is told to paste into a terminal had no oracle.  Two real
bugs slipped through that way: a comment written as `echo '...' \\ true ->
'1'` (the shell turned `-> '1'` into a redirect and littered the reader's
directory with stray files), and an exercise whose hex literals `[lit]`
silently parsed as 0.  This script executes those blocks.

What is run
  Every ```sh / ```bash / untagged fenced block in book/*.md whose commands
  pipe into `./seed-forth` (`| ./seed-forth`, `| timeout N ./seed-forth`).
  Each block runs under `bash` in a fresh temporary directory holding
  *copies* (never symlinks — a stray `>` must not reach the repo) of
  `seed-forth`, `000-seed.hex0` and every top-level `*.fth`.  `./build.sh`
  is a no-op (the tool never rebuilds or overwrites ./seed-forth).  When
  `unshare -rm` works, the block also gets a private /tmp, so examples that
  write /tmp/cc-out neither see nor clobber the real one; without it, such
  blocks are SKIPped.

A block FAILs if
  * any command writes to stderr, a command is not found / not executable
    (rc 126/127), or a command that runs ./seed-forth exits non-zero;
  * the temp dir gains, loses or changes a file (stray redirects);
  * it exceeds the timeout (--timeout, default 30 s) — unless the block or
    the paragraph after it says it loops ("Ctrl-C", "forever", "infinite
    loop", "no way out", "kills it"), or a `<!-- tryit: loops -->` marker
    sits right above the fence; then a timeout is a pass;
  * an unambiguous expected output does not match.  Only these shapes are
    asserted (anything else just has to run cleanly):
      - after the block, in the next paragraph: "Expected output: `X`",
        "Expected: `X`", "The expected output is `X`", "The seed prints
        `X`", "The seed should print `X`" (whole block's stdout == X), and
        "Expected output ends with `X`" (stdout ends with X);
      - comments in the block, attached to the command they follow (or
        trail): `# prints "X"`, `# prints 'X'`, `# prints: X`,
        `# expect: X`, `# -> X`, `... -> "X"`.  A comment group with two
        different candidates is ambiguous and ignored;
      - `-> "X"` comments on the lines *inside* one compound command
        (e.g. several `echo`s in `{ ...; } | ./seed-forth`) are concatenated
        only when every line of it that contains `emit` carries one.
    Comparison ignores trailing newlines; `\\n` in an expectation is a
    newline.

A block is SKIPped (with the reason) if it needs gforth, gcc, make, git,
vendor/ or tests/ checkouts, a missing host tool (objdump, readelf, xxd,
file), or carries a `<!-- tryit: skip -->` marker above the fence.

Usage:
    tools/check-tryit.py [--verbose] [--timeout SECS] [book/NN-foo.md ...]

Exit status is non-zero iff any block FAILs.
"""

import glob
import hashlib
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOOK = os.path.join(ROOT, "book")

FENCE_RE = re.compile(r"^\s*(```+|~~~+)\s*([A-Za-z0-9_+-]*)")
SHELL_TAGS = {"sh", "bash", "shell", ""}
PIPE_SEED_RE = re.compile(r"\|\s*(?:timeout\s+\S+\s+)?\./seed-forth\b")
SEED_RUN_RE = re.compile(r"\./seed-forth\b")
BUILD_RE = re.compile(r"(^|[\s;&|(])\./build\.sh\b")
LOOP_RE = re.compile(r"Ctrl-C|\bforever\b|infinite loop|no way out|\bkills it\b", re.I)
MARK_RE = re.compile(r"<!--\s*tryit:\s*(skip|loops)\s*-->")

NEEDS = [
    (re.compile(r"\bgforth\b"), "needs gforth"),
    (re.compile(r"\bgcc\b"), "needs gcc"),
    (re.compile(r"(^|[\s;&|])make\b"), "needs make"),
    (re.compile(r"\bgit\s"), "needs git"),
    (re.compile(r"\bvendor/"), "needs vendor/ checkouts"),
    (re.compile(r"(^|[\s;&|])\.?/?tests/"), "needs tests/ scripts"),
    (re.compile(r"(^|[\s;&|])\./test\.sh\b"), "runs the full test suite"),
]
HOST_TOOLS = ["objdump", "readelf", "xxd", "file", "unshare"]

# after-block (paragraph) expectations
PARA_EQ_RE = re.compile(
    r"(?:\bExpected(?:\s+output)?|\bThe expected output is|\bThe seed (?:should )?prints?)"
    r"\s*:?\s*`([^`]+)`")
PARA_END_RE = re.compile(r"\bExpected output ends with\s+`([^`]+)`")

# in-block comment expectations
Q = r"(?:\"((?:[^\"\\]|\\.)*)\"|'((?:[^'\\]|\\.)*)')"
C_PRINTS_Q = re.compile(r"\bprints?\s*:?\s*" + Q, re.I)
C_PRINTS_COLON = re.compile(r"\bprints:\s+([^\s\"']\S*)", re.I)
C_EXPECT = re.compile(r"^\s*(?:expect|expected)\s*:\s*(?:" + Q + r"|(\S+))\s*$", re.I)
C_ARROW_LEAD = re.compile(r"^\s*->\s*(?:" + Q + r"|(\S+))\s*$")
C_ARROW_Q = re.compile(r"->\s*" + Q)


def unesc(s):
    return s.replace("\\n", "\n").replace("\\t", "\t").replace('\\"', '"').replace("\\'", "'")


def split_comment(line):
    """Split `code  # comment` at the first unquoted ` #`; return (code, comment)."""
    sq = dq = False
    for i, ch in enumerate(line):
        if ch == "'" and not dq:
            sq = not sq
        elif ch == '"' and not sq:
            dq = not dq
        elif ch == "#" and not sq and not dq and (i == 0 or line[i - 1].isspace()):
            return line[:i], line[i + 1:]
    return line, ""


def comment_expectations(comment):
    """Return the set of expected-output strings a comment states."""
    vals = []
    for m in C_PRINTS_Q.finditer(comment):
        vals.append(m.group(1) if m.group(1) is not None else m.group(2))
    for m in C_PRINTS_COLON.finditer(comment):
        vals.append(m.group(1))
    for rx in (C_EXPECT, C_ARROW_LEAD):
        m = rx.match(comment)
        if m:
            vals.append(next(g for g in m.groups() if g is not None))
    if not vals:
        for m in C_ARROW_Q.finditer(comment):
            vals.append(m.group(1) if m.group(1) is not None else m.group(2))
    return {unesc(v) for v in vals}


def parses(text):
    r = subprocess.run(["bash", "-n"], input=text, capture_output=True, text=True)
    return r.returncode == 0 and not r.stderr.strip()


class Chunk:
    def __init__(self, lines):
        self.lines = lines          # code lines (with inline comments)
        self.tail = []              # trailing comment text (last line + following # lines)
        self.expect = None

    @property
    def text(self):
        return "\n".join(self.lines)


def chunk_block(body):
    """Split a block into top-level commands, each with its trailing comments."""
    chunks, cur, done = [], [], []
    for line in body:
        s = line.strip()
        if not cur:
            if not s:
                continue
            if s.startswith("#"):
                if chunks:
                    chunks[-1].tail.append(s[1:])
                continue
        cur.append(line)
        if line.rstrip().endswith("\\"):
            continue
        if parses("\n".join(done + cur) + "\n"):
            c = Chunk(cur)
            c.tail.append(split_comment(cur[-1])[1])
            chunks.append(c)
            done += cur
            cur = []
    if cur:
        chunks.append(Chunk(cur))   # unparseable remainder: let bash report it
    for c in chunks:
        vals = set()
        for t in c.tail:
            vals |= comment_expectations(t)
        if len(vals) == 1:
            c.expect = vals.pop()
        elif not vals and len(c.lines) > 1:
            parts, ok = [], True
            for ln in c.lines:
                code, com = split_comment(ln)
                if "emit" in code:
                    v = [m.group(1) if m.group(1) is not None else m.group(2)
                         for m in C_ARROW_Q.finditer(com)]
                    if len(v) != 1:
                        ok = False
                        break
                    parts.append(unesc(v[0]))
            if ok and parts:
                c.expect = "".join(parts)
    return chunks


def find_blocks(md):
    lines = open(md, encoding="utf-8").read().split("\n")
    out, i = [], 0
    while i < len(lines):
        m = FENCE_RE.match(lines[i])
        if not m:
            i += 1
            continue
        fence, tag = m.group(1), m.group(2).lower()
        j = i + 1
        while j < len(lines) and not lines[j].strip().startswith(fence[:3]):
            j += 1
        body = lines[i + 1:j]
        if tag in SHELL_TAGS and PIPE_SEED_RE.search("\n".join(body)):
            k = j + 1
            while k < len(lines) and not lines[k].strip():
                k += 1
            para = []
            while k < len(lines) and lines[k].strip() and not lines[k].lstrip().startswith(("#", "```", "~~~")):
                para.append(lines[k].strip())
                k += 1
            p = i - 1
            while p >= 0 and not lines[p].strip():
                p -= 1
            marker = MARK_RE.search(lines[p]) if p >= 0 else None
            out.append(dict(line=i + 1, body=body, para=" ".join(para),
                            marker=marker.group(1) if marker else None))
        i = j + 1
    return out


def snapshot(d):
    snap = {}
    for base, dirs, files in os.walk(d):
        for f in files + [x for x in dirs if os.path.islink(os.path.join(base, x))]:
            p = os.path.join(base, f)
            rel = os.path.relpath(p, d)
            try:
                snap[rel] = hashlib.sha256(open(p, "rb").read()).hexdigest()
            except OSError:
                snap[rel] = "?"
    return snap


def can_unshare():
    if not shutil.which("unshare"):
        return False
    with tempfile.TemporaryDirectory() as t:
        r = subprocess.run(["unshare", "-rm", "sh", "-c", f"mount --bind {t} /tmp"],
                           capture_output=True)
        return r.returncode == 0


def build_script(chunks, outdir_rel):
    parts = []   # cwd is already the work dir (set by the caller)
    for n, c in enumerate(chunks):
        code = BUILD_RE.sub(lambda m: m.group(1) + "true", c.text)
        parts.append("{\n" + code + "\n} > %s/%d.out 2> %s/%d.err" % (outdir_rel, n, outdir_rel, n))
        parts.append("__rc=$?; echo $__rc > %s/%d.rc; (exit $__rc)" % (outdir_rel, n))
    return "\n".join(parts) + "\n"


def run_block(md, blk, timeout, private_tmp, verbose):
    shown = os.path.relpath(md, ROOT) if md.startswith(ROOT + os.sep) else md
    rel = f"{shown}:{blk['line']}"
    text = "\n".join(blk["body"])
    if blk["marker"] == "skip":
        return "SKIP", rel, "tryit: skip marker", ""
    code_only = "\n".join(split_comment(ln)[0] for ln in blk["body"])
    for rx, why in NEEDS:
        if rx.search(code_only):
            return "SKIP", rel, why, ""
    for tool in HOST_TOOLS[:-1]:
        if re.search(r"(^|[\s;&|])%s\b" % tool, code_only) and not shutil.which(tool):
            return "SKIP", rel, f"missing host tool: {tool}", ""
    if "/tmp/" in code_only and not private_tmp:
        return "SKIP", rel, "writes /tmp and `unshare -rm` is unavailable", ""

    chunks = chunk_block(blk["body"])
    loops = blk["marker"] == "loops" or bool(LOOP_RE.search(text + " " + blk["para"]))
    para_eq = PARA_EQ_RE.findall(blk["para"])
    para_end = PARA_END_RE.findall(blk["para"])

    root = tempfile.mkdtemp(prefix="tryit-")
    try:
        work, outd, ptmp = (os.path.join(root, x) for x in ("work", "out", "tmp"))
        for d in (work, outd, ptmp):
            os.mkdir(d)
        for f in ["seed-forth", "000-seed.hex0"] + [os.path.basename(p) for p in glob.glob(os.path.join(ROOT, "*.fth"))]:
            src = os.path.join(ROOT, f)
            if os.path.exists(src):
                shutil.copy2(src, os.path.join(work, f))
        before = snapshot(work)
        script = os.path.join(root, "block.sh")
        open(script, "w").write(build_script(chunks, "../out"))
        env = dict(os.environ, TRYIT_WORK=work, LC_ALL="C")
        if private_tmp:
            cmd = ["unshare", "-rm", "bash", "-c",
                   'cd "$TRYIT_WORK" && mount --bind "$1" /tmp && exec bash --noprofile --norc ../block.sh',
                   "tryit", ptmp]
        else:
            cmd = ["bash", "--noprofile", "--norc", script]
        timed_out = False
        proc = subprocess.Popen(cmd, cwd=work, env=env, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                start_new_session=True)
        try:
            top_out, top_err = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(proc.pid, signal.SIGKILL)
            top_out, top_err = proc.communicate()

        problems, detail = [], []
        outs = []
        for n, c in enumerate(chunks):
            def rd(ext):
                p = os.path.join(outd, f"{n}.{ext}")
                return open(p, "rb").read().decode("latin-1") if os.path.exists(p) else None
            out, err, rc = rd("out"), rd("err"), rd("rc")
            if out is None:
                break
            outs.append(out)
            first = c.lines[0].strip()
            detail.append(f"  $ {first}{' ...' if len(c.lines) > 1 else ''}\n"
                          f"    rc={rc.strip() if rc else '?'} stdout={out!r} stderr={err!r}")
            if rc is None:
                break           # still running when the timeout hit
            rcv = int(rc.strip() or 0)
            if err.strip():
                problems.append(f"stderr from `{first}`: {err.strip().splitlines()[0]}")
            if rcv in (126, 127):
                problems.append(f"`{first}`: command not found/not executable (rc {rcv})")
            elif rcv != 0 and SEED_RUN_RE.search(c.text):
                problems.append(f"`{first}` exited {rcv}")
            if c.expect is not None and out.rstrip("\n") != c.expect.rstrip("\n"):
                problems.append(f"`{first}`: expected {c.expect!r}, got {out!r}")
        if top_err.strip():
            problems.append("harness stderr: " + top_err.decode("latin-1").strip().splitlines()[0])
        if timed_out:
            if not loops:
                problems.append(f"timed out after {timeout}s")
        else:
            whole = "".join(outs)
            for x in para_eq:
                if whole.rstrip("\n") != unesc(x):
                    problems.append(f"paragraph says output is {x!r}; got {whole!r}")
            for x in para_end:
                if not whole.rstrip("\n").endswith(unesc(x)):
                    problems.append(f"paragraph says output ends with {x!r}; got {whole[-80:]!r}")
        after = snapshot(work)
        for f in sorted(set(before) | set(after)):
            if f not in before:
                problems.append(f"stray file created: {f!r}")
            elif f not in after:
                problems.append(f"file removed: {f!r}")
            elif before[f] != after[f]:
                problems.append(f"file modified: {f!r}")

        nexp = sum(c.expect is not None for c in chunks) + len(para_eq) + len(para_end)
        if problems:
            return "FAIL", rel, "; ".join(problems), "\n".join(detail)
        note = f"{nexp} output check{'s' if nexp != 1 else ''}"
        if timed_out:
            note += ", looped until timeout as documented"
        return "OK", rel, note, ""
    finally:
        shutil.rmtree(root, ignore_errors=True)


def main(argv):
    verbose = "--verbose" in argv or "-v" in argv
    timeout = 30
    files = []
    it = iter(argv)
    for a in it:
        if a == "--timeout":
            timeout = float(next(it))
        elif a in ("--verbose", "-v"):
            pass
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            files.append(os.path.abspath(a))
    if not os.path.exists(os.path.join(ROOT, "seed-forth")):
        print("check-tryit: ./seed-forth not built — run ./build.sh first")
        return 1
    private_tmp = can_unshare()
    counts = {"OK": 0, "SKIP": 0, "FAIL": 0}
    for md in files or sorted(glob.glob(os.path.join(BOOK, "*.md"))):
        for blk in find_blocks(md):
            status, rel, note, detail = run_block(md, blk, timeout, private_tmp, verbose)
            counts[status] += 1
            print(f"{status:<5} {rel}  {note}")
            if status == "FAIL" and verbose and detail:
                print(detail)
    tmpnote = "" if private_tmp else " (no private /tmp: /tmp-writing blocks skipped)"
    print(f"check-tryit: {counts['OK']} OK, {counts['SKIP']} SKIP, {counts['FAIL']} FAIL{tmpnote}")
    return 1 if counts["FAIL"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
