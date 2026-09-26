# Chapter 21 — Arena and I/O Buffers

```text
Missing capability: the compiler has nowhere to keep input bytes or emitted output.
New pattern: fixed buffers plus a tiny arena separate owned memory by responsibility.
Artifact after this chapter: a source reader, an output writer, and a bump allocator.
Proof link: later stages can assemble /tmp/cc-out deterministically for Stage-A checks.
```

Here is a 22-line C program, `tri.c`:

```c
#define ROWS 4
struct tri { int rows; int stars; };
struct tri t;

void line(int pad, int n) {
    while (pad > 0) { putchar(' '); pad = pad - 1; }
    while (n > 0) { putchar('*'); n = n - 1; }
    putchar('\n');
}

int main() {
    int w[ROWS];
    int r;
    t.rows = ROWS;
    for (r = 0; r < t.rows; r = r + 1) {
        w[r] = 1 + r * 2;
        line(t.rows - 1 - r, w[r]);
        t.stars = t.stars + w[r];
    }
    if (t.stars == ROWS * ROWS) return t.stars;
    return 1;
}
```

The compiler Part III builds turns these 484 bytes into a
1,241-byte x86-64 executable that prints

```text
   *
  ***
 *****
*******
```

and exits with status 16, the number of stars.  No assembler, linker
or libc takes part: every one of the 1,241 bytes is written by Forth
words loaded on top of the 1,772-byte seed.  How do 22 lines become
those bytes?  `tri.c` is Part III's running example, and every
chapter from here to Ch 32 shows it at that chapter's stage.  This
chapter's Try it compiles it.

The first answer is plain bookkeeping.  The 484 bytes need somewhere
to land, and the 1,241 need somewhere to accumulate before they reach
disk.  Part III uses the seed's Forth to host a compiler for a small
subset of C: enough to rebuild M2-Planet, whose binary is the next
link in the Guix Full Source Bootstrap chain.  The compiler is split
across eleven files (`020-cc-arena.fth` through `120-cc-main.fth`),
loaded in numerical order on top of `010-lib.fth`.  This chapter
covers the first two: a bump allocator, and the source reader and
output writer.

## The main byte path

Ch 20 closed by naming Part III's three recurring motifs: emit,
remember, patch; small tables with newest-wins lookup; one buffer per
responsibility.  The first and third show up in this chapter's two
files.  Before reading them, here is the whole compiler at a glance,
as `cc-main` in `120-cc-main.fth` drives it:

```text
  stdin (C source)
    |  cc-load-stdin (030)
    v
  cc-src-buf
    |
    v
  preprocessor (040) ------------------> macro table (040)
    |  splices #include "..." files,        #define NAME N
    |  drops other directive lines
    v
  cc-prep-out-buf
    |  cc-prep-copy-back: copied over cc-src-buf, cursor rewound
    v
  lexer (050) <------------------------- macro table lookup
    |  one token at a time into tok-* globals; an identifier
    |  that names a macro becomes a number token
    v
  parser + codegen: 100 (expressions), 110 (declarations,
    |  statements, functions); x86-64 encoders in 090
    v
  cc-out-buf
    |  [ELF header, 080: emitted before parsing starts]
    |  [entry stub, libc shims, function bodies]
    |  [globals, appended by cc-finalize-globals]
    |  cc-finalize-elf (080) patches p_filesz / p_memsz
    v
  cc-write-output (030) ---> /tmp/cc-out (ELF executable)

  shared state across the stages:
    020 arena    060 type words    070 symbol table + scope stack
```

The ELF writer is not a stage at the end of the line.  Ch 25's
`cc-emit-elf-header` writes the 120-byte header into `cc-out-buf`
before the parser runs, with the size fields left at zero, and
`cc-finalize-elf` patches them once the last byte is known.

## 1. The arena: a 41-line bump allocator

Most of the compiler's state lives in fixed-size parallel arrays: the
symbol table (Ch 24), the macro table (Ch 22), the label fixup table
(Ch 30).  Each is a `create NAME N allot` of pre-sized storage with a
separate counter variable.  That works for anything whose maximum
count we can pin down in advance.

A few things don't fit that mould: struct descriptors, the fixup
chains for `goto` labels and forward function references, the case
list of a `switch`.  For those we need an allocator that hands out
variable-sized blocks, and the 41-line file `020-cc-arena.fth` is
exactly that.

