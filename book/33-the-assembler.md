# Chapter 33 — The Assembler: M1 and hex2 in Forth

```text
Missing capability: M2-Planet's output is .M1 text, and turning it into an ELF still takes mescc-tools' M1 and hex2 binaries.
New pattern: a two-pass assembler: expand the macros, walk the text once to place every label, then walk it again to emit.
Artifact after this chapter: 130-asm.fth, an M1 expander and hex2 linker that reads M1 on stdin and writes an ELF to /tmp/asm-out.
Proof link: bootstrap.sh builds M1 and hex2 from mescc-tools' C source with it, so no GCC-built binary is in the chain.
```

Ch 32 ended with a compiler, `cc-out-v1`, whose output is text.
Run it on a C file and you get `.M1`: mnemonics like `mov_rax, %60`,
labels like `:FUNCTION_main`, references like `&GLOBAL_x`.  The
kernel cannot run text.  The tools written to turn it into bytes,
mescc-tools' `M1` and `hex2`, are C programs, so you can compile
them with `cc-out-v1`, and get two more `.M1` files that need `M1`
and `hex2` before they can run.

stage0-posix breaks that loop from below, with hex1, hex2-0 and M0
written in hand-assembled hex.  `verify.sh` breaks it with GCC,
which is the compiler this whole route exists not to trust.  This
chapter breaks it with Forth.  `130-asm.fth` is 785 lines that
load on the seed and `010-lib.fth` alone, read M1 text on stdin,
and write an ELF to `/tmp/asm-out`.  `bootstrap.sh` runs it three
times:

```
  cc-out-v1 (Ch 32) ── compiles M2-Planet ──► self-v1-amd64.M1
  seed-forth + 010-lib.fth + 130-asm.fth ───► cc-out-v2-fasm  (an M2-Planet)
  cc-out-v2-fasm ── compiles mescc-tools ───► M1.M1, hex2.M1
  seed-forth + 010-lib.fth + 130-asm.fth ───► M1, hex2        (two runs)
  M1 + hex2 on self-v1-amd64.M1 ────────────► cc-out-v2 == cc-out-v2-fasm
```

From there on the chain assembles with its own `M1` and `hex2`, and
the last line is the check: the two assemblers, one in Forth and one
in C, give the same 223,515 bytes.

The file is a single program, not a layer of the compiler, and it is
read in source order like every other file in this book.  Source
order puts the buffers first and the macro expander last, although
the expander runs first; the map below says where each piece sits in
the run.

| § | Words | Job in the run |
|---|---|---|
| 3–4 | `asm-load-stdin`, the cursor, `asm-emit-byte`, `asm-write-output` | read stdin, write the ELF |
| 6 | `asm-store-label`, `asm-find-label` | the label table |
| 7–8 | `asm-parse-number`, `asm-emit-le`, `asm-read-token` | numbers and tokens |
| 9 | `asm-do-ref`, `asm-process-token` | one token, one decision |
| 10 | `asm-pass-loop` | the two passes |
| 11 | `asm-expand-pass` | `DEFINE`s and strings, run before both passes |
| 12 | `asm-main` | all of it, in order |

## 1. M1 and hex2 in one page

The Glossary gives the two formats a line each.  The assembler needs
them exactly, so here they are.

**hex2** is a stream of tokens separated by whitespace, with `#` and
`;` starting comments.  A run of hex digits is bytes, two digits per
byte: `0F05` is the two bytes of `syscall`.  `:name` declares a label
at the current address.  A *sigil* followed by a label name stands
for that label's address, written into a field of fixed width:

| Sigil | Width | Writes |
|---|---:|---|
| `!` | 1 | target − end of field (relative) |
| `@` | 2 | target − end of field |
| `~` | 3 | target − end of field |
| `%` | 4 | target − end of field; `%target>base` writes target − base |
| `$` | 2 | the target's address (absolute) |
| `&` | 4 | the target's address |

Addresses count up from a base, 0x600000 for M2-Planet's programs.
"Relative" means relative to the end of the field.  When the field
is the last part of an x86 instruction, as a `jmp` or `call`
displacement is, that is the start of the next instruction, exactly
where the CPU measures from.  `%target>base` is the odd one out: two labels,
no address arithmetic against the current position.  M2-Planet's
ELF header, `M2libc/amd64/ELF-amd64.hex2`, uses it to get the file
size into the program header (`%ELF_end>ELF_base`) and `&_start` to
get the entry point into `e_entry`.

**M1** is hex2 plus three conveniences, all textual:

- `DEFINE name value` makes every later `name` stand for `value`:
  `DEFINE syscall 0F05`, `DEFINE mov_rax, 48C7C0`.  The comma is
  part of the name.  M2-Planet's `amd64_defs.M1` is 314 of these.
- A sigil with a number instead of a label is an immediate: `%60`
  is the four bytes `3C 00 00 00`, `!-1` is `FF`.
- `"hi"` is the bytes of the string plus a NUL (`68 69 00`), and
  `'0F 05'` is passed through as is.

mescc-tools splits the job in two.  `M1` rewrites M1 into hex2 text:
macros replaced, numbers and strings turned into hex, labels and
label references left alone.  `hex2` then lays out the labels and
writes the bytes.  Here is a fragment of Try it's program before and
after `M1`:

```
:_start                              :_start
    mov_eax, %1  mov_edi, %1         B8 01000000 BF 01000000
    mov_esi, &msg  mov_edx, %3       BE &msg BA 03000000
    syscall                          0F05
    jmp8 !done                       EB !done
:msg "hi                             :msg 68 69 0A 00
"
```

`130-asm.fth` does both jobs in one program, and it is more
forgiving than `M1` about what it accepts.  mescc-tools' `M1` stops
at a bare hex token such as `7F454C46` ("Received invalid other")
and wants it quoted; that is why stage0 feeds the ELF header to
`hex2`, not `M1`.  The Forth assembler takes raw hex anywhere, so
`bootstrap.sh`'s `forth_asm` can simply concatenate `amd64_defs.M1`,
`ELF-amd64.hex2`, `libc-full.M1` and the program onto stdin.  It is
no more forgiving than that: a bare token that is neither a macro
nor hex is still an error, and so is a value too big for its field
(§13).

## 2. The file's contract

```forth file=130-asm.fth
\ 130-asm.fth — M1 + hex2 assembler / linker in Forth.
\
\ Closes the bootstrap gap below seed-forth's C compiler: consumes the
\ M1 macro syntax that M2-Planet emits and produces ELF bytes directly,
\ removing the need to trust GCC-built mescc-tools (M1, hex2).  Stage0-
\ posix's M1+hex2 stays in the picture as an independent byte-level
\ witness; both pipelines are expected to produce identical bytes.
\
\ Self-contained: depends only on 010-lib.fth (and the seed primitives
\ it builds on).  No cross-import from the C-compiler layers — forth-asm
\ sits cleanly below the cc in the bootstrap chain rather than alongside.
\
\ What is implemented (phase 2 complete):
\   - M1 macro expansion: 'DEFINE name value' + name substitution
\   - Six sigils: '!' (1-byte rel), '@' (2-byte rel), '~' (3-byte rel),
\     '%' (4-byte rel, with optional '>base' explicit base), '$' (2-byte
\     abs), '&' (4-byte abs).  Each handles numeric form ('!42', '%0x3C',
\     '%-1', decimal / hex / negative) and label form.
\   - Quoted strings: '"text"' hex-encodes bytes with NUL terminator;
\     "'text'" passes content through verbatim.
\   - ':label' decls; '#' and ';' comments to end of line.
\   - Two-pass label resolution; cmp-identical to mescc-tools' M1+hex2
\     output for the exit42 smoke test, the m1-jump42 fixture, and the
\     full M2-Planet self-compile (~2.4 MiB M1 in, 220 KiB ELF out).
\
\ What is checked, as mescc-tools checks it: a label reference must fit
\ its field (hex2's rule; 244), a number must fit its field (M1's rule;
\ 245), and a bare token must be an even number of hex digits (246, 247),
\ so a misspelled macro name is an error, not bytes.
\
\ Not implemented (no real-world inputs use these on amd64; the token
\ forms among them die with 246 or 247 rather than assembling differently):
\   - '<N' padding directive
\   - nibble accumulation across whitespace within a hex pair
\   - architecture-specific ARM/AArch64/RISC-V displacement quirks
\   - the rare unary-'<' / '^' alignment markers used by ARM
\   - a quoted DEFINE body

```

