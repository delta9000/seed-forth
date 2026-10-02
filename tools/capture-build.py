#!/usr/bin/env python3
"""Authoring tool, never run by the bootstrap: turn one host build of a
package into a runner recipe that needs no shell, make or host utility.

  capture-build.py NAME TARBALL --cc TCC [--configure ARGS] [--make ARGS]
                   [--install SRC=DST ...] [--keep-fixture REGEX ...]

It unpacks TARBALL, runs the package's own ./configure and make on the host
with CC=TCC (tcc-musl), AR="TCC -ar", RANLIB=true, and records the make run
with strace.  It then writes ladder/NAME/:

  recipe     runner commands, run inside the unpacked tree with CC, P, T, L
             and SRC set: copy each fixture into place, then replay in order
             every execve of TCC, of TCC -ar, and of a program the build
             itself made (cwd included), then copy the --install files
             into P.  mv by make's shell becomes a runner rename.
  fixtures/  the files a replayed command reads that the tarball does not
             provide as-is: what ./configure wrote (config.h ...) and what
             make's shell steps wrote (sed, echo, cat > file ...).  These
             are host-made text; review them like patches.

The replay is checked where it runs: the recipe's outputs are hashed and
compared with the host build's (HASHES in the same directory).
"""
import argparse, hashlib, os, re, shlex, shutil, subprocess, sys, tarfile, tempfile
from pathlib import Path
from ladder_fixture_copies import fixture_copies

ROOT = Path(__file__).resolve().parents[1]
ap = argparse.ArgumentParser()
ap.add_argument("name")
ap.add_argument("tarball")
ap.add_argument("--cc", required=True)
ap.add_argument("--configure", default="")
ap.add_argument("--make", default="")
ap.add_argument("--install", action="append", default=[])
ap.add_argument("--install-dir", action="append", default=[],
                help="SRCDIR=DSTDIR: every ELF the build made directly in SRCDIR")
ap.add_argument("--keep", default=None, help="keep the work directory here")
args = ap.parse_args()

work = Path(args.keep or tempfile.mkdtemp(prefix="capture-"))
if work.exists():
    shutil.rmtree(work)
work.mkdir(parents=True)
with tarfile.open(args.tarball) as t:
    t.extractall(work, filter="tar")
top = [p for p in work.iterdir()]
assert len(top) == 1, top
src = top[0]
orig = {str(p.relative_to(src)): p.read_bytes() for p in src.rglob("*") if p.is_file()}
orig_regular = {str(p.relative_to(src)) for p in src.rglob("*")
                if p.is_file() and not p.is_symlink()}

env = dict(os.environ, CC=args.cc, AR=f"{args.cc} -ar", RANLIB="true", CFLAGS="-O2",
           LC_ALL="C", SOURCE_DATE_EPOCH="0")
if args.configure is not None:
    subprocess.run(f"./configure {args.configure}", shell=True, cwd=src, env=env,
                   check=True, stdout=open(work / "configure.log", "w"),
                   stderr=subprocess.STDOUT)
trace = work / "make.trace"
subprocess.run(["strace", "-f", "-qq", "-s", "65535", "-o", str(trace), "-e",
                "trace=execve,chdir,fchdir,clone,clone3,fork,vfork,open,openat,"
                "rename,renameat,renameat2,dup2,dup3,close,fcntl,pipe,pipe2,mkdir,mkdirat"] + ["make"] + shlex.split(args.make),
               cwd=src, env=env, check=True, stdout=open(work / "make.log", "w"),
               stderr=subprocess.STDOUT)

# ---- analyse the trace -------------------------------------------------
cc = os.path.realpath(args.cc)
cwd = {}
exe = {}
first = None
events = []                     # ("exec", cwd, argv) | ("mv", cwd, a, b)
writers = {}                    # absolute path -> "replay" | "other"
reads = set()                   # absolute paths opened for reading by replayed programs
pending = {}
fds = {}                        # pid -> {fd: (path, append)}
line_re = re.compile(r"^(\d+)\s+(.*)$")


def absol(c, p):
    return os.path.normpath(p if p.startswith("/") else os.path.join(c, p))


def built(path):
    """A program the build itself made: an ELF file under the source tree
    that the tarball did not contain (scripts from the tarball need a shell)."""
    if not path.startswith(str(src) + "/") or os.path.relpath(path, src) in orig:
        return False
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def strings(s):
    return [bytes(x, "latin1").decode("unicode_escape").encode("latin1").decode("utf-8", "surrogateescape")
            for x in re.findall(r'"((?:[^"\\]|\\.)*)"', s)]


