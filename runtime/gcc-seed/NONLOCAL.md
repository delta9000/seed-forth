# Ordinary C90 nonlocal return

The original Flex 2.5.11 source needs ordinary `setjmp` and `longjmp`.
`include/setjmp.h` declares a private Linux AMD64 LP64 `jmp_buf`: an array of
eight `long` cells, 64 bytes with eight-byte alignment. It is not compatible
with a host libc buffer. `122-cc-sysv-runtime.fth` independently emits both
43-byte leaf functions as ET_REL objects. The driver includes these members
in its demand-selected runtime archive and source-hashed cache. No host C
compiler, assembler, linker, libc object, or downloaded binary supplies the
production bytes.

The slots at offsets 0, 8, 16, 24, 32, and 40 hold RBX, RBP, R12, R13, R14,
and R15. Offset 48 holds the caller's RSP after the call returns (`RSP+8` on
entry); offset 56 holds the continuation RIP (`[RSP]` on entry). `setjmp`
leaves preserved registers and RSP untouched and returns zero. `longjmp`
reads the C `int` from ESI, maps zero to one, sign-extends the resulting value,
restores all six preserved integer registers and RSP, then jumps to RIP.
The undefined upper half of the integer argument register is ignored. Neither
leaf calls another function or borrows the caller's red zone.

Use only the C90 setjmp contexts: a complete controlling expression; one
operand of a relational/equality comparison with an integer constant expression
whose result is the complete controlling expression; the operand of unary `!`
as that controlling expression; or the complete expression statement, possibly
cast to void. Assignment, initialization, arithmetic and function arguments
containing setjmp are outside this contract. All targets must be initialized
by a still-live invocation in the same thread. Reusing a buffer supersedes
its prior saved environment. Copying/mutating a buffer or returning from its
containing function before longjmp is unsupported.

After longjmp, a non-volatile automatic object local to the function containing
setjmp has an indeterminate value if modified since that invocation. Use
`volatile` when such a changed local must retain its value. Unchanged locals,
static objects and volatile locals are exercised by the checks. There is no
C++ destructor unwinding, thread transfer, signal-mask save/restore, signal-jump
API, floating-point environment restoration, or CET shadow-stack support.
Ordinary setjmp does not promise signal-mask preservation. The leaf routines
do not modify MXCSR or the x87 control word; floating-point state remains as
it was at longjmp, rather than reverting to setjmp-time state.

The header exposes a self-suppressing macro that reaches the actual `setjmp`
symbol without an intervening wrapper frame. For optional GCC-compatible host
oracles it also annotates returns-twice and nonreturning functions. The Forth
compiler's existing stable call-stack behavior handles valid setjmp contexts;
this runtime adds no compiler special cases.

References used to establish the contract:

- [AMD64 System V ABI, sections 3.2.1 and 3.2.2](https://refspecs.linuxbase.org/elf/x86_64-abi-0.99.pdf): register ownership and stack alignment
- [C90 Defect Report 008](https://www.open-std.org/JTC1/SC22/wg14/www/docs/dr_008.html): the rule for modified non-volatile automatic objects
- [WG14 N1570, section 7.13](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf): public nonlocal-jump contract and permitted contexts, retained from C90

Run `python3 tests/gcc/nonlocal-runtime-check.py` for the production proof.
It builds the C fixture, retained returns-twice fixture, runtime objects,
archive and final executable with Forth. It checks initial and resumed returns,
zero-to-one conversion, negative values, INT_MIN, INT_MAX, 0x12345678, bounded
buffer writes, 25 simultaneous recursive targets, nested function-pointer
callbacks, both comparison operand orders, loops, repeated stack reuse, and
re-entry after switch cleanup in a still-live frame. A retained JSON report
records the complete compiler source identity and artifact/input hashes.

Add `--oracle` for separate C90 host builds at `-O0` and `-O2`: mixed
Forth/host callbacks, optimizing host callers against the Forth-built runtime,
and host-libc reference runs. Host-only assembly deliberately changes every
preserved integer register before longjmp, checks all 64 bits after resumption,
checks exact caller RSP/alignment, and poisons the unused upper argument bits.
The existing `sysv-setjmp-check.sh` remains an independent host-libc compiler
ABI oracle. Its success alone never demonstrates a source-built runtime.