Four promises are worth holding on to.  The file depends on
`010-lib.fth` and nothing else, which §5 comes back to.  It is
two-pass, so a reference may come before its label.  What it checks,
it checks the way mescc-tools does, so a malformed input dies here
wherever it would die there (§13).  And the "not implemented" list
is the price of 785 lines: padding, alignment and the ARM, AArch64
and RISC-V field encodings, none of which amd64 M1 from M2-Planet
uses; the token forms among them die rather than assemble wrong.

## 3. Buffers and a cursor

The first thing the file does is move `HERE` past the VM's fixed
pages, with `skip-vm-pages` from Ch 12, exactly as `030-cc-io.fth`
does for the compiler.  Then it defines the one check every buffer
write goes through.

```forth file=130-asm.fth
\ ============================================================================
\ A. Buffers + cursor abstraction
\ ============================================================================
\ Skip past the VM's fixed pages (data stack 0x410000..0x411000, I/O scratch
\ 0x412000, token buffer 0x412800, sysvars 0x413000..0x414000) so our buffers
\ do not overlap runtime VM state.
skip-vm-pages                                   \ HERE = 0x414000

\ asm-check-cap ( n cap code -- )  Die with code unless n <= cap: the
\ assembler's copy of cc-check-cap (020), since this program loads none of
\ the compiler's files.  n is how full a buffer or table will be once the
\ write about to happen is done.  Codes are 230..249 (Appendix G).
: asm-check-cap
  >r > if, r> die then,
  r> drop ;

```

`asm-check-cap` is Ch 21's `cc-check-cap` letter for letter, except
for the last word: `die` (Ch 5) instead of `cc-die`.  The assembler
reports a failure with its exit status and nothing else; there is no
source line to print, because M1 text has no line tracking here.
Codes 230–249 are the assembler's, next to the compiler's in
Appendix G.

Two 4 MiB buffers hold the input.  `asm-src-buf` keeps stdin exactly
as read; `asm-exp-buf` gets the text after macro expansion.  The
reading words do not name either buffer.  They go through a cursor
of three variables, and two words aim it.

```forth file=130-asm.fth
\ Raw M1 source (filled by asm-load-stdin).
\ Sized for M2-Planet's ~2.4 MiB self-compile output plus libc + defs + ELF.
[lit] 4194304 constant asm-src-cap            \ 4 MiB
create asm-src-buf  asm-src-cap allot
variable asm-src-len

\ Expanded buffer (filled by asm-expand-pass: M1 macros substituted, DEFINEs
\ stripped).  Passes 1 and 2 read from here, not from asm-src-buf.
[lit] 4194304 constant asm-exp-cap            \ 4 MiB
create asm-exp-buf  asm-exp-cap allot
variable asm-exp-len

\ Cursor: read primitives look at whichever buffer asm-cur-* points to.
\ asm-use-src and asm-use-exp swap the cursor between the two buffers.
variable asm-cur-buf
variable asm-cur-len
variable asm-cur-pos

: asm-use-src
  asm-src-buf asm-cur-buf !
  asm-src-len @ asm-cur-len !
  [lit] 0 asm-cur-pos ! ;

: asm-use-exp
  asm-exp-buf asm-cur-buf !
  asm-exp-len @ asm-cur-len !
  [lit] 0 asm-cur-pos ! ;

: asm-reset-pos  [lit] 0 asm-cur-pos ! ;

```

One tokenizer, pointed at `asm-src-buf`, feeds the macro expander
(§11); pointed at `asm-exp-buf`, it feeds both assembly passes.
`asm-reset-pos` rewinds without changing buffers, which is all the
second pass needs.

```forth file=130-asm.fth
\ asm-load-stdin ( -- )  Read all of fd 0 into asm-src-buf.  Each read asks
\ for all the room left; a source that fills the buffer dies with 239 (a
\ full buffer and a longer input look the same, so one byte stays unused).
: asm-load-stdin
  [lit] 0 asm-src-len !
  begin,
    [lit] 0 asm-src-buf asm-src-len @ +  asm-src-cap asm-src-len @ -  read
    dup [lit] 0 >
  while,
    asm-src-len +!
    asm-src-len @ 1+ asm-src-cap [lit] 239 asm-check-cap
  repeat,
  drop ;

\ asm-eof? ( -- f )
: asm-eof?  asm-cur-pos @ asm-cur-len @ >= ;

\ asm-peek-char ( -- c )  Byte at current position; 0 at EOF.
: asm-peek-char
  asm-eof? if,
    [lit] 0
  else,
    asm-cur-buf @ asm-cur-pos @ + c@
  then, ;

\ asm-next-char ( -- c )  Returns current byte, advances pos.
: asm-next-char
  asm-peek-char
  [lit] 1 asm-cur-pos +! ;

\ asm-exp-emit-byte ( b -- )  Append a byte to asm-exp-buf; die 240 if full.
: asm-exp-emit-byte
  asm-exp-len @ 1+ asm-exp-cap [lit] 240 asm-check-cap
  asm-exp-buf asm-exp-len @ + c!
  [lit] 1 asm-exp-len +! ;

```

`asm-load-stdin` is Ch 21's `cc-read-all` inlined for one buffer:
ask `read` for all the room that is left, add what came back, stop
at 0.  It checks `len + 1` against the capacity, so a source that
exactly fills the buffer dies with 239 rather than being silently
cut: after a full read there is no way to tell "done" from "more
waiting".  `tests/asm/die-gates.sh` feeds it 4 MiB of blanks to
prove it.

`asm-peek-char` returns 0 at the end of the buffer, the same
convention as the compiler's `cc-peek-char`, and `asm-next-char`
advances even there, harmlessly, since `asm-eof?` compares with
`>=`.  `asm-exp-emit-byte` is the only way bytes enter the expansion
buffer, so its one check (240) covers every writer.

## 4. The output side

```forth file=130-asm.fth
\ ============================================================================
\ B. Output buffer + emit helpers
\ ============================================================================
[lit] 1048576 constant asm-out-cap
create asm-out-buf  asm-out-cap allot
variable asm-out-pos

: asm-out-init  [lit] 0 asm-out-pos ! ;

\ asm-emit-byte ( b -- )  Append a byte to asm-out-buf; die 241 if full.
: asm-emit-byte
  asm-out-pos @ 1+ asm-out-cap [lit] 241 asm-check-cap
  asm-out-buf asm-out-pos @ + c!
  [lit] 1 asm-out-pos +! ;

\ ============================================================================
\ C. Output file write
\ ============================================================================
\ Open flags: O_WRONLY=1, O_CREAT=64, O_TRUNC=512 → 577.  Mode 0o755 = 493.

\ asm-write-output ( path-addr -- )  path-addr must point at NUL-terminated bytes.
: asm-write-output
  [lit] 577 [lit] 493 open                      ( fd )
  dup 0< if,
    drop [lit] 230 die
  then,
  >r                                            ( ; R: fd )
  r@ asm-out-buf asm-out-pos @ write drop
  r> close drop ;

\ Newline byte for stderr diagnostics.
create asm-nl-byte  nl c,

```

The output buffer is 1 MiB; M2-Planet assembles to 223,515 bytes.
`asm-emit-byte` checks before it stores, like `asm-exp-emit-byte`,
and dies with 241 when full.

`asm-write-output` is Ch 21's `cc-write-output` again: flags 577 are
`O_WRONLY|O_CREAT|O_TRUNC`, mode 493 is `0o755`, so the file is
executable as soon as it is written.  A failed `open` is code 230.
`asm-nl-byte` exists because `emit` (Ch 16) always writes to fd 1:
the one diagnostic this program prints goes to fd 2, and `write`
needs the newline in memory.

## 5. Why not load `030-cc-io.fth`?

You have now met four words the compiler already has under other
names: `asm-check-cap`, `asm-load-stdin`, `asm-peek-char` and
`asm-write-output`.  Loading `020-cc-arena.fth` and `030-cc-io.fth`
would save most of them.  The file deliberately does not.

The compiler's I/O words are not free-standing.  `cc-check-cap` ends
in `cc-die`, which prints `cc-src-line` from the lexer-state block
(Ch 21); `cc-load-stdin` starts with `cc-src-init`.  Borrowing the
I/O means borrowing the compiler's state and its failure
conventions, and then the assembler is only correct if those files
are.

Self-containment keeps the audit short and the layers one-way.  To
trust what the assembler writes, you read `010-lib.fth` and this
file; nothing in Chs 21–32 can change a byte of its output, and
nothing here can change the compiler's (Ch 32's `-cc-` glob keeps
`130-asm.fth` out of every compile).  The file header puts it as
"below the cc in the bootstrap chain rather than alongside".  The
cost is about forty lines of near-duplicates, and each one is short
enough to compare with its twin at a glance.

## 6. The label table

A label is a name and an address.  The table stores 24-byte records
of three cells: where the name is, how long it is, and the address.