```forth file=020-cc-arena.fth
\ 020-cc-arena.fth — bump allocator for variable-size compiler data.
\ Used by the C compiler for: struct descriptors, call/goto fixup lists,
\ switch-case lists — anything that doesn't fit a fixed slot in a parallel
\ array.  Most compiler state lives in fixed-size buffers (parallel arrays
\ declared with `create NAME N allot`); this arena handles the rest.
\
\ Depends on 010-lib.fth: constant, variable, create, allot, [lit], if,/then,,
\ swap, dup, over, drop, +, /, *, >, !, @, syscall6.

\ ----- Storage -----
\ The buffer lives in the dictionary alongside the cc-arena-base header (it's
\ what `create` builds: a header + data area; allot extends the data area).
\ Sized to fit within 000-seed.hex0's mapped segment with room for the compiler
\ dictionary, struct descriptors, labels, and string overflow.
[lit] 32768 constant cc-arena-cap
create cc-arena-base  cc-arena-cap allot
variable cc-arena-ptr
\ Initialize the bump pointer to the base of the buffer.
cc-arena-base cc-arena-ptr !

\ ----- cc-alloc -----
\ cc-alloc ( n -- addr )  Bump n bytes (rounded up to an 8-byte boundary)
\ off the arena and return the start address of the allocation.  On exhaustion
\ the program exits with status 7 (OOM).
\
\ Stack trace:
\   ( n )
\   align up to 8:  (n+7)/8*8
\   ( n' )
\   cc-arena-ptr @ swap over +     ( old-top new-top )
\   dup cc-arena-base cc-arena-cap + >    ( old-top new-top oom? )
\   if, drop drop  exit(7)  then,
\   cc-arena-ptr !                  ( old-top )
: cc-alloc                                       ( n -- addr )
  [lit] 7 + [lit] 8 / [lit] 8 *                  \ align up to 8 bytes
  cc-arena-ptr @ swap over +                     ( old-top new-top )
  dup cc-arena-base cc-arena-cap + > if,
    drop drop
    [lit] 7 die
  then,
  cc-arena-ptr ! ;                               ( -- old-top )
```

`[lit] 32768 constant cc-arena-cap` fixes the total budget at 32 KiB.
`create cc-arena-base cc-arena-cap allot` reserves that storage
directly inside the dictionary: `create` makes a header for the name
and `allot` extends its data area by 32 768 bytes.  Forth's own
defining words serve as the compiler's `malloc`.  `cc-arena-ptr` is
the bump pointer.

The line `cc-arena-base cc-arena-ptr !` runs at load time, so the
pointer starts at the buffer's first byte.

`cc-alloc` rounds the request up to a multiple of 8 (`(n+7)/8*8`
keeps every allocation cell-aligned; later passes assume it).  It
reads the current top, computes the new top, and checks whether that
has walked past `cc-arena-base + cc-arena-cap`.  On overflow it exits
with status 7.  Otherwise it stores the new top and leaves the old top
on the stack as the address just allocated.

**No `free`.**  The arena only grows.  Every allocation lives for the
whole compilation, and the kernel reclaims everything at exit.  The
allocator is one screen long, and double-free, use-after-free and
leaks are all impossible.

**`die 7` on OOM.**  There is no recovery and no traceback; the
status code tells you which limit you hit.  Status 7
distinguishes this failure from the other `die`s (`die 1` when the
output file cannot be opened, in `030-cc-io.fth`; `die 70`/`71`/`72`
in the preprocessor for a missing `#include` file, too-deep nesting
and a full macro-name pool, introduced in Ch 22; Ch 26 reuses 70 and
71 for full global buffers).  Status codes are the compiler's only
error-reporting channel.

## 2. The source reader and output writer

The 151-line file `030-cc-io.fth` has three sections: A, the source
buffer and reader; B, the output buffer and emitters; C, the final
file write.

### The source buffer and reader

The compiler reads stdin into one large buffer, then walks it
character by character.  With the whole source in memory, the
preprocessor can rewrite it wholesale, the lexer can look ahead, and
there is no buffered I/O to negotiate on the read side.  Section A
starts by placing the buffer.

