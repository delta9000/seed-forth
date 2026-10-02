# K1 — the second rung

K1 is a small kernel in C, built by the chain's own tcc-0.9.27, that runs
ordinary static Linux x86-64 programs as real processes and finally hands
the machine to a Linux bzImage.  K0 (1,309 bytes of hex0) runs the seed
route to TinyCC; K1 is what that TinyCC builds to host the rest of the
ladder (musl, make, bash, configure scripts, binutils, gcc, the Linux
build), and then boots the Linux kernel the ladder produces.

```sh
k1/run.sh                                   # K0 -> prebuilt K1 -> direct TinyCC route
k1/run-chain.sh --seed-smoke                 # K0 builds K1, then K1 rebuilds direct TinyCC (3 GiB)
k1/run.sh --no-repo --add DIR=t -- k1 /t/prog args   # any static program
```

`k1/run.sh` builds K0 from `k0/k0.hex0` (stage0's hex0-seed) and K1 with
the direct route's `build-out/pnut-amd64/kit/build/tcc-boot2`, writes a boot image
with `k1/mkimg.py`, and runs QEMU/KVM. Run `./seed-forth <
tools/tcc-ladder-start.fth` first to build that compiler. Exit status comes
back through `isa-debug-exit`, as in `k0/run.sh`.

The default K0/K1/host ladder now uses `tools/tcc-ladder-start.fth` and
`tools/tcc.recipe`: seed Forth builds the recipe runner, the extended Forth
compiler directly builds TinyCC, TinyCC reaches the pinned boot2/boot3
fixed point, and that TinyCC builds both ladder helpers and K1. The old
`tools/amd64-start.fth` / `tools/amd64.recipe` path is the named pnut
control. The historical `build-out/pnut-amd64` output directory remains
because downstream pins can embed it; it does not imply pnut execution.

Before the executable boundary, `tools/tcc_inputs.py` verifies and copies
only raw pinned archives, libc/tool sources and patch fixtures. Seed Forth
builds an exact-patch helper and bintools; those unpack the TinyCC archive
and apply the pinned patches. All 440 prepared source hashes are checked
before Forth compiles TinyCC. Host Python does no extraction, C preprocessing
or source patching in this default route. `tests/tcc/prep-stage-sources.py`
remains a separate host-side source oracle for focused tests.
K1's input disk contains only `hex0-seed` as its initial executable.

`k1/run-chain.sh --seed-smoke` exercises the actual K0-built K1 handoff,
then has K1 rebuild seed Forth and the direct TinyCC fixed point from a
source-only input disk. It needs no GNU/Linux ladder distfiles and defaults
to 3 GiB RAM (`K1_MEM` overrides). Both its exit status and guest PASS marker
are checked. The full `k1/run-chain.sh` continues through the GNU tools and
Linux and retains its larger default memory requirement. `QEMU` may name
a local QEMU executable or wrapper.

For a deliberately low-concurrency full run, `JOBS=1 k1/run-chain.sh`
passes `JOBS` through the chain-built `env` into guest stages 10–12. Merely
inheriting a host environment would not work: the recipe runner starts
children with an empty environment. Unset `JOBS` preserves the existing
stage defaults; accepted values are integers 1–256. Stage 12 now honors
this value instead of forcing 16 jobs. The seed smoke is unchanged.

Optional file-backed RAM uses a fresh workspace file, for example:

```sh
JOBS=1 K1_MEM=16G K1_RAM_FILE=build-out/k1-full/ram.bin \
    K1_DISKS=build-out/k1-full k1/run-chain.sh
```

With file backing, `K1_MEM` must include an explicit `K`, `M`, `G` or `T`
suffix; unitless memory values are rejected because QEMU interprets them
differently in its two memory options.

`K1_RAM_FILE` must name a nonexistent file below this checkout's
`build-out`, with existing real directory parents. Symlink components,
existing files/directories, `..`, commas and control characters are rejected.
The helper creates a mode-0600 sparse file exclusively; QEMU uses shared
file backing with `prealloc=off`. No swap, mount or system settings change.
`K1_RAM_RESERVE` defaults to `8G`: the full potential backing size plus
that headroom must fit the filesystem's current free space. The file is
left for inspection after exit; choose a new pathname for another run.
This setup check is not a runtime resource monitor. File-backed RAM can
be much slower under pressure, and the full ladder's required peak RAM
has not been measured. Anonymous RAM remains the default.

`python3 k1/tests/options-check.py` verifies default recipe identity,
explicit `JOBS` injection, sparse creation, and path/overwrite/disk guards.
A small real K0→K1 probe also passed with 3 GiB shared file-backed RAM:
an empty-environment runner launched an environment-setting test wrapper,
its child received `JOBS=1`, checked 32 MiB of guest memory writes, and
exited with the expected status. Only 50 MiB of backing blocks were used.
The full-run wrapper additionally requires the final Linux handoff,
init greeting and Linux 7.2.8 version markers; QEMU status 85 alone is
insufficient. These checks do not establish full-ladder resource sufficiency.

## Full Linux validation with KVM

From a checkout with the pinned submodules initialized, place the 30 raw
archives named in `k1/chain-inputs.sha256` in `build-out/distfiles`. These
are the existing pins from `ladder/PACKAGES`, `gcc64/SOURCES` and the
stage-10/stage-12 scripts; no generated C or prebuilt compiler is needed.
The archives total 616 MiB. GCC15 is not required for this route.

On a host with QEMU installed and writable KVM access:

```sh
(cd build-out/distfiles && sha256sum -c ../../k1/chain-inputs.sha256)
test -w /dev/kvm                    # fail rather than accidentally choose TCG
command -v qemu-system-x86_64
unset K1_RAM_FILE K1_RAM_RESERVE     # use ordinary guest RAM on this host
JOBS=1 K1_MEM=24G K1_DISKS="$PWD/build-out/k1-full" \
    QEMU=qemu-system-x86_64 k1/run-chain.sh
```

Use a fresh `K1_DISKS` directory; its input/output images are rebuilt.
The host needs room for the selected guest RAM plus its own workload.
The 24 GiB default is a conservative choice, not a measured minimum.
Allow additional disk room for the 625 MiB input image, 4 GiB output
image and extracted results. K1 keeps the build filesystem in guest RAM,
so archive size alone is not a RAM estimate. The full working-set peak
has not been measured. `JOBS=1` limits compiler process concurrency.

Success means wrapper status 0, QEMU status 85, and all these guest lines
in `build-out/k1-full/serial.log` (checked by the wrapper):

- `finish: K1 hands the machine to the Linux kernel it built`
- `init: hello from a Linux kernel built from hex0 and seed-forth`
- `init: Linux version 7.2.8` followed by the build/version details

`build-out/k1-full/out.img` contains the result tar written by the
chain-built tools, including the kernel and stage logs. Retain that image
and the serial log for comparison. A missing marker or nonzero wrapper
status is not a completed Linux validation.

The direct raw-input K0/K1 smoke has passed. A subsequent full attempt
was interrupted after K1's direct TinyCC proof and did not record a
complete musl/GNU/Linux result. Full Linux validation is still pending.

## Boot

K0 knows nothing about K1: `mkimg.py` writes K0's usual image format with
init = `k1`, and K1's own arguments in the file `/k1.args`
(`[-v] [-i stdin] prog args...`, one per line).  K0 execs k1 like any
program — ring 0, K0's identity map, rsp at an argv block — and k1 then:

1. reads the e820 map from QEMU's fw_cfg (`etc/e820`);
2. builds its own page tables: the low 4 MiB identity-mapped,
   supervisor-only, for K1's image (linked at 0x200000), and all physical
   memory at `KBASE` = 0xFFFF800000000000 with 1 GiB pages;
3. loads its GDT (kernel 0x10/0x18, user 0x2B/0x33, TSS 0x38), IDT
   (exceptions only), TSS, and the SYSCALL MSRs (STAR's sysret base is
   0x23 so SS gets RPL 3), and masks both PICs: there are no interrupts;
4. calibrates the TSC against PIT channel 2 and reads the CMOS clock;
5. copies K0's file table into its RAM file system, then gives K0's image
   memory to its page allocator;
6. starts init (pid 1) with stdin from `-i` (or /dev/null), stdout and
   stderr on the serial console.  When init exits, QEMU exits with its
   status (signals as 128+n).

## Design

- **Memory.** Physical pages come from a free list, else a bump pointer
  over the e820 RAM, so RAM never touched is never written and KVM never
  backs it.  `kmalloc` has power-of-two classes up to a page; larger
  requests take contiguous pages from the bump area.
- **Address spaces.** One 4-level page table per process.  The upper half
  is the shared direct map; PD entries 0-1 map K1 (so user programs start
  at 0x400000, as static ELFs do).  User memory is demand-zero within
  VMAs (image, brk, mmap, a 64 MiB stack below 0x7FFFFFFFF000), each
  with its protection; `mprotect` splits VMAs and rewrites PTEs, and a
  write to a read-only page is a fault.  mmap addresses grow down from
  0x7F0000000000, stepping under any mapping in the way; a page-aligned
  hint is honoured when its range is free (GCC's PCH files need their
  address back), and `brk` refuses to grow over a mapping, so musl's
  malloc falls back to mmap.  fork copies every present page — no
  copy-on-write.
- **Processes.** Ring 3, entered and left through SYSCALL/SYSRET;
  exceptions use the IDT and IRETQ.  Each process has a 32 KiB kernel
  stack with its user registers (`struct tframe`) on top.  A process runs
  until it blocks (wait4, a pipe, poll, a vfork child, pause), exits, or
  is preempted by the PIT tick (100 Hz, PIC vectors 32-47) while in user
  mode; `make -j` and alarm-driven configure probes need both.  SSE state is
  saved with FXSAVE on every switch; FS base per process (musl's TLS).
- **Files.** A RAM file system: regular files in a 3-level radix tree of
  pages (sparse holes read zero), directories as a creation-ordered list
  plus a hash table past 16 entries, symlinks, hard links, modes,
  ownership, ns timestamps (make needs mtimes), `/dev/{null,zero,tty,
  console,random,urandom}`, `/tmp` (1777), FIFOs (`mknod`), and
  `/proc/self/fd/N` and `/proc/self/maps`.  An inode is freed when it has
  no names and no open files.
- **Disks.** `ata.c` drives QEMU's primary IDE channel by PIO (LBA48,
  `rep insw`/`outsw`, no interrupts).  hda holds the starting tree as an
  archive `mkdisk.py` writes, imported at boot; hdb is `/dev/hdb`, which
  `ladder/finish.sh` tars its results to for the host to read back.
- **Pipes.** 64 KiB rings with blocking reads and writes; writing with no
  readers raises SIGPIPE (so `yes | head` ends).
- **Signals.** sigaction, sigprocmask, kill/tkill/tgkill, pause,
  sigsuspend, default actions (SIGCHLD and friends ignored, others
  terminate), handlers via an on-stack frame and the sa_restorer that
  musl supplies, SA_RESTART (an interrupted blocking call is re-executed
  by backing up rip), SA_NODEFER, SA_RESETHAND, `sigaltstack`.  Signals
  are delivered on return from a syscall or from an interrupt (with every
  register restored); a user page fault or other trap is delivered as
  SIGSEGV/SIGILL/SIGFPE to a handler if there is one.  `alarm`,
  `setitimer` and `getitimer` (ITIMER_REAL) run off the tick.
- **exec.** Static ELF only (ET_EXEC, or ET_DYN loaded at
  0x555555554000); PT_INTERP is ENOEXEC.  `#!` scripts with one optional
  argument, nested up to 4.  The auxv carries AT_PHDR, AT_ENTRY,
  AT_RANDOM, AT_EXECFN and friends.  A segment whose p_filesz runs past
  the end of the file is zero-filled, as Linux's mmap would (pnut writes
  such ELFs).