```forth file=130-asm.fth
\ ============================================================================
\ Label table — flat array of (name-addr, name-len, ip) triples.
\ ============================================================================

[lit]   24 constant asm-rec-size
[lit] 8192 constant asm-cap                   \ headroom: M2-Planet uses ~4k labels
create asm-labels  asm-rec-size asm-cap * allot
variable asm-count

\ Base address.  Default matches mescc-tools' --base-address 0x00600000
\ for the M2-Planet self-compile path.  Callers can override by storing a
\ different value before invoking asm-main, e.g. for GNU Mes (0x1000000):
\
\   cat 010-lib.fth 130-asm.fth                   \ defines words
\   echo '[lit] 16777216 asm-base !'              \ override
\   echo 'asm-main'                                \ then run
\
variable asm-base
[lit] 6291456 asm-base !                          \ 0x600000 default
variable asm-ip
variable asm-pass

\ asm-rec ( i -- a )  Address of the i-th label record.
: asm-rec  asm-rec-size *  asm-labels + ;

\ asm-store-label ( name-addr name-len -- )  Die 242 if the table is full.
: asm-store-label
  asm-count @ 1+ asm-cap [lit] 242 asm-check-cap
  asm-count @ asm-rec                       ( addr len rec )
  >r                                         ( addr len ; R: rec )
  r@ [lit] 8 + !                             \ rec[8] = len
  r@ !                                       \ rec[0] = addr
  asm-ip @ r> [lit] 16 + !                   \ rec[16] = ip
  [lit] 1 asm-count +! ;

```

The name is not copied.  Labels are recorded while the cursor is on
`asm-exp-buf`, and that buffer never changes after expansion, so a
pointer into it stays valid through both passes.  8,192 records is
twice what M2-Planet needs: its self-compile declares 4,023 labels.

`asm-base` is the address of the first byte, 0x600000 unless the
caller stores something else before `asm-main`.  `asm-store-label`
records `asm-ip`, the address the next byte will have, so `:done`
followed by `B8` gives `done` the address of that `B8`.

```forth file=130-asm.fth
variable asm-find-addr
variable asm-find-len

\ asm-find-label ( name-addr name-len -- ip flag )
\ Linear scan from newest to oldest entry.  flag = -1 if found (returning
\ at once, with exit,), else ip = flag = 0.
: asm-find-label
  asm-find-len !  asm-find-addr !
  asm-count @
  begin,
    dup [lit] 0 >
  while,
    1-                                       ( i )
    dup asm-rec                              ( i rec )
    dup [lit] 8 + @ asm-find-len @ = if,
      dup @ asm-find-addr @ asm-find-len @ bytes-eq if,
        nip [lit] 16 + @ true exit,          ( ip -1 )
      then,
    then,
    drop                                     ( i )
  repeat,
  drop [lit] 0 [lit] 0 ;

```

`asm-find-label` is the book's small-table search once more (Chs 17,
22, 24): compare lengths first, bytes second with `bytes-eq`, newest
entry first.  On a hit it leaves the address and `true` and leaves
the word through `exit,` (Ch 11), with the index already dropped by
`nip`.  It is linear, and pass 2 calls it for every label reference,
each time over up to 4,023 labels for M2-Planet; Exercise 4 asks
what a hash would buy.

## 7. Numbers

A sigil's body may be a number instead of a label, and hex tokens
need their digits converted.  Four words cover it.

```forth file=130-asm.fth
\ ============================================================================
\ Hex digit utilities + decimal parser + variable-width emit
\ ============================================================================

\ hex-val ( c -- v )  Convert one hex digit char to 0-15.
\ Caller must ensure c is a valid hex digit (asm-hex-char?, below).
: hex-val
  dup digit? if,
    [char] 0 -
  else,
    dup [char] a - [lit] 6 / 0= if,
      [lit] 87 -                             \ 'a'..'f' -> 10..15
    else,
      [lit] 55 -                             \ 'A'..'F' -> 10..15
    then,
  then, ;

\ asm-hex-char? ( c -- f )  True for 0-9, a-f and A-F, the characters
\ hex2 reads as digits.
: asm-hex-char?
  dup digit?
  over [char] a - [lit] 6 / 0= or
  swap [char] A - [lit] 6 / 0= or ;

```

`hex-val` uses Ch 6's range check, `(c - 'a') / 6 == 0`, to tell
lower-case from upper-case letters.  It trusts its input: a
character that is not a hex digit gives a wrong value, not an error.
`asm-hex-char?` is the same range check asked as a question, three
times, and pass 1 asks it of every character of a hex token before
`hex-val` ever sees one (§9).

```forth file=130-asm.fth
variable asm-dec-addr
variable asm-dec-len
variable asm-dec-val
variable asm-dec-neg
variable asm-dec-hex
variable asm-dec-i

\ asm-parse-number ( addr len -- value )
\ Decimal or hex integer: optional leading '-', then an optional '0x' / '0X'
\ prefix for hex.
\ (Matches a subset of mescc-tools' strtoint sufficient for amd64 inputs;
\ 0b binary and bare-0 octal are not used by M2-Planet's M1 output.)
: asm-parse-number
  asm-dec-len ! asm-dec-addr !
  [lit] 0 asm-dec-val !
  [lit] 0 asm-dec-neg !
  [lit] 0 asm-dec-hex !
  [lit] 0 asm-dec-i !
  \ Leading '-'?
  asm-dec-len @ [lit] 0 > if,
    asm-dec-addr @ c@ [char] - = if,
      true asm-dec-neg !
      [lit] 1 asm-dec-i !
    then,
  then,
  \ '0x' / '0X' hex prefix?
  asm-dec-len @ asm-dec-i @ - [lit] 2 >= if,
    asm-dec-addr @ asm-dec-i @ + c@ [char] 0 = if,
      asm-dec-addr @ asm-dec-i @ + 1+ c@
      dup [char] x = swap [char] X = or if,
        true asm-dec-hex !
        [lit] 2 asm-dec-i +!
      then,
    then,
  then,
  asm-dec-hex @ if,
    begin,
      asm-dec-i @ asm-dec-len @ <
    while,
      asm-dec-addr @ asm-dec-i @ + c@ hex-val
      asm-dec-val @ [lit] 16 * +
      asm-dec-val !
      [lit] 1 asm-dec-i +!
    repeat,
  else,
    begin,
      asm-dec-i @ asm-dec-len @ <
    while,
      asm-dec-addr @ asm-dec-i @ + c@ [char] 0 -
      asm-dec-val @ [lit] 10 * +
      asm-dec-val !
      [lit] 1 asm-dec-i +!
    repeat,
  then,
  asm-dec-val @
  asm-dec-neg @ if,
    [lit] 0 swap -
  then, ;

```

`asm-parse-number` accepts an optional `-`, then an optional `0x` or
`0X`, then digits, and negates at the end with `0 swap -` (Ch 4).
That is the subset of mescc-tools' `strtoint` that amd64 inputs
use; binary and octal are left out, as the comment says.  Six
variables instead of stack juggling, the style the compiler uses
too: every intermediate has a name you can print.

```forth file=130-asm.fth
\ asm-emit-le ( v width -- )  Emit the low width bytes of v, little-endian.
: asm-emit-le
  begin,
    dup
  while,
    over asm-emit-byte                     ( v width )
    swap [lit] 256 / swap 1-               ( v/256 width-1 )
  repeat,
  2drop ;

```

`asm-emit-le` writes the low `width` bytes of a value, low byte
first, dividing by 256 each time.  The seed's `/` is unsigned
(Ch 15), so dividing a negative value by 256 is a logical shift
right, and the bytes of a negative displacement come out in two's
complement: `%-1` gives `FF FF FF FF`, and a backward `!label` of
−5 gives `FB`.

## 8. Reading tokens

A token is a slice of the active buffer: an address and a length,
never a copy.

```forth file=130-asm.fth
\ ============================================================================
\ Whitespace / comment skipper and token reader
\ ============================================================================
\
\ asm-skip-rest-of-line ( -- )  Consume bytes until newline or EOF.
: asm-skip-rest-of-line
  begin,
    asm-eof? if, exit, then,
    asm-next-char nl =
  until, ;

\ asm-skip-ws ( -- )  Advance past whitespace and '#'/';' comments.
: asm-skip-ws
  begin,
    asm-eof? if, exit, then,
    asm-peek-char dup space? if,
      drop asm-next-char drop
    else,
      dup [char] # =  swap [char] ; =  or 0= if, exit, then,
      asm-next-char drop
      asm-skip-rest-of-line
    then,
  again, ;

```

`asm-skip-ws` loops with `again,` (Ch 11) and leaves through
`exit,`, over whitespace (`space?`, Ch 6) and over comments: a `#`
or `;` consumes the rest of the line.

