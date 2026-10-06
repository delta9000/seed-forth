# 18. Decimal parsing and the interpreter loop

[Previous: Inline branch operands](17-inline-branch-operands.md) · [Practice help](../practice/18-solutions.md) · [Next: Audit synthesis and capstone](19-audit-synthesis-and-capstone.md)

The token `407` contains three readable digits. Does the seed put 407 on
its stack? That depends on who reads it. `[lit]` asks a decimal parser to
convert its next token. The outer interpreter instead asks the dictionary
to find every token it reads. A number-shaped spelling does not change
that question.

This chapter opens the final **168 file bytes**: the 85-byte decimal helper
and the 83-byte interpreter loop. You will trace both the value and the
success flag, distinguish rejecting a token from rejecting a definition,
and predict exactly when a found word executes or becomes a future CALL.
The byte path closes at file offset **0x6EC**.

## Bring the contracts and choose your route

Use [Chapter 13](13-arithmetic-in-instruction-bytes.md) for register widths
and condition flags, [Chapter 14](14-physical-io-and-exit.md) for Linux
write/exit boundaries, [Chapter 15](15-dictionary-and-token-input.md) for
`read_word`, `find`, and `execute`, and
[Chapter 16](16-native-colon-compiler.md) for `[lit]` and call emission.
The preceding chapter explains how inline branches adjust native returns.
Here ordinary dispatch reuses that same distinction between the data stack
and the native return stack.

Check your starting picture: if the logical data stack is `[99,T,3]`, which
value is in `rdi`? After `find` replaces `T,3` with an xt, where is 99?
The answers are three in `rdi`, then 99 at `[rbp]` beneath the cached xt.
If that second answer is uncertain, revisit Chapter 12's cached-top model.
If comfortable, attempt S18-03 and S18-05 before reading their worked
explanations. A disagreement tells you where to slow down.

**Evidence boundary.** The authority is
[`000-seed.hex0` at 7d7e1996d1753118181d43e1a413960d3a1ec24b](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0).
Every instruction below was compared with those bytes and bounded GNU
objdump 2.44 disassembly. State traces and output requests are checked
static derivations. No seed execution, build, or compiler reproduction is
claimed. Assume valid stacks, readable token bytes of the supplied length,
sufficient writable storage, valid execution targets, and the earlier
input and Linux contracts. The parser adds no memory-bound validation.

Cells are 64 bits, stored little-endian; logical stack tops are at the
right. `U` means the all-ones cell, `0xFFFFFFFFFFFFFFFF`. `D` denotes a
data stack while interpreting or running a completed word; `C` denotes
that same physical stack during compilation. They are phase labels, not
two simultaneously allocated stacks. `R` is the separate native return
stack. STATE is a mode cell, HERE a dictionary-write cursor, and LAST_FOUND
a header-address cell. None is a data-stack depth.

Instruction ranges below are **half-open hexadecimal file offsets**.
Add `0x400000` for mapped instruction addresses. Numeric input, lengths,
and accumulated values are decimal unless marked otherwise.

| Body | File range | Bytes |
|---|---|---:|
| `parse_decimal_code` | `[0x644,0x699)` | 85 |
| `repl` | `[0x699,0x6EC)` | 83 |

Neither routine has a dictionary header. Chapter 15 owns all the seed's
headers; there are no extra name, flag, or link bytes to count here.

## A parser consumes a pair and returns a pair

The [decimal helper](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L633-L662)
implements `( c-addr u -- n true | 0 false )`. It accepts a nonempty
sequence of ASCII bytes `0` through `9`. It handles unsigned decimal only:
no leading sign, no base prefix, and no spaces inside the supplied token.
Leading zeroes are allowed. Success means every supplied byte passed that
syntax check; it does not mean an arbitrarily large integer fit in a cell.

The helper is not a dictionary word. The seed's `[lit]` calls it after
`read_word` has already read the whole token into memory. The parser reads
that memory; it performs no input syscall and returns no suffix length.