for raw in open(trace, errors="surrogateescape"):
    m = line_re.match(raw.rstrip("\n"))
    if not m:
        continue
    pid, rest = m.groups()
    if first is None:
        first = pid
        cwd[pid] = str(src)
        exe[pid] = "make"
    if "<unfinished ...>" in rest:
        pending[pid] = rest.split("<unfinished")[0]
        continue
    r2 = re.match(r"<\.\.\. (\w+) resumed>(.*)", rest)
    if r2:
        rest = pending.pop(pid, r2.group(1) + "(") + r2.group(2)
    call = re.match(r"(\w+)\((.*)\)\s+=\s+(-?\d+|\?)", rest)
    if not call:
        continue
    name, a, ret = call.groups()
    c = cwd.get(pid, str(src))
    if name in ("clone", "clone3", "fork", "vfork") and ret.lstrip("-").isdigit() and int(ret) > 0:
        cwd[ret] = c
        exe[ret] = exe.get(pid)
        fds[ret] = dict(fds.get(pid, {}))
    elif name in ("dup2", "dup3") and not ret.startswith("-"):
        old = int(a.split(",")[0])
        t = fds.setdefault(pid, {})
        if old in t:
            t[int(ret)] = t[old]
        else:
            t.pop(int(ret), None)
    elif name == "fcntl" and "F_DUPFD" in a and not ret.startswith("-"):
        old = int(a.split(",")[0])
        t = fds.setdefault(pid, {})
        if old in t:
            t[int(ret)] = t[old]
    elif name in ("mkdir", "mkdirat") and ret == "0":
        p = absol(c, strings(a)[0])
        if p.startswith(str(src) + "/"):
            events.append(("mkdir", c, p))
    elif name in ("pipe", "pipe2") and ret == "0":
        for fd in re.findall(r"\d+", a.split("]")[0]):
            fds.setdefault(pid, {})[int(fd)] = ("|pipe", False)
    elif name == "close" and ret == "0":
        fds.get(pid, {}).pop(int(a.split(",")[0]), None)
    elif name == "chdir" and ret == "0":
        cwd[pid] = absol(c, strings(a)[0])
    elif name == "execve" and ret == "0":
        s = strings(a)
        path, argv = s[0], s[1:]
        argv = argv[:len(argv)]
        real = os.path.realpath(absol(c, path))
        exe[pid] = real
        mine = real == cc or built(real)
        if mine and real != cc and fds.get(pid, {}).get(1, ("", False))[0] == "|pipe":
            mine = False      # its stdout feeds a shell pipeline whose result is a fixture
        if mine:
            t = fds.get(pid, {})
            out = t.get(1)
            inp = t.get(0)
            redirect = None
            if out and not out[1] and out[0].startswith(str(src) + "/"):
                redirect = out[0]
                writers[out[0]] = "replay"      # the program, not the shell, writes it
            stdin = inp[0] if inp and inp[0].startswith(str(src) + "/") else None
            if stdin:
                reads.add(stdin)
            events.append(("exec", c, real, argv, redirect, stdin))
    elif name in ("open", "openat") and not ret.startswith("-"):
        s = strings(a)
        p = absol(c, s[0])
        fds.setdefault(pid, {})[int(ret)] = (p, "O_APPEND" in a)
        mine = exe.get(pid) == cc or built(str(exe.get(pid, "")))
        if re.search(r"O_WRONLY|O_RDWR", a) and (("O_CREAT" in a) or ("O_TRUNC" in a)):
            writers[p] = "replay" if mine else "other"
        elif mine and "O_RDONLY" in a and not ("O_WRONLY" in a or "O_RDWR" in a):
            reads.add(p)
    elif name.startswith("rename") and ret == "0":
        s = strings(a)
        a1, b1 = absol(c, s[0]), absol(c, s[1])
        mine = exe.get(pid) == cc or built(str(exe.get(pid, "")))
        if not mine and writers.get(a1) == "replay":
            events.append(("mv", c, a1, b1))   # a replayed output, moved by make's shell
        if a1 in writers:
            writers[b1] = writers.pop(a1)

rel = lambda p: os.path.relpath(p, src)
inside = lambda p: p.startswith(str(src) + "/")
final = {str(p.relative_to(src)): p.read_bytes() for p in src.rglob("*") if p.is_file()}
fixtures = set()
for p in reads:
    if not inside(p) or not os.path.isfile(p):
        continue
    r = rel(p)
    if writers.get(p) == "replay":
        continue
    if writers.get(p) == "other" or orig.get(r) != final.get(r):
        fixtures.add(r)

# Preserve original-source aliases and already-replayed generation rather
# than capturing their copied bytes.  Every optimization requires exact
# content equality; the resulting package's original artifact pin still
# checks the entire replay.  See tests/ladder/README.md for the provenance.
copy_events = [
    {"kind": e[0], "program": rel(e[2]), "arguments": e[3]}
    if e[0] == "exec" else {"kind": e[0]}
    for e in events
]
archive_copies, generated_copies = fixture_copies(
    args.name, fixtures,
    {r: orig[r] for r in orig_regular if not (src / r).is_symlink()}, final,
    {rel(p) for p, kind in writers.items() if kind == "replay" and inside(p)},
    copy_events,
)
copy_targets = set(archive_copies)
for copies in generated_copies.values():
    copy_targets.update(target for source, target in copies)