```forth file=130-asm.fth
variable asm-tok-start
variable asm-tok-len
variable asm-quote-char

\ asm-read-quoted ( -- )  At an opening quote: count bytes through the
\ matching close quote (whitespace and newlines inside are body bytes).
: asm-read-quoted
  asm-next-char asm-quote-char !
  [lit] 1 asm-tok-len +!
  begin,
    asm-eof? if, exit, then,
    [lit] 1 asm-tok-len +!
    asm-next-char asm-quote-char @ =
  until, ;

\ asm-read-bareword ( -- )  Count bytes up to whitespace, '#', ';' or EOF.
: asm-read-bareword
  begin,
    asm-eof? if, exit, then,
    asm-peek-char  dup space?  over [char] # = or  swap [char] ; = or
    if, exit, then,
    asm-next-char drop
    [lit] 1 asm-tok-len +!
  again, ;

\ asm-read-token ( -- start len )
\ Whitespace/comment-delimited token slice of the active buffer; (0 0) at EOF.
\ '"' and "'" start a quoted string token that runs until the matching close
\ quote.  The returned slice includes both quote characters.
: asm-read-token
  asm-skip-ws
  asm-eof? if, [lit] 0 [lit] 0 exit, then,
  asm-cur-buf @ asm-cur-pos @ + asm-tok-start !
  [lit] 0 asm-tok-len !
  asm-peek-char dup [char] " = swap [char] ' = or if,
    asm-read-quoted
  else,
    asm-read-bareword
  then,
  asm-tok-start @ asm-tok-len @ ;

```

A quote starts a token that runs to the matching quote, spaces and
newlines included, so `"hi` newline `"` is one token of five bytes.
Everything else is a bareword that ends at whitespace or a comment
character.  `asm-read-token` returns `0 0` at the end, and a length
of 0 is how every loop in the file knows to stop.

## 9. One token, one decision

Each token of the expanded text is one of three things: a label
declaration, a sigil reference, or hex.  The next pieces handle each
kind, and a dispatcher at the end of the section picks one.  First
the shared state and the smaller helpers:

```forth file=130-asm.fth
\ ============================================================================
\ Per-token processing
\ ============================================================================

variable asm-token-start-tmp
variable asm-token-len-tmp
variable asm-gt-pos
variable asm-scan-i
variable asm-hex-i

\ asm-tok-numeric? ( -- f )  Token's body starts with digit or '-' -> numeric form.
\ Token in asm-token-start-tmp / asm-token-len-tmp.
: asm-tok-numeric?
  asm-token-len-tmp @ [lit] 2 < if,
    [lit] 0
  else,
    asm-token-start-tmp @ 1+ c@
    dup [char] - = swap digit? or
  then, ;

\ asm-find-gt ( -- )  Set asm-gt-pos to position of '>' in token name, or -1.
: asm-find-gt
  [lit] 1 asm-scan-i !
  begin,
    asm-scan-i @ asm-token-len-tmp @ <
  while,
    asm-token-start-tmp @ asm-scan-i @ + c@ [char] > = if,
      asm-scan-i @ 1- asm-gt-pos ! exit,
    then,
    [lit] 1 asm-scan-i +!
  repeat,
  true asm-gt-pos ! ;

\ asm-do-label-decl ( -- )
: asm-do-label-decl
  asm-pass @ [lit] 1 = if,
    asm-token-start-tmp @ 1+
    asm-token-len-tmp @ 1-
    asm-store-label
  then, ;

\ asm-tok-err ( code -- )  Write current token + newline to fd 2, then exit code.
: asm-tok-err
  [lit] 2 asm-token-start-tmp @ asm-token-len-tmp @ write drop
  [lit] 2 asm-nl-byte [lit] 1 write drop
  die ;

```

The token under consideration lives in two variables, so the helpers
take no arguments.  `asm-tok-numeric?` looks at the character after
the sigil: a digit or `-` means a number.  `asm-find-gt` finds the
`>` of `%target>base`.  `asm-do-label-decl` records a label only in
pass 1; in pass 2 the table is already complete.  `asm-tok-err`
writes the offending token and a newline to fd 2 and dies with the
code it is given.

A value written into a field has to fit it.  mescc-tools checks this
twice, with different bounds: `M1` checks a number such as `!300`
when it turns it into hex (`range_check` in `M1-macro.c`), and `hex2`
checks a label's value when it writes it (`range_check` in
`hex2_linker.c`).  The Forth assembler does both jobs, so it keeps
both rules, in a table:

```forth file=130-asm.fth
\ ---- Range checks ----
\ mescc-tools refuses a value that does not fit its field, and so does
\ this file.  A label's value is hex2's to check, a number's is M1's, and
\ their bounds differ.  Neither checks a 4-byte field (% and &).
\
\   field               label (hex2)          number (M1)
\   ! 1-byte relative   -128..127             -129..256
\   @ 2-byte relative   -32768..32767         -32769..32768
\   ~ 3-byte relative   -8388608..8388607     -8388609..8388608
\   $ 2-byte absolute   0..65535              -32769..65536

variable asm-fit-lo
variable asm-fit-hi

\ asm-half ( width -- n )  Half the values a width-byte field holds:
\ 128, 32768 or 8388608.
: asm-half
  [lit] 128 swap
  begin,
    1- dup
  while,
    swap [lit] 256 * swap
  repeat,
  drop ;

\ asm-label-bounds ( width relative? -- )  hex2's range for a label: signed
\ for a relative field, unsigned for an absolute one.
: asm-label-bounds
  swap asm-half swap if,                    ( half )
    dup [lit] 0 swap - asm-fit-lo !
    1- asm-fit-hi !
  else,
    [lit] 0 asm-fit-lo !
    dup + 1- asm-fit-hi !
  then, ;

\ asm-number-bounds ( width relative? -- )  M1's range for a number: one
\ below hex2's signed low end, and up to half (relative) or all (absolute,
\ and M1's 1-byte relative) of the field's values.
: asm-number-bounds
  swap dup asm-half                         ( relative? width half )
  dup [lit] 0 swap - 1- asm-fit-lo !
  swap [lit] 1 =  rot 0=  or if,            ( half )
    dup +
  then,
  asm-fit-hi ! ;

\ asm-fit ( width v code -- width v )  Die with code, echoing the token,
\ unless width is 4 or asm-fit-lo <= v <= asm-fit-hi.
: asm-fit
  >r over [lit] 4 < if,                     ( width v ; R: code )
    dup asm-fit-lo @ <  over asm-fit-hi @ >  or if,
      r> asm-tok-err
    then,
  then,
  r> drop ;

```

hex2's rule is the one you would write: a relative field holds a
signed value, an absolute one an unsigned value, so `!` reaches
−128 to 127 and `$` 0 to 65,535.  `M1`'s bounds are its own, and
they are copied here exactly rather than tidied: the low end is one
below the signed range for every field, even the absolute `$`
(`!-129` passes and writes `7f`); the high end is one above it for
`@` and `~`, and one above the *unsigned* range for `!` and `$`
(`!256` passes and writes `00`).  `asm-half` gives half a field's
range, 128, 32,768 or 8,388,608, and the two `-bounds` words set
`asm-fit-lo` and `asm-fit-hi` from it.  `asm-fit` then dies with the
code it is given, echoing the token like every other token error,
unless the value lies between them.  A four-byte field is never
checked, by either tool, which is why `asm-fit` looks at `width`
first: every `%` and `&` passes, and those are the only label
references M2-Planet writes.

Now the heart of the file.  Six sigils could be six handlers; they
differ in only two ways, the width of the field and whether a label
is written as its address or relative to the end of the field.  So
there is one handler, and each sigil passes its width, its
relativity, and the code to die with if its label does not exist.

```forth file=130-asm.fth
\ ---- Sigil references ----
\ A token that starts with one of the six sigils stands for a number of
\ width bytes: its body is either a number (`!42`, `%-1`, `$0x3C`), emitted
\ as is, or a label, whose address is emitted either absolute or relative
\ to the end of the field.  Pass 1 only advances the IP by width; pass 2
\ emits the bytes.
\
\   sigil  width  label form
\     !      1    relative
\     @      2    relative
\     ~      3    relative
\     %      4    relative, or %target>base: target - base
\     $      2    absolute
\     &      4    absolute

\ asm-ref-name ( -- a u )  The token's body: everything after the sigil.
: asm-ref-name  asm-token-start-tmp @ 1+  asm-token-len-tmp @ 1- ;

\ asm-do-ref ( width relative? err -- )  Handle a sigil token of width
\ bytes.  A label that is not defined dies with err (after echoing the
\ token); a value that does not fit the field dies with 244 (label) or
\ 245 (number).
: asm-do-ref
  asm-pass @ [lit] 1 = if,
    2drop asm-ip +! exit,                   \ pass 1: count the bytes
  then,
  >r >r                                     ( width ; R: err relative? )
  asm-tok-numeric? if,
    dup r@ asm-number-bounds
    asm-ref-name asm-parse-number           ( width v )
    [lit] 245 asm-fit
  else,
    asm-ref-name asm-find-label 0= if,      ( width ip )
      r> drop r> asm-tok-err                \ undefined label: exits
    then,
    r@ if,                                  \ relative to the field's end
      over asm-ip @ + -                     ( width ip-IP-width )
    then,
    over r@ asm-label-bounds
    [lit] 244 asm-fit
  then,
  r> drop r> drop                           ( width v )
  over asm-emit-le                          ( width )
  asm-ip +! ;

```

