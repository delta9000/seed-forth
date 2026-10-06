# Measured working-directory and setbuf interfaces

Original GCC 4.0.4 at `944765863eec87a9f37e297994fd2af960397138`
uses `getcwd` in `libiberty/getpwd.c`. The historical configuration lacks
`HAVE_GETCWD`, selecting original `libiberty/getcwd.c`, which calls unavailable
`getwd`. Adding a real implementation does not change that historical answer.
A subsequent genuine configure replay must select the implementation and omit
the fallback; neither original source edits nor forced macros are acceptable.

`gcc/gcov-io.c:137` calls `setbuf(gcov_var.file, (char *)0)` immediately after
opening its stream. A search of original gcc/libcpp/libiberty, excluding the
compiler testsuite, found no other setbuf call. This consumer requests actual
unbuffered operation, which [buffered streams](STDIO-BUFFERING.md) provide.

## getcwd: caller-owned storage and a visible kernel bound

The public type is `char *getcwd(char *, size_t)`. Local Linux AMD64
`asm/unistd_64.h` defines syscall 79; local public headers independently check
the pointer signature and eight-byte unsigned size_t. The Linux
[v6.1 syscall implementation](https://github.com/torvalds/linux/blob/v6.1/fs/d_path.c#L369-L421)
returns a NUL-inclusive length, ERANGE when the path does not fit, ENOENT for
a deleted cwd, and ENAMETOOLONG beyond its PATH_MAX pathname storage. These
facts are verified against real own temporary directories, separately from
injected syscall tests. The runtime is original project code, not adapted
kernel or libc source.

A successful call writes the complete absolute physical path plus its NUL,
returns the original buffer pointer and preserves errno. It does not use PWD,
cache across directory changes, allocate, or silently truncate. All kernel
errors in -4095 through -1 return NULL and set the corresponding positive errno.
The raw syscall sees the complete unsigned size width. It is called once.

Zero size is rejected with EINVAL before the syscall, matching the [POSIX zero-size requirement](https://pubs.opengroup.org/onlinepubs/9699919799/functions/getcwd.html)
rather than the raw kernel's ERANGE. NULL buffer is also rejected
with EINVAL at every size: the GNU allocating extension is deliberately absent.
The caller must provide writable storage of the stated size. Kernel EFAULT
is exposed for inaccessible destinations; a partially inaccessible destination
may have been partly written before EFAULT, so unchanged output is not promised
on every error. Early wrapper rejections, ordinary insufficient-size failures,
deleted cwd and kernel long-path failures do not write caller storage.

The measured local kernel bound is PATH_MAX=4096, including the terminator.
Longer reachable paths fail ENAMETOOLONG even with a larger caller buffer.
Host libc's directory-walking fallback can handle such a path; this runtime
does not supply that fallback. This long-path boundary is narrower than the
full POSIX getcwd contract; it is not presented as a missing GNU-only extension. A successful kernel result beginning with
`(unreachable)` is rejected with ENOENT instead of returning a non-absolute
path. That rejection may leave the kernel-written bytes in caller storage.
The corresponding synthetic path is tested; real chroot/mount/credential
changes are not exercised or required by this focused proof.

## setbuf

The public type is `void setbuf(FILE *, char *)`, implemented as
`setvbuf(stream, buffer, buffer ? _IOFBF : _IONBF, BUFSIZ)`; see
[STDIO-BUFFERING.md](STDIO-BUFFERING.md). The NULL form is the unbuffered
operation described by the [GNU libc manual](https://www.gnu.org/software/libc/manual/2.34/html_node/Controlling-Buffering.html);
call it immediately after opening the stream, before other operations. It
preserves errno, descriptor identity, file position and stream state. A
non-NULL buffer of `BUFSIZ` bytes becomes the stream's buffer. A NULL or
closed stream is rejected with `EBADF` (glibc would crash); a dangling or
arbitrary FILE pointer remains outside the live-object contract.

## Focused evidence and limits

Run `python3 tests/gcc/directory-buffering-check.py`. It separates static
Forth-only production from independent host libc/source at O0/O2 and both
caller/provider ABI directions. Real root, physical symlink, renamed and
deleted directory cases, every short capacity, exact pointer/NUL/errno,
protected-page boundaries and an actually constructed overlong cwd exercise
getcwd. Test doubles check all kernel errno values, full-width sizes and the
non-absolute rejection without security-setting changes.

Real fopen/fdopen streams prove immediate binary I/O with NULL setbuf, and a
caller buffer that holds output until `fflush` (also checked with host libc).
NULL and closed streams return with `EBADF`. Public-call doubles verify that
setbuf forwards exactly to setvbuf in both ABI directions. They do not assume either FILE layout. Each subprocess is serial,
bounded to 1 GiB and 300 seconds, owns a process group, and retains its command
record before reporting timeout failure. The timeout cleanup branch is tested.
The original seed and all Forth layers are hashed before and after.

This focused check does not run the held broad suites, establish a new genuine
configure epoch, link or execute GCC, or prove a bootstrap. Owner/independent
qualification results must identify the final source identity separately.

The test cleanup helper is a repository-relative dependency on the preceding
qualified 80667 harness packet: `tests/gcc/measured_runtime_runner.py`, SHA256
`993cbfbeb9fd45db92afa3a945be4cc6f007dbb4969657f9c0e54bd482e4d0cf`.
It is test infrastructure and does not change the compiler/runtime identity.

Qualification identifies the final source separately. Independent review
exposed diagnostic-induced SIGPIPE and SIGXFSZ in the initial terminal path.
Those retained failures and a review of full-pipe blocking motivated removing
diagnostic I/O entirely. Intermediate signal-mask implementations are
superseded evidence, not the accepted contract. Earlier owner attempts also
retain two test-only host-compiler warnings: a stack-address fixture and libc's
nonnull declaration in an excluded rejection case. The corrected branches
distinguish supported libc comparisons from runtime-specific rejections;
failed attempts are not described as passes.

Final focused qualification uses compiler/runtime identity
`c70c6ebcaf673a277880a439fadc04d1bded98b2d62784a4715583b84868336a`.
The owner gate and independent review passed the final silent-exit contract.
Independent checks include all four rejected forms against four stderr failure
conditions, 70 public-call ABI combinations, exact 4094–4097-byte path boundaries,
and raw high-byte/newline names with an intentionally false PWD. All 42 prior
runtime objects and the ordinary 36,872-byte runtime executable remain
byte-identical to the frozen 80667 base. These are focused claims; broader
composition and genuine configure evidence remain separate.

## Fresh original configure selection

A subsequent genuine libiberty configure replay on final c70c6e completed with
138 recorded compiler invocations: 56 succeeded and 82 failed feature/compiler
probes. The original getcwd presence probe linked successfully. Generated
config.h defines HAVE_GETCWD=1; its SHA256 is
`31dd99c8f57fe9631b118e90a40f72c0d5989342e2cabb5bc2f376facf0eba7a`.
The original Makefile's effective 72-member selection omits getcwd.o. The
static CONFIGURED_OFILES inventory still names possible fallbacks; it is not
the selected archive-member list. No full archive was built.

The original getpwd, xmalloc, xexit and xatexit objects were built by their
real generated Makefile rules and linked with the Forth runtime. That narrow
executable returns the exact cwd with false PWD, grows past its initial
100-byte allocation, and preserves its original cached-pointer behavior.
For comparison, compiling unchanged original getcwd.c with the retained old
configuration and final compiler exposes its unresolved getwd dependency.
That comparison is explicitly mixed-epoch evidence, not an old same-epoch
build. Fresh getpwd.o instead references the real runtime getcwd and has no
getwd reference. Only the documented C_alloca adapter exists in the private
source view; these witness sources are unchanged originals.

The run verifies every original source file against the pinned archive,
retains compiler/source/configuration hashes and each probe's actual inputs
and outputs, and guards host target tools. Configure's unrelated positive and
negative feature answers still need their own audit; a complete coherent GCC
configuration/cohort, library build, cc1 link and bootstrap remain unclaimed.
The first witness attempt stopped at a test-only path-length precondition;
the corrected own-directory fixture passed and both attempts are retained.
