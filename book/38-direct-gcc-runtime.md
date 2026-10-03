# 38. The runtime syscall boundary

The C runtime eventually needs memory, files, and process services. A small
bridge connects ordinary System V calls to the Linux AMD64 syscall ABI.
The bridge is generated directly by Forth into the relocatable object format
from chapter 35. No C compiler, assembler, or libc supplies its target bytes.

The function takes seven C arguments: a syscall number followed by six syscall
arguments. System V places the first six values in RDI, RSI, RDX, RCX, R8, and
R9; the seventh value is at RSP + 8 on entry. Linux instead takes the number
in RAX and its six arguments in RDI, RSI, RDX, R10, R8, and R9. The moves below
are ordered so each source is copied before another move overwrites it.

SYSCALL destroys RCX and R11, both caller-saved registers. The bridge changes
no callee-saved register and leaves RSP unchanged. It returns the raw kernel
result in RAX. Negative values from -4095 through -1 encode errors; public
runtime wrappers must translate them and set their own errno. This leaf does
not create an errno object, allocate memory, or claim a complete libc.

The documented contracts are the [AMD64 System V ABI](https://gitlab.com/x86-psABIs/x86-64-ABI)
and the Linux [syscall calling-convention table](https://man7.org/linux/man-pages/man2/syscall.2.html).
The instruction listing is original project source under the repository license.
This bridge deliberately makes the architecture and operating-system boundary
visible; an internal compiler representation does not make those disappear.

```forth file=122-cc-sysv-runtime.fth
\ 122-cc-sysv-runtime.fth -- raw Linux syscall bridge for a source-built runtime.
\ Load after 010, 020, 030, and 081. Loading this file emits no target code.
\ cc-sysrt-object creates one ET_REL object; cc-obj-write saves it.
\
\ C signature: long __seed_syscall6(long number, long a1, long a2, long a3,
\                                long a4, long a5, long a6);
\ Return the raw kernel result. Values -4095..-1 are errors; no errno is set.
\ The caller, not this leaf, converts that result to its public libc contract.

create cc-sysrt-name  s, __seed_syscall6
create cc-sysrt-code
[lit] 72 c, [lit] 137 c, [lit] 248 c,  \ mov rax,rdi       syscall number
[lit] 72 c, [lit] 137 c, [lit] 247 c,  \ mov rdi,rsi       argument 1
[lit] 72 c, [lit] 137 c, [lit] 214 c,  \ mov rsi,rdx       argument 2
[lit] 72 c, [lit] 137 c, [lit] 202 c,  \ mov rdx,rcx       argument 3
[lit] 77 c, [lit] 137 c, [lit] 194 c,  \ mov r10,r8        argument 4
[lit] 77 c, [lit] 137 c, [lit] 200 c,  \ mov r8,r9         argument 5
[lit] 76 c, [lit] 139 c, [lit] 76 c, [lit] 36 c, [lit] 8 c,
                                      \ mov r9,[rsp+8]    argument 6
[lit] 15 c, [lit] 5 c,                \ syscall           clobbers rcx,r11
[lit] 195 c,                          \ ret               result in rax

: cc-sysrt-object
  cc-obj-init
  cc-obj-text cc-obj-use
  cc-sysrt-code [lit] 26 cc-obj-bytes
  cc-sysrt-name [lit] 15 [lit] 1 [lit] 2 [lit] 0
  cc-obj-text [lit] 0 [lit] 26 cc-obj-symbol drop ;

\ A separate object owns errno for this explicitly single-threaded runtime.
\ Keep it separate so the raw bridge has no libc state or provider collision.
create cc-sysrt-errno-name  s, __errno_location
create cc-sysrt-errno-storage  s, __seed_errno
create cc-sysrt-errno-code
[lit] 72 c, [lit] 141 c, [lit] 5 c,   \ lea rax,[rip+errno]
[lit] 0 c, [lit] 0 c, [lit] 0 c, [lit] 0 c,
[lit] 195 c,                         \ ret

: cc-sysrt-errno-object
  cc-obj-init
  cc-obj-bss cc-obj-use [lit] 4 cc-obj-align [lit] 4 cc-obj-reserve drop
  cc-sysrt-errno-storage [lit] 12 cc-obj-local cc-obj-object cc-obj-default
  cc-obj-bss [lit] 0 [lit] 4 cc-obj-symbol >r
  cc-obj-text cc-obj-use cc-sysrt-errno-code [lit] 8 cc-obj-bytes
  cc-obj-text [lit] 3 cc-obj-pc32 r> [lit] 0 [lit] 4 - cc-obj-reloc
  cc-sysrt-errno-name [lit] 16 cc-obj-global cc-obj-func cc-obj-default
  cc-obj-text [lit] 0 [lit] 8 cc-obj-symbol drop ;

\ Process entry: preserve argc and argv before aligning the outgoing call.
\ Relocate the call to C main, then pass its return value to Linux exit.
create cc-sysrt-main-name  s, main
create cc-sysrt-start-name  s, _start
create cc-sysrt-start-code
[lit] 72 c, [lit] 139 c, [lit] 60 c, [lit] 36 c, \ mov rdi,[rsp]
[lit] 72 c, [lit] 141 c, [lit] 116 c, [lit] 36 c, [lit] 8 c,
                                                 \ lea rsi,[rsp+8]
[lit] 72 c, [lit] 131 c, [lit] 228 c, [lit] 240 c, \ and rsp,-16
[lit] 49 c, [lit] 192 c,                         \ xor eax,eax
[lit] 232 c, [lit] 0 c, [lit] 0 c, [lit] 0 c, [lit] 0 c,
                                                 \ call main (RELA at16)
[lit] 72 c, [lit] 137 c, [lit] 199 c,             \ mov rdi,rax
[lit] 184 c, [lit] 60 c, [lit] 0 c, [lit] 0 c, [lit] 0 c,
                                                 \ mov eax,60
[lit] 15 c, [lit] 5 c,                           \ syscall
[lit] 15 c, [lit] 11 c,                          \ ud2 if exit returned

: cc-sysrt-start-object
  cc-obj-init
  cc-sysrt-main-name [lit] 4 cc-obj-global cc-obj-func cc-obj-default
  cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol >r
  cc-obj-text cc-obj-use cc-sysrt-start-code [lit] 32 cc-obj-bytes
  cc-obj-text [lit] 16 cc-obj-plt32 r> [lit] 0 [lit] 4 - cc-obj-reloc
  cc-sysrt-start-name [lit] 6 cc-obj-global cc-obj-func cc-obj-default
  cc-obj-text [lit] 0 [lit] 32 cc-obj-symbol drop ;
```

The optional interoperability check is `python3 tests/gcc/syscall-check.py`.
Forth produces the bridge object, and a host-built test calls it at two
optimization levels. The test compares process IDs, exercises pipe reads and
writes, checks that raw errors leave the host errno untouched, and maps a file
at a nonzero offset. That final check uses all six syscall arguments, including
the value passed on the C stack. The host C compiler and libc are test oracles
only. This does not yet test a complete Forth-built C runtime.

The reconstruction check passed at both optimization levels on 2026-10-03.
It produced an 880-byte bridge object with SHA-256
`18f80c26c4437d3ad4864c84b6c38adef0bc9b97903500643f69dfc0e2299d54`.
The executable oracle uses the host linker; the later complete bootstrap must
use the Forth linker and the source-built C runtime.

The runtime also has two separate objects. `cc-sysrt-errno-object` owns one
aligned, zero-initialized integer and exports `__errno_location`. This is an
explicitly single-threaded bootstrap contract; thread-local errno is deferred.
`cc-sysrt-start-object` exports `_start`, reads argc/argv from the kernel stack,
aligns the outgoing call, and relocates a call to the C `main`. It then passes
main's result to Linux `exit`. An unexpected return from exit traps with UD2.

Run `python3 tests/gcc/syscall-runtime-check.py` for a fully Forth-produced
C program, startup, errno storage, syscall bridge, and link. The check executes
with two arguments and verifies their values, zeroed errno and stable storage,
getpid, raw EBADF, and the final process status. It needs no host C compiler,
assembler, linker, or libc artifact. This composed reconstruction test passed
on 2026-10-03. It still does not supply the public C allocation and I/O library.