Read `asm-do-ref` in its two passes:

- **Pass 1** drops `relative?` and the error code and adds `width`
  to `asm-ip`.  It never looks at the body.  Every sigil's width is
  fixed, so pass 1 can place every label without knowing the value
  of any reference.
- **Pass 2** parks the error code and `relative?` on the return
  stack.  A numeric body is parsed, checked against `M1`'s bounds
  (245) and used as is.  A label body is looked up; if missing, the
  code comes back off the return stack and `asm-tok-err` exits.  If
  the sigil is relative, the value becomes `target − (IP + width)`:
  `over asm-ip @ + -`, and it is checked against `hex2`'s bounds
  (244).  Then `asm-emit-le` writes `width` bytes and `asm-ip`
  advances.

The return stack is clean on every path that returns, as `exit,` and
`;` require (Ch 11): the normal path pops both cells at
`r> drop r> drop`.  The error paths end in `asm-tok-err`, which does
not return, so what is left on either stack no longer matters; the
undefined-label path pops both anyway, to hand `asm-tok-err` its
code.

```forth file=130-asm.fth
\ asm-do-pct-ref ( -- )  '%': asm-do-ref's 4-byte relative form, plus
\ '%target>base', which emits target - base (two labels, no IP).
: asm-do-pct-ref
  asm-pass @ [lit] 2 =  asm-tok-numeric? 0=  and if,
    asm-find-gt
    asm-gt-pos @ [lit] 0 >= if,
      asm-token-start-tmp @ 1+
      asm-gt-pos @
      asm-find-label                        ( target flag )
      0= if,
        drop [lit] 233 asm-tok-err          \ target undefined
      then,
      asm-token-start-tmp @ 1+ asm-gt-pos @ + 1+
      asm-token-len-tmp @ asm-gt-pos @ - [lit] 2 -
      asm-find-label                        ( target base flag )
      0= if,
        2drop [lit] 232 asm-tok-err         \ base undefined
      then,
      - [lit] 4 asm-emit-le
      [lit] 4 asm-ip +! exit,
    then,
  then,
  [lit] 4 true [lit] 234 asm-do-ref ;

```

`%` is the only sigil with a second form.  `asm-do-pct-ref` handles
`%target>base` itself in pass 2: two lookups, each with its own
error code (233 for the target, 232 for the base), then `target −
base` in four bytes.  Every other case, including all of pass 1,
falls through to `asm-do-ref` as a 4-byte relative reference with
code 234.  mescc-tools' `hex2` accepts `>base` after any relative
sigil; amd64 inputs only ever put it after `%`, and this file only
supports it there.

```forth file=130-asm.fth
\ asm-check-hex ( -- )  A bare token must be hex digits (else 246: a
\ misspelled macro name lands here, as M1's "invalid other") and an even
\ number of them (else 247: hex2 would carry the odd digit into the next
\ token, which this file does not do).
: asm-check-hex
  [lit] 0 asm-hex-i !
  begin,
    asm-hex-i @ asm-token-len-tmp @ <
  while,
    asm-token-start-tmp @ asm-hex-i @ + c@ asm-hex-char? 0= if,
      [lit] 246 asm-tok-err
    then,
    [lit] 1 asm-hex-i +!
  repeat,
  asm-token-len-tmp @ [lit] 1 and if,
    [lit] 247 asm-tok-err
  then, ;

\ asm-do-hex ( -- )  Token of hex digits -> 1 byte per pair.  Pass 1
\ checks it, so pass 2 only ever sees whole pairs of digits.
: asm-do-hex
  asm-pass @ [lit] 1 = if,
    asm-check-hex
    asm-token-len-tmp @ [lit] 2 / asm-ip +!
  else,
    [lit] 0 asm-hex-i !
    begin,
      asm-hex-i @ asm-token-len-tmp @ <
    while,
      asm-token-start-tmp @ asm-hex-i @ + c@ hex-val [lit] 16 *
      asm-token-start-tmp @ asm-hex-i @ 1+ + c@ hex-val
      +
      asm-emit-byte
      [lit] 1 asm-ip +!
      [lit] 2 asm-hex-i +!
    repeat,
  then, ;

\ asm-process-token ( start len -- )  Dispatch on the token's first char:
\ a label declaration, one of the six sigils (width, relative?, and the
\ code for an undefined label), or else hex bytes.
: asm-process-token
  asm-token-len-tmp !  asm-token-start-tmp !
  asm-token-start-tmp @ c@                  ( c )
  dup [char] : = if, drop asm-do-label-decl                   exit, then,
  dup [char] ! = if, drop [lit] 1 true    [lit] 235 asm-do-ref exit, then,
  dup [char] @ = if, drop [lit] 2 true    [lit] 236 asm-do-ref exit, then,
  dup [char] ~ = if, drop [lit] 3 true    [lit] 237 asm-do-ref exit, then,
  dup [char] % = if, drop asm-do-pct-ref                      exit, then,
  dup [char] $ = if, drop [lit] 2 [lit] 0 [lit] 238 asm-do-ref exit, then,
  dup [char] & = if, drop [lit] 4 [lit] 0 [lit] 231 asm-do-ref exit, then,
  drop asm-do-hex ;

```

`asm-do-hex` checks the token in pass 1 and counts `len / 2` bytes;
pass 2 writes one byte per digit pair.  `asm-check-hex` is where a
misspelled macro name ends up: `syscal` was not `DEFINE`d, so
expansion copied it through, and it is not hex, so it dies with 246
where `M1` would say "Received invalid other".  A hex token with an
odd number of digits dies with 247.  `hex2` would not stop there; it
reads digits one at a time and carries the odd one into the next
token, so `'1 2'` is the byte 0x12.  This file reads a hex token as
whole pairs, and refusing the odd digit keeps both passes counting
the same bytes.  Checking in pass 1 is enough: pass 2 reads the
same text, and pass 1 has already refused anything it could not
count.  `asm-process-token` is the dispatcher: one
line per kind, first character decides, hex is the fallback.  The
whole sigil table from the comment above `asm-ref-name` is in these
seven lines: `!`, `@` and `~` are relative with widths 1, 2 and 3;
`$` and `&` are absolute (relative flag 0) with widths 2 and 4.

Every sigil at once, on a label at the base address:

```sh
{ cat 010-lib.fth 130-asm.fth; echo asm-main
  printf ':a %%-1 !a @0x3C ~a $258 &a\n'; } | ./seed-forth
od -An -tx1 /tmp/asm-out | cut -c2-   # prints "ff ff ff ff fb 3c 00 f6 ff ff 02 01 00 00 60 00"
```

`%-1` is four `ff`.  `!a` sits at 0x600004, so its field ends at
0x600005 and `a - 0x600005` is −5, `fb`.  `@0x3C` is a number,
`3c 00`.  `~a`'s field ends at 0x60000A: −10 in three bytes,
`f6 ff ff`.  `$258` is the number 0x102, `02 01`: `$a` would be
refused, since 0x600000 does not fit two unsigned bytes (244).
`&a` is all four bytes of the address: `00 00 60 00`.

## 10. Two passes

Ch 11 met a forward jump with emit, remember, patch: write a
placeholder, keep its address, fill it in when the target is known.
The compiler does the same with calls (Ch 26) and `goto` (Ch 30).
The assembler has a simpler option, because its whole input is
already in memory: read it twice.

```forth file=130-asm.fth
\ ============================================================================
\ Two-pass driver
\ ============================================================================

: asm-pass-loop
  begin,
    asm-read-token
    dup [lit] 0 = if, 2drop exit, then,
    asm-process-token
  again, ;

: asm-init
  asm-base @ asm-ip !
  [lit] 0 asm-count ! ;

```