- **Linux hand-off.** `reboot(2)` with `LINUX_REBOOT_CMD_KEXEC` loads
  `/boot/bzImage` (64-bit boot protocol ≥ 2.12, XLF_KERNEL_64) at an
  address aligned to its `kernel_alignment` and at least its
  `pref_address`, with room for `init_size`; builds boot_params from the
  bzImage's setup header, the fw_cfg e820 map, `/boot/cmdline` and
  `/boot/initrd.cpio`; switches to page tables identity-mapping the first
  512 GiB; and jumps to load+0x200 with rsi = &boot_params.  K1's GDT
  already has the flat 0x10/0x18 segments the protocol requires.

## Linux ABI shortcuts

Everything here is deliberate and holds for the bootstrap's workloads;
each is a place K1 differs from Linux.

- One CPU; only the timer interrupt.  `nanosleep` and timed
  `poll`/`select` spin, yielding.
- No permission checks (everything runs as root, uid 0); `access(X_OK)`
  checks only that some x bit is set.
- File-backed `mmap` is a private copy; `MAP_SHARED` writes are not
  written back.
- `clone` supports fork, vfork and `CLONE_VM|CLONE_VFORK` (musl's
  posix_spawn); `CLONE_THREAD` is EINVAL, `clone3` ENOSYS; `futex` returns
  0 (one thread per process).