```text
offset range  bytes                         decoded instruction
[0644,0648) 48 8B 75 00                       mov rsi, qword [rbp]
[0648,064C) 48 83 C5 08                       add rbp, 8
[064C,064F) 48 85 FF                          test rdi, rdi
[064F,0651) 74 38                             jz 0x400689
[0651,0654) 48 31 C0                          xor rax, rax
[0654,0657) 48 89 F9                          mov rcx, rdi
[0657,065B) 48 0F B6 16                       movzx rdx, byte [rsi]
[065B,065F) 48 83 EA 30                       sub rdx, 0x30
[065F,0661) 78 28                             js 0x400689
[0661,0665) 48 83 FA 09                       cmp rdx, 9
[0665,0667) 7F 22                             jg 0x400689
[0667,066B) 48 8D 04 80                       lea rax, [rax+rax*4]
[066B,066E) 48 01 C0                          add rax, rax
[066E,0671) 48 01 D0                          add rax, rdx
[0671,0674) 48 FF C6                          inc rsi
[0674,0677) 48 FF C9                          dec rcx
[0677,0679) 75 DE                             jnz 0x400657
[0679,067D) 48 83 ED 08                       sub rbp, 8
[067D,0681) 48 89 45 00                       mov qword [rbp], rax
[0681,0688) 48 C7 C7 FF FF FF FF              mov rdi, -1
[0688,0689) C3                                ret
[0689,068D) 48 83 ED 08                       sub rbp, 8
[068D,0695) 48 C7 45 00 00 00 00 00           mov qword [rbp], 0
[0695,0698) 48 31 FF                          xor rdi, rdi
[0698,0699) C3                                ret
```

### Recover the stack before following the digits

Start before token input with `D=[88,99]`, `rdi=99`, `rbp=P`, and
`[P]=88`. Let `T=0x412800` be the token buffer address. Reading `407`
produces the parser's entry state:

```text
D = [88,99,T,3]
rdi = 3       rbp = P-16
[P-16] = T    [P-8] = 99    [P] = 88
```

The first load copies T to `rsi`; the following ADD advances `rbp` to
P-8. That consumes the address cell from the live stack while preserving
the address in a cursor register. RDI still holds the length. The parser
will replace that length with a flag and reserve one under-top slot for
the value. At its return boundary it will have replaced two input cells
with two output cells, leaving all older data in place.

The empty test comes before accumulator/count initialization and before
any byte load. For nonempty input, XOR makes `rax=0` and MOV makes
`rcx=u`. Thus RAX is the running value, RSI the next byte's address, and
RCX the remaining count. RDI is not the accumulator.

### Two signed branches enforce a byte grammar

MOVZX reads one byte and zero-extends it into the full RDX register,
giving a value from 0 to 255. SUB subtracts ASCII `0`, hexadecimal 30.
The resulting mathematical range is -48 through 207, all representable as
signed 64-bit values. JS takes the failure branch when that result is
negative. For example, `/` is `0x2F`; its subtraction produces -1,
represented by U, and JS rejects it.

After that branch is passed, the remaining candidates lie between zero
and 207. CMP compares the candidate with nine; signed JG rejects values
greater than nine. `:` is `0x3A`, becomes ten, and fails here. Both range
branches land at `0x400689`. Their use of signed conditions is compatible
with an unsigned-decimal grammar because the zero-extension and bounded
subtraction establish this small signed range first.

For an accepted digit, LEA computes `rax + 4*rax`. The brackets denote an
address-form calculation here, not a memory read. Doubling that result
with ADD gives ten times the old value; the next ADD includes the digit.
No multiply instruction or scratch accumulator is needed. All three
calculations keep the low 64 bits.

Only after acceptance do INC and DEC advance RSI and reduce RCX. JNZ
uses the zero flag from **DEC RCX**, the last flag-writing instruction,
so it asks whether more supplied bytes remain. It does not branch on
the numeric value, a carry from addition, or the current character.
Its signed one-byte displacement is `0xDE=-34`:
`0x400679-34=0x400657`, the byte-load instruction.

### Work through 407

Predict the accumulator after the middle digit zero before reading the
table. Multiplying the old four by ten is still required.