`asm-pass-loop` reads tokens until the zero-length one and hands each
to `asm-process-token`, which checks `asm-pass` wherever the passes
differ.  Pass 1 only moves `asm-ip` and fills the label table.  Pass
2 starts again from the same base, so every token lands at the
address pass 1 gave it, and every label, forward or backward, is
already in the table.

That argument has one condition: both passes must agree on every
token's size.  Sigils have fixed widths, labels have none, and a hex
token is `len / 2` bytes in both passes, because pass 1 refuses one
whose `len` is odd (247, §9).

Stop after pass 1 and print the table, then run both passes on the
same input:

```sh
{ cat 010-lib.fth 130-asm.fth; cat <<'FORTH'
: .h  dup [lit] 15 > if, dup [lit] 16 / .h then,
      [lit] 15 and dup [lit] 9 > if, [lit] 39 + then, [lit] 48 + emit ;
: pass-1-only
  asm-load-stdin asm-use-src asm-expand-pass asm-use-exp
  asm-init [lit] 1 asm-pass ! asm-pass-loop
  [lit] 0 begin, dup asm-count @ < while,
    dup asm-rec dup @ over [lit] 8 + @ [lit] 1 rot rot write drop
    bl emit [lit] 16 + @ .h bl emit  1+
  repeat, drop  asm-ip @ .h nl emit bye ;
pass-1-only
FORTH
printf ':top EB !end 90 90 :end EB !top\n'; } | ./seed-forth   # prints "top 600000 end 600004 600006"
{ cat 010-lib.fth 130-asm.fth; echo asm-main
  printf ':top EB !end 90 90 :end EB !top\n'; } | ./seed-forth
od -An -tx1 /tmp/asm-out | cut -c2-     # prints "eb 02 90 90 eb fa"
```

