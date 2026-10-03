#!/usr/bin/env python3
"""Check object publication failures with real kernel limits and narrow faults.

All object bytes come from 081 running on seed-forth. Python supplies old-file
sentinels, process limits and filesystem races; no host compiler runs here.
"""
from pathlib import Path
import os
import resource
import signal
import stat
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
(ROOT / "build-out").mkdir(exist_ok=True)
OUT = Path(tempfile.mkdtemp(prefix="object-writer-publication-", dir=ROOT / "build-out"))
BASE = "\n".join((ROOT / name).read_text() for name in (
    "010-lib.fth", "020-cc-arena.fth", "030-cc-io.fth"))
WRITER = (ROOT / "081-cc-object.fth").read_text()
OLD = b"previous complete object must survive\n" * 8
COUNT = 0


def invoke(name, dest, *, status=0, hooks="", body=None, limit=None, before=None):
    global COUNT
    COUNT += 1
    source = BASE + f"\ncreate publication-path s, {dest} [lit] 0 c,\n"
    source += hooks + "\n" + WRITER + "\n"
    source += body or "cc-obj-init [lit] 195 cc-obj-byte publication-path cc-obj-write\n"
    source += "\nbye\n"
    process = subprocess.Popen([ROOT / "seed-forth"], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               preexec_fn=limit)
    if before:
        before(process.pid)
    stdout, stderr = process.communicate(source.encode(), timeout=30)
    assert process.returncode == status, (name, process.returncode, stdout, stderr)
    assert not stdout, (name, stdout)
    if status:
        assert f"error {status}\n".encode() in stderr, (name, stderr)
    else:
        assert not stderr, (name, stderr)
    return dest


def no_temporary(dest):
    assert not list(dest.parent.glob(dest.name + ".obj-*")), dest


def failed(name, *, hooks="", limit=None, absent=False):
    dest = OUT / (name + ".o")
    if not absent:
        dest.write_bytes(OLD)
    invoke(name, dest, status=248, hooks=hooks, limit=limit)
    assert (not dest.exists()) if absent else dest.read_bytes() == OLD, name
    no_temporary(dest)


baseline = invoke("create", OUT / "baseline.o").read_bytes()
assert baseline[:6] == b"\x7fELF\x02\x01"
assert stat.S_IMODE((OUT / "baseline.o").stat().st_mode) == 0o644
no_temporary(OUT / "baseline.o")

# Replacement publishes a new inode only after the complete object is ready.
replacement = OUT / "replacement.o"
replacement.write_bytes(OLD)
replacement.chmod(0o600)
alias = OUT / "previous-hardlink.o"
os.link(replacement, alias)
old_inode = replacement.stat().st_ino
invoke("replace", replacement)
assert replacement.read_bytes() == baseline and alias.read_bytes() == OLD
assert replacement.stat().st_ino != old_inode
assert stat.S_IMODE(replacement.stat().st_mode) == 0o644
no_temporary(replacement)

target = OUT / "symlink-target.o"
target.write_bytes(OLD)
symlink = OUT / "symlink-output.o"
symlink.symlink_to(target)
invoke("replace-symlink", symlink)
assert not symlink.is_symlink() and symlink.read_bytes() == baseline
assert target.read_bytes() == OLD
no_temporary(symlink)


def file_size_limit():
    resource.setrlimit(resource.RLIMIT_FSIZE, (128, 128))
    signal.signal(signal.SIGXFSZ, signal.SIG_IGN)


def descriptor_limit():
    resource.setrlimit(resource.RLIMIT_NOFILE, (3, 3))


# The first write really transfers 128 bytes; the next fails with EFBIG.
failed("partial-write", limit=file_size_limit)
failed("partial-write-absent", limit=file_size_limit, absent=True)
failed("descriptor-exhaustion", limit=descriptor_limit)

# Inject errors at the syscall wrapper boundary, before compiling 081.
failed("zero-write", hooks=": write 2drop drop [lit] 0 ;")
failed("close-failure", hooks=": real-close close ; : close real-close drop [lit] 0 [lit] 5 - ;")
failed("close-failure-absent", hooks=": real-close close ; : close real-close drop [lit] 0 [lit] 5 - ;",
       absent=True)

# Model a directory appearing after initial validation but before rename.
rename_dest = OUT / "rename-race.o"
invoke("rename-failure", rename_dest, status=248, hooks="""
: real-close close ;
: close
  real-close >r
  publication-path [lit] 448 [lit] 0 [lit] 0 [lit] 0 [lit] 0 [lit] 83 syscall6 drop
  r> ;
""")
assert rename_dest.is_dir()
no_temporary(rename_dest)