- A bad user pointer faults in the kernel and kills the process with
  SIGSEGV instead of returning EFAULT.
- `/proc` is only `self/fd` and `self/maps`; no sockets (EAFNOSUPPORT), no ttys (`ioctl` is ENOTTY, so
  every program sees a non-interactive stdin).  `getdents64` lists `.`,
  `..`, then names in creation order.
- `statx`, `copy_file_range`, `sendfile`, `fallocate`, `rseq`, `waitid`
  are ENOSYS (musl and coreutils fall back).  Any syscall not listed in
  `sys.c` is ENOSYS and is reported once on the console.

## Files

4,879 lines of C and assembly; the kernel is 101,192 bytes (208,144 with
the `-g` symbols `build.sh` adds by default; `K1_CFLAGS=" "` drops them).

| File | Lines | What |
|---|---:|---|
| `k1.S` | 376 | entry from K0, SYSCALL entry/exit, swtch, exception stubs |
| `main.c` | 567 | boot: memory primitives, console, kprintf, TSC/RTC, fw_cfg e820, GDT/IDT/TSS/MSRs, kernel page tables, traps |
| `mm.c` | 600 | physical pages, kmalloc, page tables, VMAs, fork copy, mmap/munmap/mremap/brk |
| `fs.c` | 718 | inodes, radix data, directories, path walk, pipes, FIFOs, devices, `/proc/self`, K0 import |
| `ata.c` | 218 | IDE PIO disks, the hda archive import |
| `proc.c` | 752 | processes, scheduler, fork/clone, exec (ELF, `#!`), exit/wait, signals, init |
| `sys.c` | 1,207 | the syscall table |
| `linux.c` | 120 | the bzImage hand-off |
| `mkimg.py`, `run.sh`, `build.sh` | | boot image, QEMU run, build |
| `tcc-musl.sh`, `mkcpio.py`, `tests/` | | host-side test helpers (not part of the chain) |