```forth file=030-cc-io.fth
\ 030-cc-io.fth — Source-buffer reader, output-buffer emitter, and file I/O
\ wrappers for the C-subset compiler.  Loaded after 010-lib.fth.
\
\ Three responsibilities:
\   A. Slurp stdin into a 1 MiB cc-src-buf and walk it via peek/next.
\   B. Accumulate the output ELF into cc-out-buf via emit-byte / 4le / 8le
\      with patch-byte / patch-4le for back-fixups.
\   C. Write cc-out-buf to a path via 010-lib.fth's open/write/close.
\
\ Depends on 010-lib.fth: constant, variable, create, allot, [lit], if,/then,/else,,
\   begin,/while,/repeat,, +, -, /, =, >, >=, 0=, +!, !, @, c!, c@, drop, dup,
\   over, swap, >r, r@, r>, syscall6, read, write, open, close.

\ ===========================================================================
\ A. Source buffer + reader
\ ===========================================================================

\ 1 MiB source cap — comfortable for M2-Planet's monolithic concatenations.
[lit] 1048576 constant cc-src-cap

\ Skip past the VM's fixed pages (data stack 0x410000..0x411000, I/O scratch
\ 0x412000, token buffer 0x412800, sysvars 0x413000..0x414000) so the 1 MiB
\ cc-src-buf does not overlap runtime VM state.  At 030-cc-io.fth load time HERE
\ is well below 0x410000, so this is a forward bump to 0x414000.
skip-vm-pages                                     \ HERE = 0x414000

create cc-src-buf  cc-src-cap allot
variable cc-src-len
variable cc-src-pos
variable cc-src-line                            \ 1-based, for error messages

```