Pass 1 knows `end` is at 0x600004 before a single byte exists, and
the final `asm-ip`, 0x600006, is the program's end.  Pass 2 then
writes `eb 02`, a forward jump over the two `nop`s, and `eb fa`, a
jump back six bytes to `top`.  (`.h` is Ch 26's hex printer.)

## 11. Macro expansion

Both passes read `asm-exp-buf`.  This section fills it.  `DEFINE`s
go in a table like the labels', with 32-byte records: name address,
name length, body address, body length, all pointing into
`asm-src-buf`.

```forth file=130-asm.fth
\ ============================================================================
\ M1 macro expansion (phase 2b)
\ ============================================================================
\ Single linear pass over the raw source.  Tokens:
\   - "DEFINE" -> consume next 2 tokens (name, value), store in defs table;
\     emit nothing to asm-exp-buf.
\   - defined name -> emit its body bytes (followed by a space separator).
\   - any other token -> copy verbatim to asm-exp-buf (followed by a space).
\ DEFINEs always appear before use in real M1 sources, so single-pass works.

[lit]   32 constant asm-def-rec-size          \ name-addr 8 + name-len 8 + body-addr 8 + body-len 8
[lit] 4096 constant asm-def-cap
create asm-defs  asm-def-rec-size asm-def-cap * allot
variable asm-def-count

: asm-def-rec  asm-def-rec-size * asm-defs + ;

\ asm-def-store ( name-addr name-len body-addr body-len -- )  Die 243 if
\ the table is full.
: asm-def-store
  asm-def-count @ 1+ asm-def-cap [lit] 243 asm-check-cap
  asm-def-count @ asm-def-rec                ( name-a name-l body-a body-l rec )
  >r                                          ( name-a name-l body-a body-l ; R: rec )
  r@ [lit] 24 + !                             \ rec[24] = body-len
  r@ [lit] 16 + !                             \ rec[16] = body-addr
  r@ [lit] 8 + !                              \ rec[8] = name-len
  r> !                                        \ rec[0] = name-addr
  [lit] 1 asm-def-count +! ;

variable asm-deff-addr
variable asm-deff-len

\ asm-def-find ( name-addr name-len -- body-addr body-len flag )
\ flag = -1 if found, 0 otherwise; body-* are 0 when not found.
: asm-def-find
  asm-deff-len !  asm-deff-addr !
  asm-def-count @
  begin,
    dup [lit] 0 >
  while,
    1-                                       ( i )
    dup asm-def-rec                          ( i rec )
    dup [lit] 8 + @ asm-deff-len @ = if,
      dup @ asm-deff-addr @ asm-deff-len @ bytes-eq if,
        nip dup [lit] 16 + @ swap [lit] 24 + @ true exit,
      then,
    then,
    drop                                     ( i )
  repeat,
  drop [lit] 0 [lit] 0 [lit] 0 ;

```

`asm-def-find` is `asm-find-label` again with four cells per record
and a body instead of an address.  4,096 entries against M2-Planet's
314 `DEFINE`s is generous; the cap is there so an input with more
dies with 243 instead of writing past the table.

```forth file=130-asm.fth
\ asm-define-kw: the 6 bytes of "DEFINE".
create asm-define-kw  s, DEFINE

\ asm-is-define? ( addr len -- f )  True if token equals "DEFINE".
: asm-is-define?
  dup [lit] 6 = if,
    drop asm-define-kw [lit] 6 bytes-eq
  else,
    drop drop [lit] 0
  then, ;

variable asm-cp-addr
variable asm-cp-len
variable asm-cp-i

\ asm-exp-bytes ( addr len -- )  Copy len bytes from addr to asm-exp-buf.
: asm-exp-bytes
  asm-cp-len !  asm-cp-addr !
  [lit] 0 asm-cp-i !
  begin,
    asm-cp-i @ asm-cp-len @ <
  while,
    asm-cp-addr @ asm-cp-i @ + c@ asm-exp-emit-byte
    [lit] 1 asm-cp-i +!
  repeat, ;

\ asm-hex-digit ( n -- c )  Map 0..15 to ASCII '0'..'9' / 'A'..'F'.
: asm-hex-digit
  dup [lit] 10 < if,
    [char] 0 +
  else,
    [lit] 55 +
  then, ;

```

`s, DEFINE` (Ch 12) lays down the six bytes of the keyword, and
`asm-is-define?` compares a token with them only when its length is
6.  `asm-exp-bytes` copies a slice into the expansion buffer through
`asm-exp-emit-byte`, so it inherits the 240 check.  `asm-hex-digit`
turns 0–15 back into a character, the inverse of `hex-val`.

```forth file=130-asm.fth
\ asm-exp-string-double ( start len -- )
\ Token = '"' body '"' (len includes both quotes).  Emit hex-encoded body
\ bytes (separated by spaces) plus a trailing 00 NUL terminator, matching
\ mescc-tools M1's double-quoted-string semantics.
: asm-exp-string-double
  asm-cp-len !  asm-cp-addr !
  [lit] 1 asm-cp-i !
  begin,
    asm-cp-i @ asm-cp-len @ 1- <
  while,
    asm-cp-addr @ asm-cp-i @ + c@
    dup [lit] 16 / asm-hex-digit asm-exp-emit-byte
    [lit] 15 and asm-hex-digit asm-exp-emit-byte
    bl asm-exp-emit-byte
    [lit] 1 asm-cp-i +!
  repeat,
  \ NUL terminator: "00 "
  [char] 0 asm-exp-emit-byte [char] 0 asm-exp-emit-byte
  bl asm-exp-emit-byte ;

\ asm-exp-string-single ( start len -- )
\ Token = "'" body "'".  Emit body bytes verbatim, then a space separator.
: asm-exp-string-single
  asm-cp-len !  asm-cp-addr !
  [lit] 1 asm-cp-i !
  begin,
    asm-cp-i @ asm-cp-len @ 1- <
  while,
    asm-cp-addr @ asm-cp-i @ + c@ asm-exp-emit-byte
    [lit] 1 asm-cp-i +!
  repeat,
  bl asm-exp-emit-byte ;

```

The two string forms, both given the token with its quotes.  A
double-quoted string becomes two hex digits and a space per byte,
then `00 `: the terminator C strings need.  A single-quoted string
is copied without its quotes, so `'7F 45 4C 46'` expands to hex
that pass 1 reads as four ordinary tokens.

```forth file=130-asm.fth
\ asm-expand-pass ( -- )  Walk current cursor (asm-src-buf), build defs table,
\ write expanded text into asm-exp-buf.
: asm-expand-pass
  [lit] 0 asm-exp-len !
  [lit] 0 asm-def-count !
  begin,
    asm-read-token                            ( start len )
    dup [lit] 0 = if, 2drop exit, then,
    2dup asm-is-define? if,
      2drop
      asm-read-token                          ( name-a name-l )
      asm-read-token                          ( name-a name-l body-a body-l )
      asm-def-store
    else,
      \ Quoted strings: dispatch on first char.
      over c@ [char] " = if,
        asm-exp-string-double
      else,
        over c@ [char] ' = if,
          asm-exp-string-single
        else,
          2dup asm-def-find                   ( start len body-a body-l flag )
          if,
            asm-exp-bytes
            drop drop
          else,
            drop drop
            asm-exp-bytes
          then,
          bl asm-exp-emit-byte
        then,
      then,
    then,
  again, ;

```

`asm-expand-pass` is one linear walk over the source.  `DEFINE`
takes the next two tokens as name and body and writes nothing.  A
quoted token goes to its string word.  Anything else is looked up:
a defined name is replaced by its body, any other token copied as
is, and either way a space follows.  One pass is enough because
M1 files define before they use, and `bootstrap.sh` puts
`amd64_defs.M1` first.

The expanded text has no comments, no newlines and no `DEFINE`s,
which makes it much shorter: M2-Planet's self-compile input is
2,381,160 bytes of M1 (defs, ELF header, libc and program) and
755,356 bytes after expansion.  You can see the result directly by
stopping after this pass and writing the buffer to stdout:

```sh
{ cat 010-lib.fth 130-asm.fth; cat <<'FORTH'
: show-expansion
  asm-load-stdin asm-use-src asm-expand-pass
  [lit] 1 asm-exp-buf asm-exp-len @ write drop bye ;
show-expansion
FORTH
cat <<'M1'
DEFINE mov_eax, B8     # opcode of mov eax, imm32
DEFINE syscall 0F05
:_start  mov_eax, %60  # exit(...
         syscall
"hi"
M1
} | ./seed-forth   # prints ":_start B8 %60 0F05 68 69 00 "
```

The label stays, `mov_eax,` became `B8`, `%60` is still a sigil
token (passes 1 and 2 turn it into bytes), and `"hi"` became three
hex bytes.

## 12. `asm-main`

```forth file=130-asm.fth
\ Pre-baked output path: "/tmp/asm-out\0"
create asm-out-path  s, /tmp/asm-out  [lit] 0 c,

: asm-main
  asm-load-stdin
  asm-use-src
  asm-expand-pass             \ build defs table + write asm-exp-buf
  asm-use-exp
  asm-init
  [lit] 1 asm-pass !
  asm-pass-loop
  asm-reset-pos
  asm-base @ asm-ip !
  asm-out-init
  [lit] 2 asm-pass !
  asm-pass-loop
  asm-out-path asm-write-output
  bye ;

\ The caller invokes 'asm-main' (after optionally setting 'asm-base').
\ Existing pipelines append it on stdin between the Forth prelude and the M1
\ source; see tests/asm/*.sh.
```

`asm-main` reads top to bottom: load stdin, expand, pass 1, rewind,
pass 2, write, `bye`.  Pass 2 resets `asm-ip` and the output
position but not `asm-count`, since the labels from pass 1 are the
point.  Every check but 230 fires before `asm-write-output` opens
the file, so a run that dies writes no `/tmp/asm-out`; the die gates
check that too.

Unlike `120-cc-main.fth`, which ends by calling `cc-main`, this
file only defines `asm-main`.  The caller sends it on stdin after
the Forth, which leaves room to change `asm-base` first.  The seed
reads its input a byte at a time (Ch 16's `key`), so when it
executes `asm-main`, everything after that token is still unread
and `asm-load-stdin` gets exactly the M1 text:

```
cat 010-lib.fth 130-asm.fth     # define the words
printf 'asm-main\n'             # run them
cat amd64_defs.M1 ELF-amd64.hex2 libc-full.M1 program.M1
```

## 13. Capacity and failure

Every buffer and table has a cap, every sigil a code for an
undefined label, and every check mescc-tools makes on well-formed
tokens a code of its own.  Appendix G lists the sites with file and
line; this is the same table grouped by where the checks live:

| Codes | Where | Fails when |
|---|---|---|
| 230 | `asm-write-output` | `/tmp/asm-out` cannot be opened |
| 231, 234–238 | `asm-process-token` → `asm-do-ref` | `&`, `%`, `!`, `@`, `~`, `$` name an undefined label |
| 232, 233 | `asm-do-pct-ref` | `%target>base`: base or target undefined |
| 239 | `asm-load-stdin` | the source fills 4 MiB |
| 240 | `asm-exp-emit-byte` | the expansion fills 4 MiB |
| 241 | `asm-emit-byte` | the output fills 1 MiB |
| 242 | `asm-store-label` | more than 8,192 labels |
| 243 | `asm-def-store` | more than 4,096 `DEFINE`s |
| 244 | `asm-do-ref` → `asm-fit` | a label's value does not fit its field (`hex2`'s bounds) |
| 245 | `asm-do-ref` → `asm-fit` | a number does not fit its field (`M1`'s bounds) |
| 246 | `asm-do-hex` → `asm-check-hex` | a bare token is not hex: an undefined macro name |
| 247 | `asm-do-hex` → `asm-check-hex` | a hex token has an odd number of digits |

An undefined label and a misspelled macro name are the errors you
will actually meet.  Like every token error (231–238, 244–247) they
echo the token before the code:

```sh
{ cat 010-lib.fth 130-asm.fth; echo asm-main; printf ':start\n&nowhere\n'; } | ./seed-forth 2>&1; echo "exit: $?"   # prints "&nowhere\nexit: 231"
```

```sh
{ cat 010-lib.fth 130-asm.fth; echo asm-main; printf 'DEFINE syscall 0F05\n:start\nsyscal\n'; } | ./seed-forth 2>&1; echo "exit: $?"   # prints "syscal\nexit: 246"
```

`tests/asm/die-gates.sh` runs one input per code from 231 to 247
and checks both the exit status and that no `/tmp/asm-out` was left.

The last four codes are malformed input that mescc-tools refuses,
refused here too, and each is checked against the tool it copies.  `tests/asm/die-gates.sh` has a gate
for each; the bounds of 244 and 245 were compared at their edges
with GCC-built `M1` and `hex2` (`!` 127 bytes ahead passes, 128
dies; `!256` passes, `!257` dies), and `mescc-tools-check.sh` and
`m2planet-check.sh` still match byte for byte, since well-formed
input never reaches them.

What is left is where the Forth assembler is *stricter*, never
looser.  It refuses `'1 2'` (247), which `hex2` reads as 0x12, and
the forms in the "not implemented" list (a `<` or `^` token, a
quoted `DEFINE` body) die with 246.  And one silent difference
remains: an undefined name that happens to be an even run of hex
digits, such as `face`, is two bytes to the Forth assembler, which
reads `ELF-amd64.hex2`'s raw hex through the same path, where `M1`
would call it "invalid other".  None of this arises in the inputs
`bootstrap.sh` feeds it, and the byte-identity checks below would
catch it if it did.

## 14. In the chain

`bootstrap.sh` calls this program through one shell function:

```sh
# (from bootstrap.sh)
forth_asm() {
    local name=$1 m1=$2 dest=$3
    local L=$M2_PLANET/M2libc/amd64
    { cat 010-lib.fth 130-asm.fth
      printf 'asm-main\n'
      cat "$L/amd64_defs.M1" "$L/ELF-amd64.hex2" "$L/libc-full.M1" "$m1"
    } > "$WORK/forth-asm-$name.in"
    run_forth "$WORK" "$WORK/forth-asm-$name.in" asm-out "$dest"
}
```

Step 3 uses it on `self-v1-amd64.M1` to make `cc-out-v2-fasm`, an
M2-Planet that no C-built tool has touched.  Step 4 has that
M2-Planet compile mescc-tools' `M1-macro.c` and `hex2*.c`, and uses
`forth_asm` twice more to make the `M1` and `hex2` binaries.  After
that the Forth assembler is done, and three checks hold it to
account:

- **Step 5, two assemblers agree.**  The new `M1` and `hex2`
  assemble `self-v1-amd64.M1` into `cc-out-v2`, which must equal
  `cc-out-v2-fasm` byte for byte.
- **Step 7, the tools reproduce themselves.**  `M1` and `hex2`,
  rebuilt from source by the v3 M2-Planet and assembled by
  themselves, must equal the ones `130-asm.fth` made.
- **Against GCC, outside the chain.**  `tests/asm/*-check.sh`
  compare the Forth assembler with GCC-built mescc-tools on small
  fixtures (`exit42`, `jump42`, `m1-jump42`), on M2-Planet, and on
  `M1` and `hex2` themselves; `./verify.sh` runs them.

`./handoff.sh` then hands `bootstrap.sh`'s M2-Planet, `M1` and
`hex2` to stage0-posix's own recipe in place of hex1, hex2, M0 and
`cc_amd64`, and gets stage0-posix's published binaries back
(Appendix C).  The last tools the Forth route needed from outside,
the assembler and linker, are now built by it.

## Try it

**Small check:** a complete program, ELF header included, written
by hand in M1, assembled by the Forth assembler, and run.  It uses
`&`, `!` and both forms of `%`, a string and `DEFINE`s.

```sh
cat > /tmp/hi.M1 <<'M1'
DEFINE mov_eax, B8
DEFINE mov_edi, BF
DEFINE mov_esi, BE
DEFINE mov_edx, BA
DEFINE jmp8 EB
DEFINE syscall 0F05

:ELF_base                                   # the file loads at 0x600000
'7F454C46 02 01 01 03 00 00000000000000'    # e_ident
'0200 3E00 01000000'                        # ET_EXEC, AMD64, version 1
&_start '00000000'                          # e_entry
%ELF_phdr>ELF_base '00000000'               # e_phoff
'0000000000000000 00000000'                 # e_shoff, e_flags
'4000 3800 0100 0000 0000 0000'             # sizes; one program header
:ELF_phdr
'01000000 07000000 0000000000000000'        # PT_LOAD, RWX, offset 0
&ELF_base '00000000' &ELF_base '00000000'   # vaddr, paddr
%ELF_end>ELF_base '00000000'                # filesz
%ELF_end>ELF_base '00000000'                # memsz
'0100000000000000'                          # align

:_start
    mov_eax, %1  mov_edi, %1                # write(1,
    mov_esi, &msg  mov_edx, %3              #   msg, 3)
    syscall
    jmp8 !done                              # hop over the data
:msg "hi
"
:done
    mov_eax, %60  mov_edi, %42  syscall     # exit(42)
:ELF_end
M1
{ cat 010-lib.fth 130-asm.fth; echo asm-main; cat /tmp/hi.M1; } | ./seed-forth
/tmp/asm-out                     # prints "hi"
echo "exit: $?"                  # prints "exit: 42"
wc -c < /tmp/asm-out             # prints: 160
cp /tmp/asm-out /tmp/hi-forth    # kept for the comparison below
```

The header has the 120-byte layout of Ch 25's, one ELF header and
one program header, and the sizes the compiler back-patches
(`p_filesz`, `p_memsz`) are `%ELF_end>ELF_base` here: the linker
works them out in pass 2.  The raw hex is single-quoted so that
mescc-tools' `M1` accepts the same file; the Forth assembler would
take it bare.

**Layer check:** `tests/asm/` holds the assembler's own checks.  The
three fixtures and the die gates are `check-all.sh`'s `02a-asm` step,
which needs gcc to build the references the fixtures compare
against:

```sh
tests/asm/exit42-check.sh
tests/asm/jump42-check.sh
tests/asm/m1-jump42-check.sh
tests/asm/die-gates.sh
```

**Bootstrap relevance:** build `M1` and `hex2` the way the chain
does, then let them check the Forth assembler on the program above
(still in `/tmp/hi.M1`).
`bootstrap.sh` takes about 30 s; its step 4 is this chapter's
payoff.

```sh
./bootstrap.sh                   # ... ok: M1: 52808 bytes, hex2: 56707 bytes
B=build-out/out
$B/M1 --little-endian --architecture amd64 -f /tmp/hi.M1 -o /tmp/hi.hex2
$B/hex2 --little-endian --architecture amd64 --base-address 0x00600000 \
    -f /tmp/hi.hex2 -o /tmp/hi
cmp /tmp/hi /tmp/hi-forth && echo same   # same
```

`/tmp/hi.hex2` is the intermediate form of §1: `M1`'s output, macros
and numbers gone, labels still symbolic.  `hex2` resolves them, and
`cmp` finds no difference from what the Forth assembler wrote.

## Exercises

1. **★ Trace.** In the Try-it program, `jmp8 !done` assembles to
   `EB 04`.  Using the label addresses (`_start` is 0x600078), work
   out where the field ends and why the displacement is 4.

2. **★★ Verify.** Write `EB !far` followed by exactly 127 bytes of
   `'00'` and then `:far`, and assemble it with the Forth assembler
   and with the bootstrapped `M1` and `hex2`.  Add one more byte of
   padding and do it again.  Both tools should accept the first and
   refuse the second; which message does each print?  Now move the
   label *before* the jump: how many bytes of padding can a backward
   `!` cross, and why is that one fewer than forward?

3. **★★ Modify.** `M1` accepts `!256` and writes `00`, because its
   1-byte bound is wider than the byte.  Change `asm-number-bounds`
   to hex2's signed rule and run `tests/asm/mescc-tools-check.sh`
   and `m2planet-check.sh`.  Do they still pass?  What would it take
   to be sure no amd64 input the chain feeds the assembler writes a
   1-byte number above 127, and is the stricter rule worth the
   disagreement with `M1`?

4. **★★★ Extend.** `asm-find-label` is a linear scan, run once per
   label reference in pass 2 over up to 4,023 labels for M2-Planet.
   Time the three `forth_asm` runs in `bootstrap.sh`, then replace
   the scan with a hash table over the same records.  What must stay
   true for the output to remain byte-identical (hint: duplicate
   labels, newest wins)?

5. **★★★ Extend.** `130-asm.fth` duplicates about forty lines of
   `020-cc-arena.fth` and `030-cc-io.fth` (§5).  Sketch a shared
   `015-io.fth` both programs could load.  What would it have to
   leave out to keep the assembler's audit independent of the
   compiler's state, and would the trade be worth it?

## After this chapter

The assembler turns M1 into an ELF in three steps over text already
in memory: expand `DEFINE`s and strings into a second buffer, walk it
once to give every label an address, walk it again to write bytes
with every address known.  One handler, `asm-do-ref`, serves all six
sigils, parameterised by width, relativity and error code.  It loads
on `010-lib.fth` alone, and `bootstrap.sh` uses it to build `M1` and
`hex2` from source, after which the chain no longer needs it.

You can read any line of M2-Planet's `.M1` output and say which
bytes it becomes and at what address, trace a label from its
declaration in pass 1 to every reference in pass 2, and say which
malformed input dies with which code, and which of mescc-tools' two
tools the check was copied from.

## Takeaways

- An M1 assembler is a macro expander in front of a two-pass hex2 linker: pass 1 only counts bytes to place labels, which works because every token's size is known without knowing any label's value.
- The six sigils differ only in field width and in absolute versus end-of-field-relative addressing, so one handler serves them all, plus `%target>base` for sizes.
- `130-asm.fth` depends on `010-lib.fth` alone, so the assembler that removes the last GCC-built tools from the chain can be audited without reading the compiler.

That is the end of the main book.  You started from 1,772
hand-encoded bytes and read, in source, every step to a C compiler
whose Stage-A `.M1` output matches M2-Planet built with GCC, and to
the assembler that turns that output into running programs.  The
Prologue named two things that had to work together: a mechanical
test that fluent-looking code cannot fake, and a literate program
that keeps a human able to read every line.  Stage A and the
byte-identity checks of this chapter are the first; the
thirty-three chapters you just read are the second.

What that leaves you with is concrete.  Pick any of the 1,241 bytes
of tri.c's binary and you can name the Forth word that wrote it, the
chapter that walks that word, and the seed primitives underneath.
Pick any byte of `bootstrap.sh`'s `M1` or `hex2` and you can name
the `.M1` line it came from and the assembler word that placed it.
Run `stage-a-check.sh` and you can watch the M2-Planet built by GCC
and the one this book's compiler built emit the same `.M1`, byte for
byte.  Run `tests/cc/stage0-check.sh` and you can watch this route
and stage0-posix's, from the same 229-byte seed through independent
compilers, reach the same M2-Planet binary one generation later;
run `./handoff.sh` and stage0-posix's own recipe, fed by this route,
produces its 19 published binaries.  And when someone asks where your
compiler came from, you can point to a file of hex you have read, and
to every line of source between it and the output.

The appendices are reference cards for a second pass:

- **[A — The 32 seed primitives](A1-32-seed-primitives.md):** every
  primitive in one table.
- **[B — The memory map](A2-memory-map.md):** every fixed address
  the book referenced.
- **[C — The reproducibility chain](A3-reproducibility-chain.md):**
  hex0 → seed → M2-Planet with commands and expected hashes.
- **[D — Worked exercises](A4-worked-exercises.md):** three
  exercises walked end to end.
- **[E — Further reading](A5-further-reading.md):** Forth,
  compilers, bootstrap, ELF/x86-64: the older work this book
  stands on.
- **[F — The C subset](A6-c-subset.md):** types, operators,
  statements, and the features that are *not* in this compiler.
- **[G — Compiler exit codes](A7-error-codes.md):** status codes
  mapped to failure modes for when something dies on you, the
  assembler's 230–249 included.
