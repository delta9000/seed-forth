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

The source-built directory wrapper uses this bridge for the original
`libcpp/files.c` precompiled-header search. Each stream owns a directory
descriptor and a 32 KiB record buffer; checked record lengths protect the
variable-length names returned by Linux. EOF preserves errno, and closing
releases the stream even if the kernel reports an error. See
`runtime/gcc-seed/DIRECTORIES.md` for the bounded interface and independent
tests. This runtime prerequisite alone does not establish compiler type
semantics or a complete libcpp build.

The separate source-built math archive supplies the binary64 `math.h`
functions, first needed for `exp` and `log` in the original GCC optional
automaton-splitting heuristic. Literal `-lm` selects that genuine Forth archive
at its command-line position. The functions, errno policy and measured accuracy
are documented in `runtime/gcc-seed/MATH.md`; library ordering and the
unsupported general search options are documented in
`runtime/gcc-seed/MATH-LINKING.md`.

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

\ Private Forth-C frame contract, not a portable host backtrace interface.
\ The calling C function keeps RBP fixed; [RBP] is its parent's saved frame.
\ This leaf adds no frame and preserves every callee-saved register.
create cc-sysrt-frame-name s, __seed_parent_frame
create cc-sysrt-frame-code
[lit] 72 c, [lit] 139 c, [lit] 69 c, [lit] 0 c, \ mov rax,[rbp+0]
[lit] 195 c,                                    \ ret
: cc-sysrt-frame-object
  cc-obj-init
  cc-obj-text cc-obj-use cc-sysrt-frame-code [lit] 5 cc-obj-bytes
  cc-sysrt-frame-name [lit] 19 cc-obj-global cc-obj-func cc-obj-default
  cc-obj-text [lit] 0 [lit] 5 cc-obj-symbol drop ;

\ Linux AMD64 signal-handler return. The kernel owns the signal frame;
\ do not add a C/Forth frame or change RSP before rt_sigreturn.
create cc-sysrt-sigreturn-name s, __seed_sigreturn
create cc-sysrt-sigreturn-code
[lit] 184 c, [lit] 15 c, [lit] 0 c, [lit] 0 c, [lit] 0 c,
                                                 \ mov eax,15
[lit] 15 c, [lit] 5 c,                           \ syscall rt_sigreturn
[lit] 15 c, [lit] 11 c,                          \ ud2 if syscall returned
: cc-sysrt-sigreturn-object
  cc-obj-init
  cc-obj-text cc-obj-use cc-sysrt-sigreturn-code [lit] 9 cc-obj-bytes
  cc-sysrt-sigreturn-name [lit] 16 cc-obj-global cc-obj-func cc-obj-default
  cc-obj-text [lit] 0 [lit] 9 cc-obj-symbol drop ;

\ Runtime-aware process entry. Keep argc/argv across initialization, pass
\ envp=argv+argc+1 as main's third argument (SysV), and keep the minimal
\ raw _start builder independent of the C runtime.
create cc-sysrt-init-name s, __seed_init_runtime
create cc-sysrt-runtime-start-code
[lit] 72 c, [lit] 139 c, [lit] 60 c, [lit] 36 c, \ mov rdi,[rsp]
[lit] 72 c, [lit] 141 c, [lit] 116 c, [lit] 36 c, [lit] 8 c,
                                                 \ lea rsi,[rsp+8]
[lit] 72 c, [lit] 131 c, [lit] 228 c, [lit] 240 c, \ and rsp,-16
[lit] 87 c, [lit] 86 c,                          \ push rdi; push rsi
[lit] 232 c, [lit] 0 c, [lit] 0 c, [lit] 0 c, [lit] 0 c,
                                                 \ call initializer (RELA16)
[lit] 94 c, [lit] 95 c,                          \ pop rsi; pop rdi
[lit] 72 c, [lit] 141 c, [lit] 84 c, [lit] 254 c, [lit] 8 c,
                                                 \ lea rdx,[rsi+rdi*8+8]
[lit] 49 c, [lit] 192 c,                         \ xor eax,eax
[lit] 232 c, [lit] 0 c, [lit] 0 c, [lit] 0 c, [lit] 0 c,
                                                 \ call main (RELA30)