## Tests

- **Direct seed route (M1):** `k0/run.sh` and `k1/run.sh` require the
  direct TinyCC recipe's PASS result. `k1/run-chain.sh --seed-smoke` additionally
  proves K0 built K1 and K1 reran the source-only route, with real
  fork/exec/wait. The recipe has 49 explicit child runs plus pinned exact-patch
  applications, independently
  pinned TinyCC executable/object fixed points, 136 libc checks, rebuilt
  float/bitfield/VLA checks, and TinyCC-built bintools/simple-patch.
  `tests/tcc/kernel-route-check.sh` exercises the actual fresh host entry
  and functional helpers; `python3 tests/tcc/kernel-route-check.py` checks
  image/source inventories and route wiring without an emulator. These
  host checks do not prove guest execution.
  The raw-route guest smoke was also verified with QEMU 10.0.13 TCG,
  3 GiB RAM and no KVM: K0 built K1, K1 rebuilt from the raw input disk,
  both direct TinyCC fixed points passed, and K1 init exited with status 0.
  This smoke stops before the GNU/Linux ladder; it does not claim a fresh
  complete Linux rebuild.
- **`tests/ktest.c` (M2):** built with the chain's tcc-musl
  (`k1/tcc-musl.sh`), 48 checks: `yes | head` with SIGPIPE, fork without
  exec, handlers, masking, SIGCHLD, SIGTERM and SIGSEGV wait statuses,
  files, symlinks, hard links, `utimensat`/mtime order, rename, chmod,
  readdir, getcwd, dup2/fcntl, 10 MiB malloc + realloc (mremap), mmap,
  posix_spawn (CLONE_VM|CLONE_VFORK), poll, clock_gettime, uname, vfork.
  The same binary passes on Linux and under K1.
- **Linux hand-off (M3):** `tests/kexec.c` under K1 boots a stock
  x86-64 bzImage (Alpine 6.18.52 `vmlinuz-virt`, for testing only) with an
  initramfs (`mkcpio.py`) whose `/init` is `tests/linit.c`; Linux prints
  its log on ttyS0, runs `/init`, which exits QEMU with status 42.