| Completed step | Accepted digit | RAX calculation | RSI | RCX |
|---|---:|---|---|---:|
| Nonempty setup | none | 0 | T | 3 |
| First iteration | 4 | `0*5=0; 0*2+4=4` | T+1 | 2 |
| Second iteration | 0 | `4*5=20; 20*2+0=40` | T+2 | 1 |
| Third iteration | 7 | `40*5=200; 200*2+7=407` | T+3 | 0 |

RCX zero makes JNZ fall through. SUB reserves P-16 again, and the store
overwrites the old address slot with 407. The seven-byte MOV instruction
sign-extends its immediate `FFFFFFFF` into the 64-bit all-ones flag:

```text
D = [88,99,407,U]
rdi = U       rbp = P-16
[P-16] = 407  [P-8] = 99    [P] = 88
```

The old input pointer has been consumed; the token bytes remain in memory.
Neither 99 nor 88 has moved or changed. RET uses this helper call's native
return destination. It does not consume the value/flag pair on the data
stack. `[lit]` will test and remove the flag separately.

The loop invariant explains other lengths: after k accepted bytes,
`rsi=T+k`, `rcx=u-k`, and RAX is the decimal value of that prefix modulo
`2^64`. Keep the words “accepted” and “modulo” in the statement. They
matter at both boundaries below.

## Failure and wrapping are different outcomes

### Empty input and a bad byte

For `u=0`, the initial test jumps directly to failure. RSI has received T,
and `rbp` has advanced once, but no token byte has been loaded. RAX and
RCX have not received the nonempty-path initializations; do not assign
them zero merely because the eventual result is zero. The failure tail
reserves the value slot, explicitly stores a full-cell zero there, and
clears RDI. The result is `[88,99,0,0]`, at the same final stack pointer
as the successful pair.

Now give the helper `12x4`, length four. The first two iterations establish
RAX=12, RSI=T+2, RCX=2. Loading `x` gives 120; subtracting 48 gives 72.
JS is not taken, but `72>9` takes JG. The cursor still points at `x` and
the count is still two because the INC/DEC pair was not reached. The
failure tail returns **zero and false**, not twelve and false. Its
explicit zero store discards the prefix result for the caller.

This local cursor position says nothing about unread standard input.
`read_word` already collected all four bytes, including the last `4`.
Failure does not put `x4` back into the input stream. In this seed's actual
caller, `[lit]` then follows its fatal path rather than resuming token
reading. Confusing the memory cursor with the input stream would predict
a second token that does not exist.

### Twenty valid digits can overflow

There is no overflow check. Neither carry nor overflow from accumulator
arithmetic selects failure. For the all-digit token
`18446744073709551616`, the mathematical integer is exactly `2^64`.
Before its final digit, RAX holds 1844674407370955161. The final iteration
calculates:

```text
LEA, times five:   9223372036854775805
ADD, times two:   18446744073709551610 = 2^64 - 6
ADD, digit six:   18446744073709551616 becomes 0 modulo 2^64
```

All twenty bytes pass the digit checks. The derived result is `[0,U]`,
with RSI=T+20 and RCX=0. It is a successful syntax conversion with a
wrapped cell value. The distinct token `0` also returns `[0,U]`; empty
input instead returns `[0,0]`. Testing the value in place of the flag
would incorrectly reject both successful zero results.

For every accepted token the recurrence is
`n_next=(10*n+digit) modulo 2^64`. It preserves an exact unbounded decimal
integer only while that integer fits in the cell. Acceptance of every
digit does not establish exact unbounded-integer preservation. This is a
limit of the contract, not a hidden rejection path.

## The final loop decides what a found name means now

The [REPL](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L664-L689)
is entered by startup's jump. It never returns to startup. Its name does
not guarantee an interactive prompt, echo of successful input, or printing
of the stack; no such operations appear in this loop.

