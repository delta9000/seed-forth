# 16. The native colon compiler

[Previous: Dictionary and token input](15-dictionary-and-token-input.md) · [Practice help](../practice/16-solutions.md) · [Remaining route](../../COVERAGE.md)

A definition becomes bytes before it becomes behavior. When the input says
`: lift [lit] 3 + ;`, the seed must preserve the name, arrange a future push
of three, arrange a future addition, and finish with a return. Meanwhile,
any older values on the compiling stack must survive. Which instruction
owns each of those jobs?

We will open five bodies totaling **237 bytes**. By the end, you should be
able to derive one complete dictionary entry, explain the two different
uses of the data stack, and follow an inline literal through the native
return stack without leaving a stray address behind.

## Bring the contracts and choose your route

[Chapter 8](08-defining-words-and-phases.md) supplies the three defining
phases; [Chapter 9](09-control-flow-by-patching.md) separates compile-time
work from runtime work; [Chapter 10](10-storage-deferred-words-and-bytes.md)
explains borrowed token storage. Use the file/address coordinates of
[Chapter 11](11-executable-and-entry.md), the physical stack of
[Chapter 12](12-physical-stacks-and-memory.md), and the operand widths of
[Chapter 13](13-arithmetic-in-instruction-bytes.md). The preceding chapter
owns dictionary headers, lookup, token input, and the comma writer.

Check two prerequisites. If HERE holds `0x401000` and a name has four bytes,
where does its body start? If a native call starts at `A`, does its saved
return address point at `A`, `A+4`, or `A+5`? The answers are `0x40100E`
and `A+5`. Revisit the corresponding contract if either is uncertain.
Experienced readers can attempt S16-02 and S16-04 first, then use the
listings to explain any discrepancy.