fixtures.difference_update(copy_targets)

# ---- write ladder/NAME --------------------------------------------------
out = ROOT / "ladder" / args.name
if out.exists():
    shutil.rmtree(out)
(out / "fixtures").mkdir(parents=True)
q = lambda s: '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t") + '"' \
    if (not s or re.search(r"[\s'\"#\\]", s) or "${" in s) else s
lines = [f"# Generated by tools/capture-build.py from a host build of {Path(args.tarball).name}.",
         "# Runs in the unpacked source tree; needs CC, P, T, L and SRC set.",
         f"# configure {args.configure}".rstrip()]
dirs = set()
for r in sorted(fixtures | copy_targets):
    d = os.path.dirname(r)
    while d:
        dirs.add(d)
        d = os.path.dirname(d)
for e in events:
    if e[0] == "exec":
        for a in e[3]:
            pass
for d in sorted(dirs, key=lambda d: (d.count("/"), d)):
    lines.append(f"mkdir {d}")
for r in sorted(fixtures):
    (out / "fixtures" / r).parent.mkdir(parents=True, exist_ok=True)
    (out / "fixtures" / r).write_bytes(final[r] if r in final else open(src / r, "rb").read())
    lines.append(f"copy ${{SRC}}/fixtures/{r} {r}")
for target, source in sorted(archive_copies.items()):
    if source != target:
        lines.append(f"copy {q(source)} {q(target)}")
here = str(src)
made_dirs = set()
for event_index, e in enumerate(events):
    c = e[1]
    if c != here:
        lines.append("cd ${B}" + ("/" + rel(c) if c != str(src) else ""))
        here = c
    if e[0] == "mkdir":
        lines.append(f"mkdir {q(os.path.relpath(e[2], c))}")
        continue
    if e[0] == "mv":
        lines.append(f"rename {q(os.path.relpath(e[2], c))} {q(os.path.relpath(e[3], c))}")
        continue
    real, argv, redirect, stdin = e[2], e[3], e[4], e[5]
    prog = "${CC}" if real == cc else (os.path.relpath(real, c) if not os.path.relpath(real, c).startswith("..") else "${B}/" + rel(real))
    if prog not in ("${CC}",) and not prog.startswith(("${B}", "./", "/")):
        prog = "./" + prog
    toks = [prog] + argv[1:]
    toks = [t.replace(str(src), "${B}") for t in toks]
    io_in = os.path.relpath(stdin, c) if stdin else "-"
    io_out = os.path.relpath(redirect, c) if redirect else "${L}/out"
    if len(toks) > 100:
        # The runner takes at most 127 arguments: the plain tail goes to a
        # file that runargs appends, one argument per line.
        k = max([i for i, t in enumerate(toks) if "${" in t] + [0]) + 1
        nargs = getattr(sys.modules[__name__], "nargs", 0) + 1
        sys.modules[__name__].nargs = nargs
        (out / "args").mkdir(exist_ok=True)
        (out / "args" / f"{nargs}.txt").write_text("".join(t + "\n" for t in toks[k:]))
        toks = ["${T}/runargs", f"${{SRC}}/args/{nargs}.txt"] + toks[:k]
    lines.append(f"run 0 {q(io_in)} {q(io_out)} ${{L}}/err " + " ".join(q(t) for t in toks))
    for source, target in generated_copies.get(event_index, []):
        lines.append(f"copy {q(os.path.relpath(src / source, c))} {q(os.path.relpath(src / target, c))}")
if here != str(src):
    lines.append("cd ${B}")
inst = []
for spec in args.install_dir:
    sd, dd = spec.split("=", 1)
    for f in sorted((src / sd).iterdir()):
        r = str(f.relative_to(src))
        head = f.read_bytes()[:18] if f.is_file() else b""
        if r not in orig and head[:4] == b"\x7fELF" and head[16] == 2:   # ET_EXEC
            args.install.append(f"{r}={dd}/{f.name}")
for spec in args.install:
    s, d = spec.split("=", 1)
    lines.append(f"copy {s} ${{P}}/{d}")
    inst.append((s, d))
(out / "recipe").write_text("\n".join(lines) + "\n")
with open(out / "HASHES", "w") as h:
    for s, d in inst:
        h.write(f"{hashlib.sha256(final[s]).hexdigest()}  {s}\n")
print(f"{args.name}: {sum(1 for e in events if e[0]=='exec')} replayed commands, "
      f"{sum(1 for e in events if e[0]=='mv')} renames, {len(fixtures)} fixtures; "
      f"{len(copy_targets)} source/generated copies; "
      f"work dir {work}")