```text
offset range  bytes                         decoded instruction
[0699,069E) E8 23 FD FF FF                    call read_word
[069E,06A1) 48 85 FF                          test rdi, rdi
[06A1,06A7) 0F 84 93 FB FF FF                 jz bye_code
[06A7,06AC) E8 57 FC FF FF                    call find_code
[06AC,06AF) 48 85 FF                          test rdi, rdi
[06AF,06B1) 75 0F                             jnz 0x4006C0
[06B1,06B6) E8 A3 FD FF FF                    call report_token
[06B6,06BA) 48 8B 7D 00                       mov rdi, qword [rbp]
[06BA,06BE) 48 83 C5 08                       add rbp, 8
[06BE,06C0) EB D9                             jmp 0x400699
[06C0,06C8) 48 8B 04 25 18 30 41 00           mov rax, qword [LAST_FOUND]
[06C8,06CC) 0F B6 48 08                       movzx ecx, byte [rax+8]
[06CC,06CF) F6 C1 01                          test cl, 1
[06CF,06D1) 75 14                             jnz 0x4006E5
[06D1,06D9) 48 8B 04 25 00 30 41 00           mov rax, qword [STATE]
[06D9,06DC) 48 85 C0                          test rax, rax
[06DC,06DE) 74 07                             jz 0x4006E5
[06DE,06E3) E8 8A FE FF FF                    call compile_call
[06E3,06E5) EB B4                             jmp 0x400699
[06E5,06EA) E8 CA FC FF FF                    call execute_code
[06EA,06EC) EB AD                             jmp 0x400699
```

The fixed cells are LAST_FOUND=`0x413018` and STATE=`0x413000`.
Symbolic destinations are `read_word=0x4003C1`, `bye_code=0x40023A`,
`find_code=0x400303`, `report_token=0x400459`,
`compile_call=0x40056D`, and `execute_code=0x4003B4`.

### Read, test length, then find

Reading adds the address/length pair above any earlier data. TEST examines
the cached length. Zero jumps to `bye_code`, whose contract is Linux
`exit(0)`. This branch occurs before lookup, before the flags test, and
before any STATE read. No stack cleanup is needed for a process that
exits. Follow Chapter 15's input contract for what the reader reports;
this branch is not an independent input-error diagnosis.

For nonzero length, `find` consumes the pair and leaves one xt or zero.
On a successful match it also writes the matched **header address** to
LAST_FOUND. The xt is the code address after that header's name. These
two addresses serve different jobs: execute uses the xt, while dispatch
needs the header to find its flags byte at offset eight.

The branch at 06AF separates successful lookup from a miss. Only success
reaches the LAST_FOUND load. A miss can leave LAST_FOUND holding an older
hit; the REPL does not consult that stale value on the miss path.

### A miss restores the older top after reporting

Start this iteration with `D=[88,99]`, `rdi=99`, `rbp=P`. For an unknown
`wobble`, reading produces `[88,99,T,6]` with `rbp=P-16`; lookup produces
`[88,99,0]` with `rbp=P-8`. The saved 99 is now at `[rbp]`.

`find` leaves the token buffer and its length in RBX available to
[`report_token`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L468-L483).
That routine appends question mark and newline and requests a write of
`wobble?\n` to stdout. This is an output request under the earlier syscall
contract, not a guarantee of a complete successful write.

Crucially, reporting loads `rdi=1` as the stdout descriptor and does not
restore it. After the call, RDI must not be mistaken for the original
Forth zero or the older 99. The explicit MOV at 06B6 reloads 99 from
`[rbp]`; the ADD then restores `rbp=P`. Together they discard the temporary
lookup-result position and recover `[88,99]` despite the clobber. Doing
that cleanup before reporting would expose 99 in RDI only to overwrite
it with the descriptor. A call can respect the intended logical outcome
without preserving every register throughout its work.

The jump at 06BE reads the next token. There is **no bare-number fallback**:
it never calls `parse_decimal_code`. Unless a dictionary entry has that
name, bare `407` follows this same miss path. `[lit] 407` instead succeeds
because a found word explicitly reads and parses the next token.

### Immediate first, mode second