[lit] 72 c, [lit] 137 c, [lit] 199 c,             \ mov rdi,rax
[lit] 232 c, [lit] 0 c, [lit] 0 c, [lit] 0 c, [lit] 0 c,
                                                 \ call exit (RELA38)
[lit] 15 c, [lit] 11 c,                          \ ud2 if exit returned
create cc-sysrt-exit-name s, exit
: cc-sysrt-runtime-start-object
  cc-obj-init
  cc-obj-text cc-obj-use cc-sysrt-runtime-start-code [lit] 44 cc-obj-bytes
  cc-sysrt-init-name [lit] 19 cc-obj-global cc-obj-func cc-obj-default
  cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol >r
  cc-obj-text [lit] 16 cc-obj-plt32 r> [lit] 0 [lit] 4 - cc-obj-reloc
  cc-sysrt-main-name [lit] 4 cc-obj-global cc-obj-func cc-obj-default
  cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol >r
  cc-obj-text [lit] 30 cc-obj-plt32 r> [lit] 0 [lit] 4 - cc-obj-reloc
  cc-sysrt-exit-name [lit] 4 cc-obj-global cc-obj-func cc-obj-default
  cc-obj-undef [lit] 0 [lit] 0 cc-obj-symbol >r
  cc-obj-text [lit] 38 cc-obj-plt32 r> [lit] 0 [lit] 4 - cc-obj-reloc
  cc-sysrt-start-name [lit] 6 cc-obj-global cc-obj-func cc-obj-default
  cc-obj-text [lit] 0 [lit] 44 cc-obj-symbol drop ;
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

`cc-sysrt-runtime-start-object` is the entry the direct driver links. Its
44-byte body pushes argc/argv, calls `__seed_init_runtime` (relocation at
offset 16), and pops them back. It then sets RDX to `argv+argc+1` with the
five-byte `lea rdx,[rsi+rdi*8+8]`, the kernel's environment vector. A C
`main(int argc, char **argv, char **envp)` therefore sees the same pointer
the initializer stored in `environ`, as glibc and musl provide. The call to
`main` is relocated at offset 30. Its result goes to the C library's `exit`
(relocated at offset 38), not straight to the kernel: returning from `main`
must run `atexit` handlers and flush streams exactly as calling `exit` does.
The raw entry passes no envp and still makes the Linux exit call itself: it
serves only minimal two-argument syscall proofs without the C runtime.

Run `python3 tests/gcc/syscall-runtime-check.py` for a fully Forth-produced
C program, startup, errno storage, syscall bridge, and link. The check executes
with two arguments and verifies their values, zeroed errno and stable storage,
getpid, raw EBADF, and the final process status. It needs no host C compiler,
assembler, linker, or libc artifact. This composed reconstruction test passed
on 2026-10-03. It still does not supply the public C allocation and I/O library.

A fourth, optional object provides `__seed_parent_frame`, a private adapter
for the Forth C compiler's fixed-RBP frame chain. The helper adds no frame:
its five-byte body loads `[rbp]` into the result register and returns. This
is the saved parent frame of the C function making the call. It is deliberately
not a generic host backtrace API and must not be called from a compiler that
omits or repurposes RBP. The private `seed-frame.h` states that contract.

Original libiberty `C_alloca` estimates caller depth from the address of one
of its own locals. A caller's temporary expression/argument stack changes
that address between calls in the same live C frame. The preserved failure
witness shows a live block being reclaimed after such a call. Giving the
existing allocator its actual caller frame removes that variation while
preserving its heap chain and lazy reclamation algorithm. The adaptation is
guarded by the compiler identity and kept as a provenance patch to the original
source; it does not change ordinary C calls or replace allocation with a leak.
The primitive frame test and original allocator lifetime test are separate
proofs, and the latter must pass before accepting the adapted consumer.


## Nonlocal return for the original Flex source

`setjmp` saves six callee-saved integer registers plus the caller stack pointer
and continuation address. `longjmp` restores these and resumes that continuation
with the exact `int` argument, mapping zero to one. Both are independent leaf
objects; Forth writes every byte into ET_REL without an assembler. The complete
C90 usage boundary and independent checks are in
the nonlocal-return contract in `runtime/gcc-seed/NONLOCAL.md`.

