# Seed and Forth: compact reference

[Reading route](chapters/00-start-here.md) · [Volume contents](README.md) · [Byte audit](AUDIT.md)

This reference describes `000-seed.hex0` and `010-lib.fth` at
[`bbcc1732152af2d884737272eed870d2410ffe8e`](https://github.com/delta9000/seed-forth/tree/bbcc1732152af2d884737272eed870d2410ffe8e).
It is a lookup companion to the explanations, not a portable Forth specification.

Jump to: [entry and evidence](#entry-and-evidence), [notation](#notation-and-global-preconditions),
[input and modes](#input-and-modes), [all 32 primitives](#all-32-primitives),
[call-site rules](#call-site-and-return-stack-rules), [memory](#seed-memory-map),
[library recovery index](#library-recovery-index), [glossary](#small-glossary).

## Entry and evidence

The native seed target is **Linux/x86-64**, in 64-bit user mode, with
little-endian memory, usable process-stack space, and successful loading
at its fixed addresses. Its ELF segment requests read, write, and execute
permissions. Host policy can reject that request. Reading the manuscript
and following its paper traces requires no installation.

The pinned [`build.sh`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/build.sh)
is the build entry. It runs the assembler selected by `HEX0`, defaulting to
`vendor/stage0-posix/bootstrap-seeds/POSIX/AMD64/hex0-seed`, on
[`000-seed.hex0`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0),
then marks the output executable. The script checks for that assembler
and contains the repository's missing-submodule guidance. This description
is source inspection, not an installation procedure tested here.

The audit's decoded **machine-byte stream** is 1,772 bytes; its SHA-256 is
`697e340e38cabeecbff430d6626e29f4ed3a55498f89d7bda16d8f65e4de774e`.
This identifies bytes obtained from the annotated source. It is not the hash
of the comment-bearing text file, evidence of a new `build.sh` run, or a
record that the executable was launched. See the [edition](../EDITION.md)
and [validation record](../VALIDATION.md) for the distinction between
static decoding, earlier repository CI, and the new unexecuted teaching
examples. Earlier CI success is not a fresh-reader setup test.

The [source's authorship notice](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L1-L17)
credits AI collaboration under human architectural direction and identifies
an MIT license. The [opening](chapters/00-why-inspect-a-seed.md) retains the
original prologue's provenance context and bounds what inspection or
artifact equality establishes.

## Notation and global preconditions

- `( a b -- c )` consumes topmost inputs `a b` and leaves `c`; **b is on top**.
  An older stack prefix is preserved unless an effect says otherwise
- A **cell** is 64 bits, or eight bytes. A byte is eight bits. Addresses
  count bytes; eight consecutive bytes make a little-endian cell
- `x`, `a`, and `b` name cell bit patterns; `addr` names an address; `u` a
  byte count; `xt` a code address. Names describe intended roles, not
  runtime-enforced types
- True from `0=` and the library predicates is the all-ones cell
  `0xFFFFFFFFFFFFFFFF`, conventionally written `-1`; false is zero.
  `0branch` tests zero against **any** nonzero pattern
- Addition and multiplication retain the low 64 bits. `/` is unsigned
  division: the top input is the divisor, and zero is forbidden
- Hexadecimal addresses in this reference are display notation. Source
  literals use `[lit]` followed by **unsigned decimal digits**. There is
  no signed, hexadecimal, or floating literal syntax in that parser

Every contract assumes enough real operands, valid accessible storage,
intact dictionary/call state, and sufficient space. Stores must not damage
live stacks, source buffers, metadata, or code needed afterward. These
primitives generally do not check depth, ownership, or capacity. A failure
to satisfy a precondition does not imply a friendly error or rollback.

## Input and modes

The outer loop reads a token, finds its dictionary entry, then decides
whether to execute it now or emit a call. `STATE=0` selects interpretation;
**any nonzero STATE** selects compilation. The seed sets it to one when
starting a definition. Only **`;` and `[lit]` are initially immediate**:
their flag's low bit makes the loop execute them in either mode. Every other
primitive is ordinary and is compiled as a five-byte native call when
encountered in compile mode. The tables describe each body's effect **when
it executes**, not the effect of merely compiling its name.

This difference matters for input-consuming words. An ordinary `'` or `:`
compiled into another word reads input when that compiled call later runs.
It does not consume the following source token merely because its name
was compiled. Direct `execute` also does not consult STATE or immediacy;
it runs its target under that target's contract.

The reader recognizes ASCII space, tab, LF, and CR as separators. A complete
one-byte token `\` starts a line comment; a complete one-byte token `(`
starts a comment through the next `)`. These are reader actions, not extra
dictionary primitives. Tokens are case-sensitive byte strings, without
an added zero terminator. A successful token has at most 255 bytes; storing
the 256th byte leads to a diagnostic and exit status 2. TIB storage is
borrowed and is overwritten by later reading or reporting.

`[lit] 7` supplies seven; bare `7` goes through ordinary **name lookup**.
Decimal accumulation wraps modulo 2^64 without detecting numeric overflow.
An empty token or a nondigit makes `[lit]` report and exit with status 2.
An unknown outer-loop name instead requests a `?` diagnostic and reading
continues, without undoing earlier definitions or resetting compile mode.
EOF exits with status zero even if a definition is unfinished. `key`
represents both EOF and a read NUL byte as zero, so token input cannot
reliably distinguish them. The [dictionary/input audit][s15] opens the reader paths; [S18
parsing][s18parser] and [S18 dispatch][s18repl] open the numeric and mode decisions.

## All 32 primitives

The **body** column links the exact pinned source range; its number is a
hexadecimal **file offset**. For these file bytes, add `0x400000` to obtain
the execution token. It is not the preceding header's address. Chapter
links open the corresponding body audit. Unless stated, a body does not
consume text input or modify STATE. Arbitrary memory/syscall targets can,
of course, affect other state.

### Stack and memory

| # / word | Data-stack effect when executed | Additional effect or condition | Body / audit |
|---|---|---|---|
| 1 `dup` | `( x -- x x )` | Copy top cell | [`0x0C7`][dup_code] / [S12][s12] |
| 2 `drop` | `( x -- )` | Discard top cell | [`0x0DE`][drop_code] / [S12][s12] |
| 3 `swap` | `( a b -- b a )` | Exchange two cells | [`0x0F5`][swap_code] / [S12][s12] |
| 4 `>r` | `( x -- )` | Borrowed R portion: `( -- x )`; ownership rules below | [`0x10D`][to_r_code] / [S12][s12] |
| 5 `r>` | `( -- x )` | Borrowed R portion: `( x -- )`; current invocation owns x | [`0x125`][r_from_code] / [S12][s12] |
| 6 `r@` | `( -- x )` | Borrowed R portion: `( x -- x )`; copies one cell below its own return address | [`0x13D`][r_at_code] / [S12][s12] |
| 7 `@` | `( addr -- x )` | Read eight bytes | [`0x159`][fetch_code] / [S12][s12] |
| 8 `!` | `( x addr -- )` | Write eight bytes | [`0x168`][store_code] / [S12][s12] |
| 9 `c@` | `( addr -- byte )` | Read one byte, zero-extend to a cell | [`0x188`][cfetch_code] / [S12][s12] |
| 10 `c!` | `( x addr -- )` | Write only x's low byte | [`0x199`][cstore_code] / [S12][s12] |

### Arithmetic and system interface

| # / word | Data-stack effect when executed | Additional effect or condition | Body / audit |
|---|---|---|---|
| 11 `+` | `( a b -- sum )` | Sum modulo 2^64 | [`0x1B7`][plus_code] / [S13][s13] |
| 12 `nand` | `( a b -- x )` | x is the 64-bit complement of bitwise `a AND b` | [`0x1CE`][nand_code] / [S13][s13] |
| 13 `0=` | `( x -- flag )` | All ones if x=0; zero otherwise | [`0x1E6`][zeq_code] / [S13][s13] |
| 14 `/` | `( a b -- quotient )` | Unsigned floor(a/b); b≠0; remainder discarded | [`0x200`][divide_code] / [S13][s13] |
| 15 `*` | `( a b -- product )` | Low 64 product bits; same low result under signed/unsigned interpretation | [`0x21D`][star_code] / [S13][s13] |
| 16 `bye` | Does not return | Linux exit with status zero; does not take a status from D | [`0x23A`][bye_code] / [S14][s14] |
| 17 `emit` | `( x -- )` | Attempt one-byte stdout write of x's low byte; discard syscall result | [`0x254`][emit_code] / [S14][s14] |
| 18 `key` | `( -- x )` | Attempt one-byte stdin read; byte on success, zero at EOF, stale scratch possible on error | [`0x28F`][key_code] / [S14][s14] |
| 19 `syscall6` | `( a b c d e f n -- result )` if returning | Linux syscall n with six argument cells; service determines input/output effects | [`0x2D0`][syscall6_code] / [S14][s14] |

`syscall6` maps a–f to `rdi`, `rsi`, `rdx`, `r10`, `r8`, `r9`, and n to
`rax`; returning `rax` becomes the new cached data top. Unused arguments
still need cells. Results are raw, including negative error values where
the service specifies them; this is not libc's return/`errno` interface.
Some services do not return. The seed's calling convention and Linux's
syscall convention are separate from a System V C function call.

`emit` does not retry or report a failed write. `key` tests only whether
the read result is zero: a negative error follows its nonzero path and
loads the shared scratch byte without establishing that a new byte arrived.
Neither word is a complete robust I/O loop. Raw reading also consumes the
same stdin stream used for source tokens, so a word using `key` changes
what the token reader can read next. See [S7][s7] for progress contracts.

### Dictionary, compilation, and inline operands

| # / word | Data-stack effect when executed | Input / other effect | Body / audit |
|---|---|---|---|
| 20 `find` | `( addr u -- xt-or-0 )` | Compare u name bytes, newest first; success sets LAST_FOUND to header; miss leaves it unchanged | [`0x303`][find_code] / [S15][s15] |
| 21 `here` | `( -- addr )` | Push **value of HERE**, the current emission cursor | [`0x367`][here_code] / [S15][s15] |
| 22 `,` | `( x -- )` | Store eight bytes at HERE; advance HERE by eight | [`0x383`][comma_code] / [S15][s15] |
| 23 `execute` | `( args xt -- results )` | Consume xt, tail-jump to it; remaining effects are target's contract | [`0x3B4`][execute_code] / [S15][s15] |
| 24 `state` | `( -- addr )` | Push **address of STATE cell**, `0x413000` | [`0x497`][state_code] / [S15][s15] |
| 25 `latest` | `( -- addr )` | Push **address of LATEST cell**, `0x413008` | [`0x4BA`][latest_code] / [S15][s15] |
| 26 `'` (tick) | `( -- xt-or-0 )` | Read next token, then `find`; does not execute the result | [`0x4D8`][tick_code] / [S15][s15] |
| 27 `:` | `( -- )` | Read name, write/publish header at HERE, advance HERE past name, set STATE=1 | [`0x4ED`][colon_code] / [S16][s16] |
| 28 `;` **immediate** | `( -- )` | Append C3 (RET), advance HERE by one, set STATE=0 | [`0x54A`][semicolon_code] / [S16][s16] |
| 29 `lit` | `( -- x )` | Read inline eight-byte cell using call's return address; resume after cell | [`0x5A0`][lit_code] / [S16][s16] |
| 30 `[lit]` **immediate** | Interpret: `( -- x )`; compile: `( -- )` | Read decimal token; compile mode emits CALL lit plus eight-byte x, 13 bytes total | [`0x5C1`][bracket_lit_code] / [S16][s16] |
| 31 `branch` | `( -- )` | Jump to absolute destination stored in inline cell | [`0x611`][branch_code] / [S17][s17branch] |
| 32 `0branch` | `( flag -- )` | Zero: jump to inline cell's destination; nonzero: resume after cell | [`0x628`][zbranch_code] / [S17][s17zero] |

Colon assumes writable space, a usable name, and forward byte-copy direction
(DF=0). It has no missing-name, capacity, or completion check and publishes
LATEST before the body exists. Semicolon also has no context check: executed
outside a definition, it still writes a byte and sets STATE=0. These are
mechanisms for constructing definitions, not a validated nesting grammar.

## Call-site and return-stack rules

**Inline operands.** `lit`, `branch`, and `0branch` require more than their
D effects. The call's saved return address must point at an eight-byte
inline operand. For the usual emitted form, a five-byte CALL is followed
immediately by that cell. `lit` reads its value and resumes eight bytes
later. Branch cells hold absolute destinations, not relative distances.
`0branch` consumes its flag on both paths; its nonzero path skips the cell.
Targets and continuation points must be valid code boundaries with compatible
stack/return state. The temporary selected return destination is consumed
by RET; the inline cell stays in code memory.

Typing bare `lit`, `branch`, or `0branch` at the interpreter does not create
that layout. Nor does merely compiling their names, or obtaining their xts
with tick and handing them to `execute`. Those routes supply no promised
inline operand. Use `[lit]` for literals and the library's emission words
for branches. The [branch-body audit][s17branch] accounts for the native
returns. A specially constructed caller must establish the entire layout itself. Native CALL emission stores a signed rel32 distance from the
end of the call; the requested target must fit that range. The emitters do
not check it. See [S8][s8], [S9][s9], and [S16][s16].

**Borrowed return storage.** `>r`, `r>`, and `r@` use the actual x86 return
stack. Their table effects omit each completed primitive invocation's own
short-lived return address. Temporary data must belong to the current
owning invocation and be removed in last-in, first-out order before that
invocation returns, including an early `exit,`. A helper call adds another
return address: `r@` inside that helper skips only its own primitive-call
address, so it sees the helper's return address rather than a parent's
parked value. Balanced helpers may run while a parent's value is parked;
they must preserve that value and its ownership. See [S4][s4].

## Seed memory map

These are **process virtual addresses**, from the pinned
[headers/startup](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L19-L74).
Ranges include their start and exclude their end. The single PT_LOAD segment
covers `[0x400000, 0x1400000)`, 16 MiB. Only its first 1,772 bytes come from
the file; the remainder is initially zero-valued memory under the loader
contract. This describes virtual extent, not measured physical residency.

| Address or range | Seed role |
|---|---|
| `[0x400000, 0x400040)` | ELF header, 64 bytes |
| `[0x400040, 0x400078)` | One program header, 56 bytes |
| `[0x400078, 0x4000BA)` | Entry, sysvar initialization, jump to interpreter loop |
| `[0x4000BA, 0x4006EC)` | Initial dictionary headers, primitive/helper bodies, and loop |
| `[0x4006EC, 0x401000)` | Initially zero-filled gap before initial dictionary cursor |
| `0x401000`, growing upward | Initial HERE; runtime dictionary and library data |
| `0x411000`, growing downward | Initial `rbp`; intended data-stack area is below this address, conventionally `[0x410000, 0x411000)` |
| `0x412000` | Shared one-byte `emit`/`key` scratch |
| `0x412800` | TIB; 256-byte token storage, with reporting able to write two more bytes after a 256-byte failed token |
| `0x413000` | STATE cell: initially 0 |
| `0x413008` | LATEST cell: initially `0x400617`, header of `0branch` |
| `0x413010` | HERE cell: initially `0x401000` |
| `0x413018` | LAST_FOUND cell: initially 0 |
| `0x414000` | Destination selected by library `skip-vm-pages`; not the initial cursor |

The listed dictionary/stack boundaries have no guard or collision checks.
An unchecked cursor or stack pointer can enter another live region.
`skip-vm-pages` assigns HERE to STATE's address plus 4096; it is not a general
allocator and can move the cursor backward if used after that destination
has already been passed. Compiler buffers and generated-program heaps are
outside this seed reference; no compiler or native-C memory layout is implied.

**Value versus address.** `here` pushes the value stored at `0x413010`.
`latest` and `state` instead push addresses of their cells; `latest @`
gets a header pointer and `state @` gets the mode. Library `here-addr`
computes `latest [lit] 8 +`, the address of HERE's cell. This difference
is intentional and edition-specific. See [S2][s2] and [S11][s11].

**Cache versus logical data.** Initially `rdi=0` and `rbp=B=0x411000`,
but D is empty. That zero is a dummy cache value. At completed boundaries
with valid logical depth n, `rbp=B−8n`; when n>0, `rdi` is the real top.
For n≥2, `[rbp]` is the next-deeper real value. The saved dummy at B−8
remains outside logical D. At depth one, `[rbp]` is that dummy, not a
second operand. Dropped memory need not be erased. See [S12][s12].

**Process return stack.** `rsp` is supplied by Linux process startup; the
seed does not initialize it to any fixed address in this map. Calls, returns,
and borrowed temporary values use that separate process stack. Its location
and usable size are not specified by the seed's PT_LOAD fields. D's cached
representation and R's native control entries are different structures.

## Library recovery index

The complete definitions remain in the pinned
[`010-lib.fth`](https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/010-lib.fth).
These links recover their mechanisms without repeating the listing.

| If you need to recover… | Read |
|---|---|
| Stack contracts, literals, composition, operand order | [S1 Values and words](chapters/01-values-and-words.md) |
| HERE indirection; `here-addr` and byte-emitting `c,` | [S2 Addresses and bytes][s2] |
| `and`, `or`, modular subtraction, true versus bit masks | [S3 Bits and subtraction](chapters/03-bits-and-subtraction.md) |
| `over`, `nip`, `rot`, `2dup`, `2drop`, and R ownership | [S4 Return stack and shuffles][s4] |
| Equality, `0<`, bounded ordering, and ASCII classifiers | [S5 Comparisons and characters](chapters/05-comparisons-and-characters.md) |
| `+!`, `-!`, truncating `,4`, full-cell `,8` | [S6 Memory updates and writers](chapters/06-memory-updates-and-writers.md) |
| `open`, `read`, `write`, `close`, `die`; raw errors and partial progress | [S7 Linux I/O][s7] |
| `immediate`, `constant`, push-body emitters, `call,`, `char`, `[char]` | [S8 Defining words and phases][s8] |
| `if,`/`else,`/`then,`, loop fixups, `exit,` | [S9 Control-flow patching][s9] |
| `allot`, `create`, `variable`, `defer`/`is`, `token`, `bytes,`, `s,`, `bytes-eq` | [S10 Storage and byte sequences](chapters/10-storage-deferred-words-and-bytes.md) |

Library `<` tests the sign of modular subtraction, rather than implementing
all signed comparisons correctly across overflow. The shared safe domain
for the ordering family excludes operand differences of magnitude 2^63
or more; S5 states the directional details. `token` returns borrowed TIB
bytes; `s,` copies bytes without adding length or termination. Deferred
words must be bound to valid compatible xts before use. These conditions
are part of the contracts, not optional performance advice.

## Small glossary

- **Dictionary header:** link cell, flags byte, name-length byte, then name
  bytes; its body follows immediately. The xt points to the body, not
  the header. [S15][s15]
- **Immediate:** selected for execution by the outer loop even while
  compiling; distinct from code that runs when the completed word is called.
  [S8][s8]
- **Fixup:** address of an emitted slot whose eventual destination must be
  written later; distinct from that destination's value. [S9][s9]
- **Subroutine threading:** compiled word bodies call native code; the
  processor's call/return instructions perform the dispatch. [S16][s16]
- **Audit region:** one byte range in the [source ledger](source-audit.csv).
  It locates an explanation, not an execution result or a correctness proof

The unnamed reader/error routines, `compile_call`, `parse_decimal_code`,
and `repl` are source routines, not additional dictionary words. Find their
exact ranges in the ledger. For an integrated derivation, use the [S19 capstone](chapters/19-audit-synthesis-and-capstone.md);
to resume the learning route, return to the [volume contents](README.md).

[s2]: chapters/02-addresses-and-bytes.md
[s4]: chapters/04-return-stack-and-shuffles.md
[s7]: chapters/07-linux-io-contracts.md
[s8]: chapters/08-defining-words-and-phases.md
[s9]: chapters/09-control-flow-by-patching.md
[s11]: chapters/11-executable-and-entry.md
[s12]: chapters/12-physical-stacks-and-memory.md
[s13]: chapters/13-arithmetic-in-instruction-bytes.md
[s14]: chapters/14-physical-io-and-exit.md
[s15]: chapters/15-dictionary-and-token-input.md
[s16]: chapters/16-native-colon-compiler.md
[s17branch]: chapters/17-inline-branch-operands.md#four-instructions-replace-a-return-destination
[s17zero]: chapters/17-inline-branch-operands.md#eleven-instructions-consume-the-flag-before-choosing
[s18parser]: chapters/18-decimal-parser-and-repl.md#a-parser-consumes-a-pair-and-returns-a-pair
[s18repl]: chapters/18-decimal-parser-and-repl.md#the-final-loop-decides-what-a-found-name-means-now
[dup_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L81-L85
[drop_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L91-L95
[swap_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L101-L106
[to_r_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L112-L119
[r_from_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L125-L132
[r_at_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L138-L146
[fetch_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L152-L155
[store_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L161-L168
[cfetch_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L174-L177
[cstore_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L183-L190
[plus_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L196-L200
[nand_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L206-L211
[zeq_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L217-L223
[divide_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L229-L238
[star_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L244-L250
[bye_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L256-L260
[emit_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L266-L277
[key_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L283-L299
[syscall6_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L305-L319
[find_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L325-L361
[here_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L367-L372
[comma_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L378-L386
[execute_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L392-L397
[state_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L489-L494
[latest_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L500-L505
[tick_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L511-L514
[colon_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L520-L537
[semicolon_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L543-L550
[lit_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L568-L579
[bracket_lit_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L582-L601
[branch_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L607-L612
[zbranch_code]: https://github.com/delta9000/seed-forth/blob/bbcc1732152af2d884737272eed870d2410ffe8e/000-seed.hex0#L618-L632