After a hit, MOVZX loads the one-byte flags field into ECX, clearing the
rest of that 32-bit destination and therefore the high half of RCX.
TEST examines **bit zero**, not whether the whole flag byte is nonzero.
If that bit is set, JNZ reaches execution without loading STATE. Otherwise
the loop loads STATE; zero selects execution, any nonzero value selects
`compile_call`.

| Immediate bit | STATE | REPL action with the xt |
|---|---|---|
| Set | Not consulted | Execute now |
| Clear | Zero | Execute now |
| Clear | Nonzero | Emit a future CALL |

This is a dispatch decision, not a restriction on what the executed word
may do. An immediate word may itself read STATE and emit bytes. `[lit]`
does exactly that; `;` emits a return byte and clears STATE.

On the compile path, `compile_call` consumes the xt, writes five bytes at
HERE, and advances HERE by five under Chapter 16's preconditions. It
returns to `0x4006E3`, whose jump restarts the loop. On the execute path,
the CALL saves `0x4006EA` on R. `execute_code` removes the xt from the
data stack and tail-jumps to its body. An ordinarily returning body uses
that existing native return address, then the jump at 06EA restarts the
loop. A word such as `bye` exits instead; the loop does not force a return.

## Four traces keep the phases separate

Each row sequence below is a static prediction. Its stated starting stack
is independent of the other traces unless the text says otherwise.

**Interpret an ordinary `+`.** Start `D=[99,7,3]`, STATE=0,
HERE=`0x401021`. Reading produces `[99,7,3,T,1]`; lookup produces
`[99,7,3,0x4001B7]` and LAST_FOUND=`0x4001AC`. The immediate bit is clear
and STATE is zero. Execute removes the xt, restoring three as cached top;
`plus_code` combines seven and three. At the next iteration D=`[99,10]`.
Neither this dispatch nor addition changes HERE or STATE.

**Compile that same `+`.** Resume Chapter 16's `lift` construction with
C=`[99]`, STATE=1, HERE=`0x40101B`. Reading and lookup temporarily give
`[99,T,1]` and `[99,0x4001B7]`. The same clear immediate bit now reaches
the compile path. Its bytes are `E8 97 F1 FF FF`, with displacement
`0x4001B7-0x401020=-3689`. HERE becomes `0x401020`; C returns to `[99]`;
STATE stays one. No addition happens to C. Later, when the completed word
runs, its separately considered D supplies the operands.

**Execute an immediate `[lit]`.** Earlier in that construction, take
C=`[99]`, STATE=1, HERE=`0x40100E`, with input `[lit] 3` next. Lookup of
`[lit]` yields xt=`0x4005C1`, header=`0x4005B2`, and flag byte one.
The REPL skips its STATE test and executes the word now. That word reads
`3` itself, gets `[3,U]` from the parser above C, removes the flag, then
checks STATE internally. It emits CALL `lit_code` plus the eight-byte
cell three. HERE becomes `0x40101B`, C returns to `[99]`, and STATE stays
one. The outer loop never sees `3` as its next lookup token. In interpret
mode the same immediate dispatch instead leaves three on D and emits
nothing, because `[lit]` takes its own other branch.

**Miss while compiling.** At C=`[99]`, STATE=1, HERE=`0x40101B`, read an
unknown `wobble`. The report-and-cleanup path restores C and loops. STATE
remains one, HERE remains `0x40101B`, and the earlier header and literal
remain written. Subsequent `+ ;` can still append the call and return,
ending at HERE=`0x401021`, STATE=0. The unknown word was reported and
skipped; there was no rollback of the definition or automatic cancellation
of compile mode. The source author must not treat continuation as evidence
that the intended word was compiled.

## Exit status does not validate a definition

