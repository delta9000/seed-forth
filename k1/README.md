# K1 — the second rung

K1 is a small kernel in C, built by the chain's own tcc-0.9.27, that runs
ordinary static Linux x86-64 programs as real processes and finally hands
the machine to a Linux bzImage.  K0 (1,309 bytes of hex0) runs the seed
route to TinyCC; K1 is what that TinyCC builds to host the rest of the
ladder (musl, make, bash, configure scripts, binutils, gcc, the Linux
build), and then boots the Linux kernel the ladder produces.

```sh
k1/run.sh                                   # K0 -> K1 -> the seed-only amd64 route
k1/run.sh --no-repo --add DIR=t -- k1 /t/prog args   # any static program
```

`k1/run.sh` builds K0 from `k0/k0.hex0` (stage0's hex0-seed) and K1 with
`build-out/k1/tcc` (a copy of the route's `tcc-boot2`), writes a boot image
with `k1/mkimg.py`, and runs QEMU/KVM.  Exit status comes back through
`isa-debug-exit`, as in `k0/run.sh`.

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

- **Seed route (M1):** `k1/run.sh` → `amd64-runner: PASS (seed-built tools
  only)` in ~4.6 s, the same 79 child executions as under K0, with real
  fork/exec/wait.
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