**Evidence boundary.** This is a static audit of the Linux/x86-64 seed at
[revision bbcc1732152af2d884737272eed870d2410ffe8e](https://github.com/delta9000/seed-forth/tree/bbcc1732152af2d884737272eed870d2410ffe8e).
The listings were compared with the source bytes and bounded GNU objdump
2.44 disassembly. Traces and generated layouts are checked manual
derivations, not observed executions. No seed execution or build is needed.

Cells are eight bytes; stored multibyte values are little-endian. Both
logical stack tops appear at the right. `C` labels the data stack during
compilation and `D` labels it during later execution: they are the same
physical stack at different times. `rdi` caches its top; `rbp` points to the
next cell below it. `R` is the separate native return stack using `rsp`.

Assume valid stacks, trusted input within the token reader's bounds,
nonoverlapping readable name bytes and writable dictionary storage,
sufficient capacity, no pointer wrap, and valid executable destinations.
Names in successful examples contain 1–255 bytes. The forward copy also
requires `DF=0`, examined below. These are preconditions, not new checks
inside the compiler.

Each instruction row gives a **half-open hexadecimal file-offset range**.
Add `0x400000` to obtain the corresponding virtual address. By contrast,
the generated `lift` layout later uses explicitly labeled virtual addresses.
Headers are accounted for in Chapter 15, not counted again here:

| Body/helper | File range | Bytes |
|---|---|---:|
| `colon_code` | `[0x4ED,0x53F)` | 82 |
| `semicolon_code` | `[0x54A,0x56D)` | 35 |
| `compile_call` | `[0x56D,0x593)` | 38 |
| `lit_code` | `[0x5A0,0x5B2)` | 18 |
| `bracket_lit_code` | `[0x5C1,0x601)` | 64 |

Symbolic call/jump targets in the listings resolve to these virtual
addresses: `read_word=0x4003C1`, `parse_decimal_code=0x400644`,
`fatal_token=0x400477`, `compile_call=0x40056D`, and
`comma_code=0x400383`. Each relative transfer uses the address after its
own instruction as the origin, including the five-byte final tail jump.

## Keep the three phases visible

These are the machine mechanisms behind Chapter 8's `constant` example:

1. **Make `constant`.** The first source colon runs `colon_code` to create
   its header. The second colon is an ordinary word encountered in compile
   mode, so `compile_call` emits a future call to `colon_code`. Immediate
   `[lit] 0` emits a future literal; immediate `;` appends a return
2. **Use `constant` to make `seven`.** That saved call now executes
   `colon_code`, which reads `seven` and preserves the supplied value.
   The already-compiled body emits seven's push template and resets STATE.
   Its compiled literal executes `lit_code`; it does not read fresh input
3. **Run `seven`.** Its emitted push body returns seven. It reads no name
   and changes neither HERE nor LATEST. That particular body uses the
   library's direct push template, not the inline-literal layout below

STATE steers token dispatch; it does not intercept every executing machine
instruction. Otherwise phase 2 could not run its writers after colon set
STATE to one. Conversely, seeing `:` in source does not always mean that
colon executes immediately. Its header's immediate bit is clear; `;` and
`[lit]` have that bit set.

Our smaller recurring definition exposes the same building blocks without
repeating the whole defining-word program:

```forth
: lift [lit] 3 + ;
```

For this paper model, start with HERE=`0x401000`, LATEST=`0x400617`, STATE=0,
and `C=[99]`. Those system values match the seed's initial dictionary;
99 is a stipulated earlier data value. No library words are needed. Later
we will call `lift` with a separate runtime input. Compiling its `+` must
not add three to the compiling 99.

## Colon: preserve the name and restore the old data stack

The [complete `colon_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L520-L536)
is 82 bytes. Symbolic system-cell operands abbreviate fixed addresses:
STATE=`0x413000`, LATEST=`0x413008`, HERE=`0x413010`.

```text
offset range  bytes                                decoded instruction
[04ED,04F2) E8 CF FE FF FF                          call read_word
[04F2,04FA) 48 8B 0C 25 08 30 41 00                 mov rcx, qword [LATEST]
[04FA,0502) 48 8B 14 25 10 30 41 00                 mov rdx, qword [HERE]
[0502,0505) 48 89 0A                                mov qword [rdx], rcx
[0505,0509) C6 42 08 00                             mov byte [rdx+8], 0
[0509,050D) 40 88 7A 09                             mov byte [rdx+9], dil
[050D,0515) 48 89 14 25 08 30 41 00                 mov qword [LATEST], rdx
[0515,0518) 48 89 F9                                mov rcx, rdi
[0518,051C) 48 8B 75 00                             mov rsi, qword [rbp]
[051C,0520) 48 8D 7A 0A                             lea rdi, [rdx+10]
[0520,0522) F3 A4                                   rep movsb
[0522,052A) 48 89 3C 25 10 30 41 00                 mov qword [HERE], rdi
[052A,052E) 48 8B 7D 08                             mov rdi, qword [rbp+8]
[052E,0532) 48 83 C5 10                             add rbp, 16
[0532,053E) 48 C7 04 25 00 30 41 00 01 00 00 00     mov qword [STATE], 1
[053E,053F) C3                                      ret
```

The first call consumes an input token, not a data operand. `read_word`
returns `( -- c-addr u )`, preserving earlier data. Let the incoming
`rbp=P`, `rdi=99`, and let `T` be the token buffer address. After reading
`lift`, the physical stack is:

```text
C = [99, T, 4]
rdi = 4       rbp = P-16
[P-16] = T    [P-8] = 99
```

The first three stores construct the fixed part of the new header. The
old LATEST goes at the entry's beginning, the flags byte becomes zero, and
`dil`, the low byte of four, supplies the name length. This byte store does
not copy the name. The `40` REX prefix selects `dil` in this encoding;
`48` on the link store selects a full-cell operation instead.

The code keeps two uses of the length separate. Storing DIL writes one
byte at entry+9; moving RDI to RCX supplies the full register as the copy
count. Under the token reader's 255-byte bound these agree. The one-byte
store itself is not a length check. Nor does colon write a zero byte after
the name: that next location is where native code will begin.

Now follow groups with one causal job each:

| Completed group | Register/stack fact | Dictionary and state fact |
|---|---|---|
| Read name, `04ED` | `rdi=4`, `rbp=P-16` | No new header yet |
| Load and write fixed fields, `04F2–050D` | `rdx=0x401000` | Link=`0x400617`, flags=0, length=4 |
| Publish entry, `050D` | Data slots still hold T and 99 | LATEST=`0x401000` |
| Set copy operands, `0515–0520` | `rcx=4`, `rsi=T`, `rdi=0x40100A` | Destination starts after ten fixed bytes |
| Copy, then save cursor, `0520–052A` | `rcx=0`, `rdi=0x40100E` | Name copied; HERE=`0x40100E` |
| Restore data and mode, `052A–053E` | `rdi=99`, `rbp=P`, `C=[99]` | STATE=1; LATEST unchanged |

`lea` computes the destination address; it does not load a value stored
there. During the copy, `rdi` has been borrowed as a destination pointer,
so it temporarily ceases to represent the Forth top. The saved 99 at
`[rbp+8]` makes restoration possible. Advancing `rbp` by sixteen removes
both token-result slots. The final RET consumes this colon invocation's
return destination, without consuming 99.

### Why the copy runs forward

`F3 A4` is REP MOVSB. Here it copies bytes from `rsi` to `rdi`, counting
with `rcx`; with **DF=0**, each copied byte advances both pointers. Four
iterations copy `6C 69 66 74`, leave `rcx=0`, and advance the destination
from `0x40100A` to `0x40100E`. Intel's
[MOVS and REP entries](https://cdrdv2-public.intel.com/868141/253667-089-sdm-vol-2b.pdf#page=113)
specify the direction dependence and the default 64-bit address/count
registers. REP does not clear DF.

The [AMD64 ABI, draft 0.99.6, §3.4.1, Table 3.5](https://refspecs.linuxbase.org/elf/x86_64-abi-0.99.pdf#page=29)
specifies DF=0 at process initialization. This is the process-entry
precondition supporting the forward-copy model, which must remain true
when colon is called. **The shown body does not execute CLD.** We do not
attribute the initial flag value to seed startup instructions or assume
arbitrary added native code preserves it. With DF=1, the second byte would
use `T-1` and `0x401009`, already entering the header rather than finishing
the name.

Colon trusts the reader's length and the caller's storage arrangements.
It neither rejects a zero-length result itself nor checks capacity or
rolls back partially written state. LATEST changes before the name copy
and before any body exists. There is no transaction or hidden “complete”
bit. A valid-looking header is not evidence of a callable completed word.

## compile_call: emit a distance, then consume only the xt

The [38-byte helper](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L551-L562)
is not a dictionary word. The outer loop's ordinary compile path and
`[lit]` share it. Its contract is `( prefix xt -- prefix )`, with five
bytes appended at HERE. It does not read STATE or modify LATEST.

```text
offset range  bytes                                decoded instruction
[056D,0575) 48 8B 04 25 10 30 41 00                 mov rax, qword [HERE]
[0575,0578) C6 00 E8                                mov byte [rax], 0xE8
[0578,057C) 48 83 C0 05                             add rax, 5
[057C,057F) 48 29 C7                                sub rdi, rax
[057F,0582) 89 78 FC                                mov dword [rax-4], edi
[0582,058A) 48 89 04 25 10 30 41 00                 mov qword [HERE], rax
[058A,058E) 48 8B 7D 00                             mov rdi, qword [rbp]
[058E,0592) 48 83 C5 08                             add rbp, 8
[0592,0593) C3                                      ret
```

Let the incoming cursor be `A` and target be `T`. After writing E8 at A,
the helper makes `rax=A+5`. SUB replaces the cached xt by `T-(A+5)`.
The following store writes its **low 32 bits** at `rax-4`, which is A+1.
It fills exactly the four bytes after E8; `FC` encodes displacement -4.
The absence of REX.W on `89 78 FC` matters: this store is four bytes, not
eight. Updating HERE finishes the instruction; reloading the old next
cell and advancing `rbp` consumes exactly one xt.

For the literal call in `lift`, set A=`0x40100E`, T=`0x4005A0`:

```text
address after call = 0x401013
T - (A+5)          = -0xA73 = -2675
low 32 bits        = 0xFFFFF58D
emitted bytes      = E8 8D F5 FF FF
new HERE           = 0x401013
```

During this particular helper call, the prefix is `[99,3]`. If its entry
has `rbp=Q`, `[Q]=3`, and `[Q+8]=99`, its final state is `rdi=3`,
`rbp=Q+8`, `[rbp]=99`. Neither prefix value was used in the displacement
calculation. This is how a compiler can emit a call while retaining the
value it intends to write immediately afterward.

At runtime, CALL sign-extends the stored displacement and adds it to the
address after the instruction. Thus `0x401013-0xA73=0x4005A0` recovers the
target. This is the [Intel CALL rel32 contract](https://www.intel.com/content/dam/www/public/us/en/documents/manuals/64-ia-32-architectures-software-developer-vol-2a-manual.pdf#page=224).
For our nonwrapping address model, the distance must lie in
`[-2^31, 2^31-1]`. The helper performs **no range check**: storing four low
bytes is not a proof that the sign-extended result reaches the requested
64-bit target. A too-distant target can produce a different destination.

## lit: turn its return address into an inline-data address

The [18-byte `lit_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L568-L575)
does not parse a number or inspect STATE. Its caller must provide an
eight-byte value immediately after the CALL, followed by valid continuation
code. That is a **call-site contract**, additional to the stack effect
`( prefix -- prefix n )`.

```text
offset range  bytes                                decoded instruction
[05A0,05A1) 58                                      pop rax
[05A1,05A5) 48 83 ED 08                             sub rbp, 8
[05A5,05A9) 48 89 7D 00                             mov qword [rbp], rdi
[05A9,05AC) 48 8B 38                                mov rdi, qword [rax]
[05AC,05B0) 48 83 C0 08                             add rax, 8
[05B0,05B1) 50                                      push rax
[05B1,05B2) C3                                      ret
```

Run the completed `lift` on paper with `D=[99,7]`. Its literal call pushes
`S=0x401013`, the inline cell's address. Let `Rbase` include the return
destination of `lift` and any older correctly owned entries:

| Moment | D or physical change | R, top at right |
|---|---|---|
| Before CALL lit | `[99,7]` | `Rbase` |
| Entry to lit | Unchanged | `Rbase, S` |
| POP at `05A0` | `rax=S` | `Rbase` |
| Reserve/save at `05A1–05A9` | Save old top 7 at new `[rbp]` | `Rbase` |
| Load at `05A9` | `rdi=[S]=3`; D becomes `[99,7,3]` | `Rbase` |
| ADD, then PUSH | `rax=S+8=0x40101B` | `Rbase, S+8` |
| RET at `05B1` | Continue at `0x40101B` | `Rbase` |

If `rbp=P` before this call, it finishes at `P-8`, with `[P-8]=7` and
`[P]=99`. Exactly one data value was added. On R, **neither S nor S+8
remains after RET**. PUSH temporarily puts the selected destination there;
RET consumes it. The value cell remains in code memory.

The next instruction calls `+`, leaving `[99,10]`; `lift`'s own final RET
then consumes its own return destination. The literal's adjusted return
and the definition's return are different events. An omitted `add rax,8`
would resume at the value bytes, not at the next intended instruction.

A top-level bare call to `lit`, including a bare interpreted `lit` token,
does not supply this inline cell. A return address exists, but the following
bytes belong to its caller's instructions rather than a promised value
cell. It is not a valid substitute for `[lit] 3`. The same objection applies
to an ordinary compiled call to `lit` without its eight-byte payload.

## [lit]: choose between a present value and future code

The [64-byte immediate body](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L582-L600)
reads the following token itself. Here we use bounded interfaces:
`read_word` preserves the prefix and pushes address/length;
`parse_decimal_code` replaces those with value/flag, also preserving the
prefix. Success gives a nonzero flag; failure gives zero. Exact numeric
parsing belongs to the remaining parser audit in the
[coverage route](../../COVERAGE.md).

```text
offset range  bytes                                decoded instruction
[05C1,05C6) E8 FB FD FF FF                          call read_word
[05C6,05CB) E8 79 00 00 00                          call parse_decimal_code
[05CB,05CE) 48 85 FF                                test rdi, rdi
[05CE,05D4) 0F 84 A3 FE FF FF                       jz fatal_token
[05D4,05D8) 48 8B 7D 00                             mov rdi, qword [rbp]
[05D8,05DC) 48 83 C5 08                             add rbp, 8
[05DC,05E4) 48 8B 04 25 00 30 41 00                 mov rax, qword [STATE]
[05E4,05E7) 48 85 C0                                test rax, rax
[05E7,05E9) 75 01                                   jnz 0x4005EA
[05E9,05EA) C3                                      ret
[05EA,05EE) 48 83 ED 08                             sub rbp, 8
[05EE,05F2) 48 89 7D 00                             mov qword [rbp], rdi
[05F2,05F7) BF A0 05 40 00                          mov edi, 0x4005A0
[05F7,05FC) E8 71 FF FF FF                          call compile_call
[05FC,0601) E9 82 FD FF FF                          jmp comma_code
```

TEST examines the whole returned flag. JZ immediately uses that result,
transferring to `fatal_token` on invalid decimal input. No literal is
emitted on that branch; the fatal path reports the token and exits as
Chapter 15 describes. It does not complete or undo an already-open header.

On success, the load and pointer advance discard the flag, exposing `n`.
A separate TEST examines STATE: zero returns with `n` on the data stack;
any nonzero value selects compilation. The short JNZ's displacement is one
because it skips the one-byte interpret-mode RET: `0x5E9+1=0x5EA`.
Neither flag test means “positive”; both distinguish zero from nonzero.

In compile mode, watch the temporary duplicate of three. Reset to our
post-colon `C=[99]`, `rbp=P`, HERE=`0x40100E`, STATE=1:

| After action | C | `rbp` | HERE |
|---|---|---|---|
| Read token `3` | `[99,T,1]` | P-16 | `0x40100E` |
| Parse successfully | `[99,3,U]` | P-16 | `0x40100E` |
| Drop success flag | `[99,3]` | P-8 | `0x40100E` |
| Reserve/save cached 3 | `[99,3,3]` | P-16 | `0x40100E` |
| Replace cache with lit xt | `[99,3,0x4005A0]` | P-16 | `0x40100E` |
| `compile_call` consumes xt | `[99,3]` | P-8 | `0x401013` |
| Tail-call comma consumes 3 | `[99]` | P | `0x40101B` |

`U` is the all-ones success cell. The `mov edi` uses a 32-bit destination,
which zeroes the upper half of `rdi`; it therefore installs the complete
address `0x00000000004005A0`. While the helper overwrites that cached
address with displacement arithmetic, the saved three remains at `[rbp]`.
Its reload is why comma receives three rather than the xt or displacement.

JMP to `comma_code` adds no return destination. Comma stores the cell at
HERE, advances HERE by eight, restores the older 99, and returns directly
to `[lit]`'s caller. Combined emission is five plus eight, **13 bytes**.
STATE remains one and LATEST remains `0x401000`; 99 survives throughout.
In interpret mode the earlier RET instead leaves `[99,3]`, with no change
to HERE, LATEST, or STATE.

### The next token is an ordinary call

After compile-mode `[lit] 3`, the input loop next reads `+`. Its lookup
produces the existing xt `0x4001B7`; because `+` is ordinary and STATE is
nonzero, the compile path passes `[99,0x4001B7]` to `compile_call`.
The helper writes five bytes beginning at the current `0x40101B`, advances
HERE to `0x401020`, and leaves `[99]`. No addition ran on that stack.

There is consequently no CALL to `bracket_lit_code` in the generated
`lift` body. That immediate word already did its input-reading work.
The CALL to `lit_code` and following cell are its output. There *is* a
CALL to `plus_code`, because that ordinary word's work was deferred.
The different generated forms result from the dispatch contract, not from
how many source characters each word contains.

## Semicolon: append a return, then leave compile mode

The [35-byte `semicolon_code`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L543-L549)
is immediate, so the outer loop executes it while building `lift`:

```text
offset range  bytes                                decoded instruction
[054A,0552) 48 8B 04 25 10 30 41 00                 mov rax, qword [HERE]
[0552,0555) C6 00 C3                                mov byte [rax], 0xC3
[0555,0558) 48 FF C0                                inc rax
[0558,0560) 48 89 04 25 10 30 41 00                 mov qword [HERE], rax
[0560,056C) 48 C7 04 25 00 30 41 00 00 00 00 00     mov qword [STATE], 0
[056C,056D) C3                                      ret
```

Before it runs, the literal and ordinary `+` call have moved HERE to
`0x401020`. Semicolon stores C3 there, advances HERE to `0x401021`, and
sets STATE to zero. Neither `rdi` nor `rbp` changes, so `C=[99]` remains.
LATEST still identifies the `lift` header.

Two returns are present in this explanation. The **stored C3** will end a
later `lift` invocation. The **C3 at file offset 056C** ends this current
semicolon invocation. Writing an instruction byte does not execute it.

Semicolon knows no nesting depth and checks no complete-word invariant.
It does not inspect STATE before writing, validate stack balance, or
resolve forgotten branch patches. Calling it twice would append two bytes
and leave STATE zero. Calling it outside a definition still performs the
store. Its small contract works because source construction supplies the
larger discipline.

## Reconcile every generated byte

For `lift`, the fixed header is eight link bytes plus two one-byte fields.
Its four-byte name gives `10+4=14` header bytes. The body contains a 13-byte
literal, a five-byte addition call, and a one-byte return: `13+5+1=19`.
The whole entry therefore occupies **33 bytes**, ending at `0x401021`.

The addition displacement is independently derived from its own call site:
`0x4001B7-0x401020=-0xE69=-3689`, whose low four bytes are `97 F1 FF FF`.
Reusing the literal's displacement would call the wrong address.

```text
virtual range         bytes                       meaning
[401000,401008) 17 06 40 00 00 00 00 00          link: old LATEST
[401008,401009) 00                               ordinary flags
[401009,40100A) 04                               four name bytes
[40100A,40100E) 6C 69 66 74                      "lift"
[40100E,401013) E8 8D F5 FF FF                   CALL 0x4005A0 (lit)
[401013,40101B) 03 00 00 00 00 00 00 00          inline value three
[40101B,401020) E8 97 F1 FF FF                   CALL 0x4001B7 (+)
[401020,401021) C3                               RET
```

The name ends exactly where the xt begins; there is no zero terminator or
alignment padding. During construction, HERE steps through `0x401000`,
`0x40100E`, `0x40101B`, `0x401020`, and `0x401021`. LATEST changes once,
when colon publishes the header. STATE changes 0→1→0. The compiling data
stack returns to `[99]` after each complete source action. Later execution
with `[99,7]` produces `[99,10]` without advancing HERE.

These 33 bytes are **not part of the original 1,772-byte file**. Its
file-backed range ends at virtual address `0x4006EC`; `0x401000` lies in
the segment's additional memory from Chapter 11. The compiler writes new
process memory there. Subtracting the load base gives the number `0x1000`,
but does not create a file byte at that offset. Accordingly, runtime
headers and code do not increase our static source-audit count.

## Practice

Use paper, the stated bounds, and the [hint/solution companion](../practice/16-solutions.md).
After checking an answer, close it and attempt its changed case.

### S16-01 — Recover the old top after copying

Trace colon for `lift` from `C=[99]`, `rbp=P`. Give the token-result slots,
the copy registers before and after REP, and the two cleanup instructions'
effect. Explain why `[rbp]` cannot replace `[rbp+8]` in the final reload.
What goes wrong with the second byte if DF=1? Identify who supplies DF=0.

### S16-02 — Finish a call without losing its prefix

For HERE=`0x40101B`, target=`0x4001B7`, and C=`[99,target]`, derive all five
emitted bytes, new HERE, and final physical stack. A proposed rewrite
stores `target-HERE` instead of `target-(HERE+5)`: which address would the
resulting call reach? Explain why four-byte storage alone does not check
encodability.

### S16-03 — Follow both literal modes

Start with `[88,99]` and token `3`. Trace `[lit]` with STATE=0, then on a
fresh reset with STATE=2 and HERE=`0x40100E`. Include the returned parser
flag, temporary duplicate, helper consumption, tail-call return, emitted
bytes, and preserved prefix. Explain the path for invalid token `3x`.

### S16-04 — Remove every temporary return address

At `lift`'s literal call, use D=`[99,7]` and R=`Rbase`. Trace every change
to R and the physical data stack until execution resumes at the addition
call. Diagnose changing the address adjustment from eight to seven.
Why does a top-level bare `lit` not satisfy this mechanism's contract?

### S16-05 — Rebuild the entry in a changed layout

On a fresh model with HERE=`0x402000`, LATEST=`0x401000`, STATE=0, and
C=`[88,99]`, define `: boost [lit] 12 + ;`. Derive every header/body range,
both relative displacements, final HERE/LATEST/STATE, and the later result
on D=`[77,8]`. Explain what a second executed semicolon would do and what
it would fail to validate. Keep this a static derivation.

## Stop, check, and continue

The five audited bodies contain 53 instructions and 237 bytes. We have
connected their stores and stack restoration to one complete generated
entry, including the preconditions they leave to their callers. The
intervening fixed dictionary headers remain Chapter 15's responsibility.

For a pause, save this checkpoint: `lift`'s literal starts at `0x40100E`,
its cell starts at `0x401013`, and its continuation is `0x40101B`. On
returning, explain which address is briefly on R at each step. The
[remaining route](../../COVERAGE.md) opens branch bodies, decimal parsing,
and outer-loop dispatch; those mechanisms are not claimed complete here.

**Verification limits.** All 237 source bytes were checked against the
pinned file and statically decoded one body at a time. Address arithmetic,
stack traces, and exercise answers were independently recalculated. This
establishes a bounded account of the inspected implementation, not a build,
a running-system test, a proof of safe arbitrary input, or evidence of
novice learning outcomes.