Contrast three routes rather than merging all bad input into one error.
An unknown dictionary name takes the report-and-continue route just shown.
A bad token consumed by
[`[lit]`](https://github.com/delta9000/seed-forth/blob/7d7e1996d1753118181d43e1a413960d3a1ec24b/000-seed.hex0#L582-L600)
takes another route: for `[lit] 12x4`, the parser returns zero and false;
`[lit]` tests the false flag and jumps to `fatal_token`. It reports the
whole token and invokes `exit(2)`. It does not compile a successful literal
or return to the loop for a later `bye`. Earlier writes are not undone by
this path either; the process exits.

Ordinary end of input takes the REPL's early `exit(0)` branch. Consider
`: half [lit] 3` followed by EOF, starting with HERE=`0x401000` and
C=`[99]`. Colon writes the fourteen-byte `half` header; `[lit]` emits its
thirteen bytes. HERE is `0x40101B` and STATE is still one. The next read
returns length zero and the loop exits without checking STATE. No
semicolon ran and no final C3 was appended. Status zero here records this
exit route; it is not a completeness check on the unfinished definition.

These outcomes follow the explicit branches. They do not require inventing
an abort stack, rollback log, numeric fallback, or validation pass.

## Close the file-byte path honestly

The last instruction occupies `[0x6EA,0x6EC)`: `EB AD`. AD as a signed
byte is -83, so the instruction-end address `0x4006EC` plus -83 returns
to `0x400699`. Its final stored byte is at offset `0x6EB`. Offset `0x6EC`
is the exclusive end, not an additional byte. The two bodies cover exactly
`0x6EC-0x644=168` bytes.

Together with the preceding audit units, that closes the partition of
1,772 source-derived file bytes. Complete static coverage establishes that
every file region has an assigned explanation and source-matched fields
or instruction rows, including these final branches. It makes the byte
claims inspectable. It does not prove every possible execution correct,
make malformed stacks or addresses safe, or establish that all source
programs implement their authors' intentions.

The reasoning still relies on the stated x86-64 semantics, Linux/loader
contracts, accurate source and tool observations, and each example's
preconditions. Newly emitted dictionary bytes are derived process-memory
layouts, not more bytes in this file. No execution trace, compiler build,
bootstrap comparison, or real-reader learning result follows from finishing
a disassembly. [Chapter 19](19-audit-synthesis-and-capstone.md) will combine
the audited mechanisms and evidence boundaries into a whole-seed capstone.

## Practice

Use the [separate hints and solutions](../practice/18-solutions.md) after
an attempt. For each answer, mark whether you predicted it independently,
used a hint, or reconstructed it from the worked trace; then try the
changed case without the solution open.

### S18-01 — Keep digits and stack slots separate

Before reading `407`, let D=`[88,99]`, `rbp=P`, and `rdi=99`. Give the
parser's entry slots, RAX/RSI/RCX after each digit, and both returned cells.
Which input slot is overwritten, and why is the final `rbp` unchanged from
the parser's entry? Explain the JNZ flag source.

### S18-02 — Reject the whole token

Trace `12/9`, `12:9`, and empty input. For each, identify the first failure
branch, cursor/count facts actually established, and returned pair. Does
an unexamined suffix remain in standard input? Why can the byte checks
use JS and signed JG even though the accepted number syntax is unsigned?

### S18-03 — Separate acceptance from exactness

Compare tokens `0`, `18446744073709551615`, and
`18446744073709551616` with empty input. Give each value/flag pair. Derive
the last token's final iteration and explain why testing only its returned
value would be wrong. Is a successful flag an overflow check?

### S18-04 — Dispatch one name at two times

Trace ordinary `+` once with D=`[99,7,3]`, STATE=0, HERE=`0x401021`, then
with C=`[99]`, STATE=2, HERE=`0x40101B`. Include header versus xt, final
stack, and HERE. Follow the compile case with immediate `;`. Which STATE
read is skipped? For hypothetical flag bytes `02` and `03`, which one
sets the immediate bit?

### S18-05 — Explain continuation and termination

Start at HERE=`0x401000`, STATE=0, C=`[99]`, and read
`: half [lit] 3 wobble` followed by EOF; assume `wobble` is absent. Trace
the miss's physical cleanup, requested report, HERE, STATE, and exit
route. Did it undo the partial definition or supply its return? Contrast
`[lit] 12x4 bye` with bare `12x4 bye` in interpret mode, assuming no
`12x4` dictionary entry. State which predictions remain unexecuted.