# Retry EINTR and complete multiple short writes without changing the bytes.
short = invoke("interrupted-short-write", OUT / "short.o", hooks="""
variable write-calls
: real-write write ;
: write
  [lit] 1 write-calls +!
  write-calls @ [lit] 1 = if, 2drop drop [lit] 0 [lit] 4 - exit, then,
  dup [lit] 17 > if, drop [lit] 17 then, real-write ;
""")
assert short.read_bytes() == baseline
no_temporary(short)

# A pre-existing PID-named sibling, including a symlink, belongs to somebody
# else: O_EXCL must reject it without modifying either that entry or its target.
for kind in ("file", "symlink"):
    dest = OUT / ("collision-" + kind + ".o")
    dest.write_bytes(OLD)
    collision = []

    def precreate(pid):
        path = Path(str(dest) + f".obj-{pid:016x}")
        if kind == "symlink":
            path.symlink_to(target)
        else:
            path.write_bytes(OLD)
        collision.append(path)

    invoke("temporary-collision-" + kind, dest, status=248, before=precreate)
    assert dest.read_bytes() == OLD and collision[0].read_bytes() == OLD
    assert collision[0].is_symlink() == (kind == "symlink")
    assert target.read_bytes() == OLD

# Repeated writes and resets in one process cannot retain an open descriptor
# or an owned-temp flag. Only one descriptor beyond stdin/out/err is available.
def one_descriptor():
    resource.setrlimit(resource.RLIMIT_NOFILE, (4, 4))


repeat = OUT / "repeat.o"
invoke("repeat-reset", repeat, limit=one_descriptor, body="""
variable publication-count
: publication-repeat
  [lit] 314159
  begin, publication-count @ [lit] 12 < while,
    cc-obj-init [lit] 195 cc-obj-byte
    publication-path cc-obj-write publication-path cc-obj-write
    [lit] 1 publication-count +!
  repeat,
  [lit] 314159 <> if, [lit] 250 die then, ;
publication-repeat
""")
assert repeat.read_bytes() == baseline
no_temporary(repeat)

# Reject special output objects without opening/replacing them, including
# /dev/full when the tests happen to run with permission to replace it.
for special in (OUT / "directory.o", OUT / "fifo.o", Path("/dev/full")):
    if special.name == "directory.o":
        special.mkdir()
    elif special.name == "fifo.o":
        os.mkfifo(special)
    before = special.stat()
    invoke("special-" + special.name, special, status=248)
    after = special.stat()
    assert (before.st_dev, before.st_ino, before.st_mode) == (
        after.st_dev, after.st_ino, after.st_mode)
    no_temporary(special)

missing = OUT / "missing-parent" / "output.o"
invoke("missing-parent", missing, status=248)
assert not missing.parent.exists()

# Path copying reserves room for the suffix and NUL before any output exists.
invoke("overlong-path", OUT / "unused.o", status=248, body="""
cc-obj-init
create overlong-path [lit] 4097 allot
variable long-index
: fill-long-path
  begin, long-index @ [lit] 4096 < while,
    [lit] 120 overlong-path long-index @ + c! [lit] 1 long-index +!
  repeat,
  [lit] 0 overlong-path [lit] 4096 + c! ;
fill-long-path overlong-path cc-obj-write
""")
assert not (OUT / "unused.o").exists()

# The C driver must reject every source/output identity before the compiler
# reads or writes the file, including its optional preprocessor dump mode.
for kind in ("same", "hardlink", "symlink"):
    for dump in ("0", "1"):
        source = OUT / f"source-{kind}-{dump}.c"
        original = b"int example(void) { return 42; }\n"
        source.write_bytes(original)
        dest = source if kind == "same" else OUT / f"alias-{kind}-{dump}.o"
        if kind == "hardlink":
            os.link(source, dest)
        elif kind == "symlink":
            dest.symlink_to(source)
        result = subprocess.run(["bash", ROOT / "tests/gcc/sysv-object-compile.sh",
                                 source, dest], capture_output=True, timeout=30,
                                env={**os.environ, "SF_NATIVE_DUMP": dump})
        assert result.returncode == 1, (kind, dump, result)
        assert b"source and output must be different files" in result.stderr
        assert source.read_bytes() == original and dest.read_bytes() == original
        assert dest.is_symlink() == (kind == "symlink")
        no_temporary(dest)

print(f"object-writer-publication: {COUNT} writer cases and 6 driver aliases pass")
print(f"object-writer-publication: inspectable evidence: {OUT}")