```forth file=122-cc-sysv-runtime.fth

\ Ordinary C90 nonlocal return. Layout: RBX,RBP,R12,R13,R14,R15,RSP,RIP.
\ The saved RSP is the caller's value after this leaf would return.
\ No signal mask, floating-point environment, or shadow stack is saved.
create cc-sysrt-setjmp-name s, setjmp
create cc-sysrt-setjmp-code
[lit] 72 c, [lit] 137 c, [lit] 31 c,             \ mov [rdi],rbx
[lit] 72 c, [lit] 137 c, [lit] 111 c, [lit] 8 c, \ mov [rdi+8],rbp
[lit] 76 c, [lit] 137 c, [lit] 103 c, [lit] 16 c, \ mov [rdi+16],r12
[lit] 76 c, [lit] 137 c, [lit] 111 c, [lit] 24 c, \ mov [rdi+24],r13
[lit] 76 c, [lit] 137 c, [lit] 119 c, [lit] 32 c, \ mov [rdi+32],r14
[lit] 76 c, [lit] 137 c, [lit] 127 c, [lit] 40 c, \ mov [rdi+40],r15
[lit] 72 c, [lit] 141 c, [lit] 68 c, [lit] 36 c, [lit] 8 c,
                                                \ lea rax,[rsp+8]
[lit] 72 c, [lit] 137 c, [lit] 71 c, [lit] 48 c, \ mov [rdi+48],rax
[lit] 72 c, [lit] 139 c, [lit] 4 c, [lit] 36 c,  \ mov rax,[rsp]
[lit] 72 c, [lit] 137 c, [lit] 71 c, [lit] 56 c, \ mov [rdi+56],rax
[lit] 49 c, [lit] 192 c,                         \ xor eax,eax
[lit] 195 c,                                    \ ret
: cc-sysrt-setjmp-object
  cc-obj-init
  cc-obj-text cc-obj-use cc-sysrt-setjmp-code [lit] 43 cc-obj-bytes
  cc-sysrt-setjmp-name [lit] 6 cc-obj-global cc-obj-func cc-obj-default
  cc-obj-text [lit] 0 [lit] 43 cc-obj-symbol drop ;

\ Only ESI is the C int argument. Do not depend on its undefined upper bits.
\ Sign-extension is harmless for host int callers and matches Forth C values.
create cc-sysrt-longjmp-name s, longjmp
create cc-sysrt-longjmp-code
[lit] 137 c, [lit] 240 c,                         \ mov eax,esi
[lit] 133 c, [lit] 192 c,                         \ test eax,eax
[lit] 117 c, [lit] 5 c,                           \ jnz normalized
[lit] 184 c, [lit] 1 c, [lit] 0 c, [lit] 0 c, [lit] 0 c,
                                                 \ mov eax,1
[lit] 72 c, [lit] 152 c,                          \ cdqe
[lit] 72 c, [lit] 139 c, [lit] 31 c,              \ mov rbx,[rdi]
[lit] 72 c, [lit] 139 c, [lit] 111 c, [lit] 8 c,  \ mov rbp,[rdi+8]
[lit] 76 c, [lit] 139 c, [lit] 103 c, [lit] 16 c, \ mov r12,[rdi+16]
[lit] 76 c, [lit] 139 c, [lit] 111 c, [lit] 24 c, \ mov r13,[rdi+24]
[lit] 76 c, [lit] 139 c, [lit] 119 c, [lit] 32 c, \ mov r14,[rdi+32]
[lit] 76 c, [lit] 139 c, [lit] 127 c, [lit] 40 c, \ mov r15,[rdi+40]
[lit] 72 c, [lit] 139 c, [lit] 103 c, [lit] 48 c, \ mov rsp,[rdi+48]
[lit] 255 c, [lit] 103 c, [lit] 56 c,            \ jmp [rdi+56]
: cc-sysrt-longjmp-object
  cc-obj-init
  cc-obj-text cc-obj-use cc-sysrt-longjmp-code [lit] 43 cc-obj-bytes
  cc-sysrt-longjmp-name [lit] 7 cc-obj-global cc-obj-func cc-obj-default
  cc-obj-text [lit] 0 [lit] 43 cc-obj-symbol drop ;
```