`skip-vm-pages` is the one trick in the file.  Before
`create cc-src-buf cc-src-cap allot` reserves a megabyte of dictionary
space, it slides HERE (the dictionary's next-byte pointer, Ch 2)
forward to `0x414000`, one page above the start of the sysvar page
(Ch 12 defines it), so the buffer lives clear of the seed's reserved
pages: the data-stack page at `0x410000–0x411000` (with the stack
itself growing down from the top), the I/O scratch byte at `0x412000`,
the token buffer at `0x412800`, the sysvars at `0x413000`.  Chs 13–20
introduced those addresses.

With the buffer placed, the reader is a reset word, a load loop and
three accessors:

```forth file=030-cc-io.fth
\ cc-src-init ( -- )  Reset reader state.
: cc-src-init
  [lit] 0 cc-src-len !
  [lit] 0 cc-src-pos !
  [lit] 1 cc-src-line ! ;

\ cc-load-stdin ( -- )  Read all of fd 0 into cc-src-buf.
\ Loops until read returns 0 (EOF).  4 KiB chunks.
\ Stack note: at begin, the stack is empty.  read leaves n on TOS; dup/>
\ produces ( n flag ); while, pops flag leaving ( n ); +! pops n leaving ( ).
\ When the loop exits (n<=0), stack is ( n ) which we drop.
: cc-load-stdin
  cc-src-init
  begin,
    [lit] 0 cc-src-buf cc-src-len @ + [lit] 4096 read
    dup [lit] 0 >
  while,
    cc-src-len +!
  repeat,
  drop ;

\ cc-eof? ( -- f )  -1 if pos has reached len; 0 otherwise.
: cc-eof?  cc-src-pos @ cc-src-len @ >= ;

\ cc-peek-char ( -- c )  Returns byte at the current position; 0 at EOF.
\ Both arms of if,/else, produce exactly one value, so stack stays balanced.
: cc-peek-char
  cc-eof? if,
    [lit] 0
  else,
    cc-src-buf cc-src-pos @ + c@
  then, ;

\ cc-next-char ( -- c )  Returns current byte and advances pos.
\ Tracks line number when consuming '\n' (10).
: cc-next-char
  cc-peek-char
  [lit] 1 cc-src-pos +!
  dup [lit] 10 = if,
    [lit] 1 cc-src-line +!
  then, ;

```

`cc-load-stdin` is one `begin, while, repeat,`.  Each iteration calls
`read` with `(fd=0, buf=cc-src-buf+len, count=4096)`, duplicates the
returned count and tests it against 0.  If positive, it adds the count
to `cc-src-len` and loops; otherwise it drops it and exits.

`cc-peek-char` and `cc-next-char` are the reader interface every later
pass uses.  `peek` returns the byte at `pos` (or 0 at EOF) without
advancing.  `next` returns the same byte and advances, bumping
`cc-src-line` on newline.

### The output buffer

Section B declares the output buffer and the primitives that append
to it.

```forth file=030-cc-io.fth
\ ===========================================================================
\ B. Output buffer + ELF-aware emit helpers
\ ===========================================================================

\ 1 MiB output cap — fits any reasonable ELF the C-subset compiler emits.
[lit] 1048576 constant cc-out-cap
create cc-out-buf  cc-out-cap allot
variable cc-out-pos

\ cc-out-init ( -- )
: cc-out-init  [lit] 0 cc-out-pos ! ;

\ cc-emit-byte ( b -- )  Append a byte at cc-out-buf[cc-out-pos++].
: cc-emit-byte
  cc-out-buf cc-out-pos @ + c!
  [lit] 1 cc-out-pos +! ;

\ cc-emit-4le ( v -- )  Emit low 4 bytes of v in little-endian.
: cc-emit-4le
  dup cc-emit-byte                              \ byte 0
  [lit] 256 / dup cc-emit-byte                  \ byte 1
  [lit] 256 / dup cc-emit-byte                  \ byte 2
  [lit] 256 / cc-emit-byte ;                    \ byte 3

\ cc-emit-8le ( v -- )  Emit all 8 bytes of v in little-endian.
\ Reuses cc-emit-4le for both halves; shifts by 32 between halves.
: cc-emit-8le
  dup cc-emit-4le                                              \ low 4 bytes
  [lit] 256 / [lit] 256 / [lit] 256 / [lit] 256 /              \ shift right 32
  cc-emit-4le ;                                                \ high 4 bytes

```

`cc-emit-byte` is the obvious `c!` plus `+!` pair.  `cc-emit-4le` and
`cc-emit-8le` peel off bytes from low to high by repeated `/256`.
These mirror `010-lib.fth`'s `,4` and `,8` (Ch 9), but write into
`cc-out-buf` rather than at the dictionary's HERE.

The emitters only append.  Fixing up bytes already written takes a
second family that writes at an explicit offset:

```forth file=030-cc-io.fth
\ cc-out-patch-byte ( v offset -- )  Overwrite cc-out-buf[offset] with low byte of v.
: cc-out-patch-byte  cc-out-buf + c! ;

\ cc-out-patch-4le ( v offset -- )  Overwrite 4 bytes at offset (LE).
\ Stash offset on the return stack so we can compute offset+1, +2, +3.
: cc-out-patch-4le
  >r                                                  ( v       ; R: offset )
  dup r@                       cc-out-patch-byte      ( v       ; R: offset )
  [lit] 256 / dup r@ [lit] 1 + cc-out-patch-byte      ( v>>8    ; R: offset )
  [lit] 256 / dup r@ [lit] 2 + cc-out-patch-byte      ( v>>16   ; R: offset )
  [lit] 256 /     r> [lit] 3 + cc-out-patch-byte ;    ( v>>24>>8 popped )

\ cc-out-patch-8le ( v offset -- )  Overwrite 8 bytes at offset (LE).
: cc-out-patch-8le
  >r                                                  ( v       ; R: offset )
  dup r@                       cc-out-patch-byte      ( v       ; R: offset )
  [lit] 256 / dup r@ [lit] 1 + cc-out-patch-byte
  [lit] 256 / dup r@ [lit] 2 + cc-out-patch-byte
  [lit] 256 / dup r@ [lit] 3 + cc-out-patch-byte
  [lit] 256 / dup r@ [lit] 4 + cc-out-patch-byte
  [lit] 256 / dup r@ [lit] 5 + cc-out-patch-byte
  [lit] 256 / dup r@ [lit] 6 + cc-out-patch-byte
  [lit] 256 /     r> [lit] 7 + cc-out-patch-byte ;

```

`cc-out-patch-4le` stashes `offset` on the return stack with
`>r`/`r@`/`r>` (Ch 4) so the four byte-writes can each compute
`offset+0` through `offset+3`.  This is Ch 11's emit-remember-patch
pattern, moved from dictionary branch slots to `cc-out-buf` offsets.
Ch 25 uses it for ELF header fields whose values aren't known until
the rest of the file is laid out.

### Writing the file

Section C writes the buffer to a path.

```forth file=030-cc-io.fth
\ ===========================================================================
\ C. Output file write
\ ===========================================================================
\ Open flags (Linux x86-64 asm-generic):
\   O_WRONLY=1, O_CREAT=64, O_TRUNC=512  →  bitwise OR = 577.
\ Mode 0o755 = decimal 493.
\
\ 010-lib.fth's `open` already takes ( path flags mode -- fd ) — its signature
\ matches what we need, so no open3 wrapper is required here.

\ cc-write-output ( path-addr -- )  path-addr must point at NUL-terminated bytes.
\ Opens path with O_WRONLY|O_CREAT|O_TRUNC, mode 0755; writes
\ cc-out-buf[0..cc-out-pos@] to it; closes.  On open failure (fd < 0),
\ exits with status 1 (cannot recover — we have no place to write a diagnostic).
: cc-write-output
  [lit] 577 [lit] 493 open                        ( fd )
  dup [lit] 0 < if,
    drop
    [lit] 1 die
  then,
  >r                                              ( ; R: fd )
  r@ cc-out-buf cc-out-pos @ write drop           \ write all bytes
  r> close drop ;
```

Flag `577 = O_WRONLY|O_CREAT|O_TRUNC` and mode `493 = 0o755` are the
only magic numbers in the file, and the comment derives both.  On open
failure (`fd < 0`) the compiler exits with status 1, for the same
reason as the arena: there is nowhere to write a diagnostic.

## 3. Why one big buffer instead of streaming?

A streaming compiler would pipe characters through lexer, parser and
emitter with no intermediate buffers.  This one reads everything,
walks it, then writes everything out.

Streaming wins on memory when the source is huge; buffering wins on
simplicity when it is small.  M2-Planet's largest single translation
unit is about 200 KiB, so a 1 MiB cap leaves headroom, and two
megabytes of address space buy a compiler with no I/O interleaving to
reason about.

Several passes also want random access.  The lexer peeks two bytes
ahead to tell `/` from `//` and `0` from `0x`.  The preprocessor
rewrites the whole source into a second buffer and copies it back over
the first.  The code emitter patches ELF header fields.

This is "one buffer per responsibility" in its simplest form: source
traversal, preprocessor output, emitted ELF bytes and global data
each get an owner and a cursor.

## 4. How the buffers connect to what's coming

The rest of Part III reaches for these pieces by name.  Ch 22 walks
`cc-src-buf` with its own cursor and copies its result back over it;
Ch 23 reads it through `cc-peek-char` / `cc-next-char` and never backs
up.  Ch 24's struct descriptors and Ch 26's forward-call fixup chains
come from `cc-alloc`.  Chs 25, 26 and 29–31 emit into `cc-out-buf` and
back-patch with `cc-out-patch-4le` / `cc-out-patch-8le`, and Ch 32
calls `cc-write-output` last.

## Try it

**Small check:** the repo test script runs the focused probes for
this chapter's two mechanisms, `test-020-cc-arena.fth` and
`test-030-cc-io.fth`.

```sh
./build.sh
./test.sh         # runs test-020-cc-arena.fth and test-030-cc-io.fth
                  # alongside the lexer / types / sym tests.
```

`test-020-cc-arena.fth` exercises `cc-alloc` at several sizes and
asserts the returned addresses are 8-aligned and non-overlapping;
`test-030-cc-io.fth` round-trips bytes through `cc-emit-byte` and
`cc-out-patch-4le`.

**Bootstrap relevance:** the Stage-A gate uses these buffers for every
input byte and every emitted output byte, starting with the smallest C
test case.

```sh
./build.sh && tests/cc/stage-a-check.sh
```

That driver has `seed-forth` compile the M2-Planet monolith, runs the
result on M2-Planet's own sources, and `cmp`s the `.M1` text it
writes against a GCC-built M2-Planet's.

**tri.c at this stage:** compile the running example, then replay
`cc-main`'s steps by hand to watch the buffers fill.  The second
pipeline loads every file except `120-cc-main.fth` (whose last line
runs `cc-main`) and prints a cursor after each step:

```sh
./build.sh
tri() { cat <<'C'
#define ROWS 4
struct tri { int rows; int stars; };
struct tri t;

void line(int pad, int n) {
    while (pad > 0) { putchar(' '); pad = pad - 1; }
    while (n > 0) { putchar('*'); n = n - 1; }
    putchar('\n');
}

int main() {
    int w[ROWS];
    int r;
    t.rows = ROWS;
    for (r = 0; r < t.rows; r = r + 1) {
        w[r] = 1 + r * 2;
        line(t.rows - 1 - r, w[r]);
        t.stars = t.stars + w[r];
    }
    if (t.stars == ROWS * ROWS) return t.stars;
    return 1;
}
C
}
{ cat 010-lib.fth [0-9][0-9][0-9]-cc-*.fth; tri; } | ./seed-forth
/tmp/cc-out                         # draws the triangle
echo "exit: $?"                     # prints "exit: 16"
{ cat 010-lib.fth 0[2-9]0-cc-*.fth 1[01]0-cc-*.fth
  cat <<'FORTH'
: .d  dup [lit] 9 > if, dup [lit] 10 / .d then,
      dup [lit] 10 / [lit] 10 * - [lit] 48 + emit ;
: .n  .d [lit] 32 emit ;
: steps
  cc-load-stdin        cc-src-len @ .n
  cc-preprocess        cc-src-len @ .n
  cc-out-init cc-globals-init
  cc-emit-elf-header   cc-out-pos @ .n
  cc-parse-program     cc-out-pos @ .n
  cc-finalize-globals  cc-out-pos @ .n
  cc-arena-ptr @ cc-arena-base - .d  bye ;
steps
FORTH
  tri; } | ./seed-forth             # prints "484 470 120 1225 1241 656"
```

`cc-load-stdin` puts all 484 bytes of `tri.c` in `cc-src-buf`; the
preprocessor (Ch 22) leaves 470.  `cc-out-buf` holds the 120-byte ELF
header (Ch 25) before a single token is parsed, 1,225 bytes once both
functions are compiled, and 1,241 once the 16 bytes of the global `t`
are appended (Ch 26).  The last number is the arena: 656 bytes, one
struct descriptor for `struct tri` (Ch 24), and the only allocation
this program makes.  `cc-finalize-elf` and `cc-write-output` then
send those 1,241 bytes to `/tmp/cc-out` in one `write`.

## Exercises

1. **★★★ Verify.** The arena is 32 KiB.  Could you reduce it to 16 KiB without
   breaking M2-Planet compilation?  How would you measure?  (Hint:
   instrument `cc-alloc` to record peak `cc-arena-ptr`.)

2. **★★ Verify.** The source buffer is 1 MiB.  What's the actual peak source size
   for M2-Planet?  Could you tighten this and save 800 KiB of
   virtual address space?

3. **★★ Trace.** `cc-out-patch-4le` writes 4 bytes one at a time.  Could you
   write a faster `patch-cell-le` using `!` and some shuffling?
   Would it be worth the bytes-of-code?

4. **★★ Modify.** Add `cc-emit-string ( c-addr u -- )` that emits `u` bytes from
   `c-addr` to the output buffer.  Use it to emit a hardcoded
   "Hi\n" greeting and confirm.

5. **★★ Trace.** The arena's OOM path exits with status 7.  Trace which
   compiler-side failures use which status (`die N`) and assemble
   a table.  Where should new failure modes draw their numbers
   from?

## After this chapter

The compiler has a deterministic memory model: stdin lands in
`cc-src-buf`, emitted bytes accumulate in `cc-out-buf` and reach disk
in one `write`, and the arena handles anything that doesn't fit a
fixed slot.  Every byte the Stage-A check compares passes through
these buffers.  But `tri.c`'s 484 bytes are not yet C a parser can
use: line 1, `#define ROWS 4`, is an instruction to a preprocessor,
and Ch 22 has to decide what to do with it.

## Takeaways

- The C compiler's memory model is two big in-memory buffers plus a small overflow arena, all inside the 16 MiB segment from the ELF program header (Ch 13), with no `malloc` or `mmap`.
- Reading and writing are batched: stdin arrives in one chunked loop, and the output leaves in one `write` after the whole ELF is laid out.
- Back-patching through `cc-out-patch-4le` and `cc-out-patch-8le` handles forward references inside the emitted ELF, the same trick `if,` uses for Forth-level control flow in Ch 11.

Next: Chapter 22 — The Preprocessor.
