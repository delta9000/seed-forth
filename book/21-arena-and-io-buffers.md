# Chapter 21 — Arena and I/O Buffers

```text
Missing capability: the compiler has nowhere to keep input bytes or emitted output.
New pattern: fixed buffers plus a tiny arena separate owned memory by responsibility.
Artifact after this chapter: a source reader, an output writer, and a bump allocator.
Proof link: later stages can assemble /tmp/cc-out deterministically for Stage-A checks.
```

Part III opens with the first two files of the C compiler written
in Forth, both of them deliberately uneventful infrastructure.
`020-cc-arena.fth` (41 lines, entire file) is an 8-byte-aligned bump
allocator that hands out variable-sized blocks for struct
descriptors, label-fixup overflow, and string-pool entries; it
fails loudly with `die 7` on exhaustion.  `030-cc-io.fth` (151
lines, entire file) gives the compiler its two buffers: a 1 MiB
source buffer at `0x414000+` filled by `cc-load-stdin` and walked
by the `cc-peek-char` / `cc-next-char` reader (with line tracking
for error messages), and a 1 MiB output buffer written via
`cc-emit-byte`, `cc-emit-4le`, `cc-emit-8le` and back-patched
through `cc-out-patch-*` so that header fields like `e_shoff` and
segment sizes can be filled in after layout is known.

By the end of the chapter you'll be able to explain the arena's
exhaustion behaviour, trace a single byte from stdin through
`cc-peek-char` into a lexer call, and read the output-buffer writer
with enough fluency to see why the whole ELF is accumulated in
memory before any `write` syscall fires.  The ELF-header bytes that
`cc-emit-4le` and `cc-emit-8le` actually emit are Ch 25; how the
lexer consumes `cc-next-char` is Ch 23.

---

Part II finished with the seed standing on its own legs: an ELF
binary that reads tokens, finds them in the dictionary, executes or
compiles them, and exits.  Part III is the payoff.  We use that
Forth to host a compiler for a small subset of C — enough to rebuild
M2-Planet, whose binary is the next link in the Guix Full Source
Bootstrap chain.

The C compiler is split across eight files (`020-cc-arena.fth`
through `120-cc-main.fth`), loaded in numerical order on top of
`010-lib.fth`.  This chapter covers the first two: the memory
allocator the compiler reaches for when a fixed-size slot won't do,
and the buffered I/O it uses to read source and emit ELF.

Nothing here is dramatic.  The arena is 41 lines.  The reader and
writer together are 151.  Their job is to be boring — to give the
later passes a uniform memory model so the interesting code can be
about C, not about `mmap`.

## Part III's repeated shapes

Before the first source block, it helps to name the patterns that
will keep coming back.  This compiler favors fixed buffers, parallel
arrays, integer IDs, newest-first linear lookup, and explicit
emit/remember/patch sequences.  Those choices are not shortcuts
around "real" compiler design; they are the normal shape of this
bootstrap artifact.  M2-Planet is a known target, the input set is
bounded, and predictable memory beats general allocation machinery.

The main byte path is:

```text
stdin
  -> cc-src-buf
  -> cc-prep-out-buf
  -> cc-src-buf
  -> lexer/parser
  -> cc-out-buf + globals
  -> /tmp/cc-out
```

Keep that path in mind as the chapters add pieces to the compiler.
Ch 22 rewrites source into a flatter stream.  Ch 23 turns that
stream into token globals.  Ch 24 gives names and C types compact
runtime representations.  Chs 25-31 then emit, remember, and patch
bytes until Ch 32 can compare the resulting `.M1` text with the
GCC-built reference.

## 1. The arena: a 41-line bump allocator

Most of the compiler's state lives in *fixed-size parallel arrays*
that we'll meet in later chapters: the symbol table (Ch 24), the
macro table (Ch 22), the label fixup table (Ch 30).  Each is a
`create NAME N allot` of pre-sized storage with a separate counter
variable.  That works for anything whose maximum count we can pin
down at compile time.

A few things don't fit that mould — struct descriptors of variable
arity, label fixup chains that occasionally overflow, string pool
entries.  For those we need a fly-weight allocator that hands out
*variable-sized* blocks.  This is what `020-cc-arena.fth` provides.

```forth file=020-cc-arena.fth
\ 020-cc-arena.fth — bump allocator for variable-size compiler data.
\ Used by the C compiler for: struct descriptors, label fixup overflow lists,
\ string pool overflow — anything that doesn't fit a fixed slot in a parallel
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

Read top to bottom.  `[lit] 32768 constant cc-arena-cap` fixes the
total budget at 32 KiB.  `create cc-arena-base cc-arena-cap allot`
allocates that storage directly inside the dictionary — `create`
makes a header for the name and `allot` extends the data area by
32 768 bytes.  `cc-arena-ptr` is the bump pointer.

```
   (V) (V)
   ( o.o )   "Forth's defining-words, repurposed as the C compiler's
   /\/\/\     `malloc`.  same primitive, different aisle."
```

The initialisation line `cc-arena-base cc-arena-ptr !` runs
*immediately* — it executes during file load, the moment its tokens
are read.  By the time `cc-alloc` is ever called, the pointer
already aims at the first byte of the buffer.

`cc-alloc` itself is one long stack-effect chain.  Round the request
up to a multiple of 8 (`(n+7)/8*8` keeps every allocation
cell-aligned, even on a 64-bit machine that doesn't strictly
require it — the compiler's later passes assume cell alignment).
Read the current top, compute the new top, check whether it has
walked past `cc-arena-base + cc-arena-cap`, and on overflow exit
with status 7.  Otherwise store the new top and leave the old top
on the stack as the address you just allocated.

Two design choices are worth pausing on.

**No `free`.**  The arena only grows.  Every allocation lives for
the lifetime of the compilation; when the process exits the kernel
reclaims everything.  That makes the allocator one screen long, and
it makes reasoning about lifetimes trivial.  We will never
double-free, never use-after-free, never leak — the absence of
deallocation makes all three impossible.

**`die 7` on OOM.**  The compiler has no way to recover from
arena exhaustion, so it doesn't try.  Status 7 distinguishes this
failure mode from the other `die`s the compiler uses (`die 1` when
the output file cannot be opened, in `030-cc-io.fth`; `die 70`/`71`/
`72` for various pool overflows in the preprocessor and codegen,
introduced in Chs 22 and 26).  Status codes are the compiler's only
error-reporting channel; we'll see them used throughout Part III.

```
   ,___,
   [o,o]   "exit 7 on OOM means no traceback, no recovery.
   (")_)    you find out which limit you blew by reading
            the source.  the compiler is small enough that this
            is fine, actually."
```

## 2. The source reader

The compiler reads stdin into one large buffer, then walks it
character by character.  That's a deliberate choice: with the whole
source in memory, the preprocessor can rewrite spans in place, the
lexer can back up, and we never have to negotiate buffered I/O on
the read side.

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
\ is well below 0x414000, so this is a forward bump of a few KiB.
[lit] 4276224 here-addr !                         \ 0x414000

create cc-src-buf  cc-src-cap allot
variable cc-src-len
variable cc-src-pos
variable cc-src-line                            \ 1-based, for error messages

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

The file's three sections divide the work cleanly.

**Section A** declares the source buffer.  `[lit] 4276224
here-addr !` is the small trick: before `create cc-src-buf
cc-src-cap allot` reserves a megabyte of dictionary space, we slide
`here-addr` (the dictionary's HERE pointer, Ch 2) forward to
`0x414000` so the buffer lives clear of the seed's reserved pages
— the data-stack page at `0x410000–0x411000` (with the stack itself
growing down from the top), the I/O scratch byte at `0x412000`, the
token buffer at `0x412800`, the sysvars at `0x413000`.  We met those
addresses in Chs 13–20.

`cc-load-stdin` is one `begin, while, repeat,`.  Each iteration
calls `read` with `(fd=0, buf=cc-src-buf+len, count=4096)`,
duplicates the returned count, tests it against 0; if positive,
adds it to `cc-src-len` and loops; otherwise drops it and exits.
This is the standard chunked-read loop you would write in any
language; in this Forth it costs five lines.

`cc-peek-char` and `cc-next-char` are the reader interface every
later pass uses.  `peek` returns the byte at `pos` (or 0 at EOF) but
doesn't advance.  `next` returns the same byte and advances, with
an extra branch to bump `cc-src-line` on newline.  Line numbers are
strictly informational — used only for error messages — but
threading them through here means every caller gets them for free.

**Section B** declares the output buffer and the emit primitives.
`cc-emit-byte` is the obvious `c!` + `+!` pair; `cc-emit-4le` and
`cc-emit-8le` peel off bytes from low to high by repeated `/256`.
These mirror `010-lib.fth`'s `,4` and `,8` (Ch 9), except they
write into `cc-out-buf` rather than the dictionary's HERE.

Notice that `cc-emit-4le` is a stack-only function: no temporary
variable, just `dup; emit; /256; dup; emit; …`.  The Forth-style
chain pays for itself in clarity once you've read a few of these.

The `patch` family is the same idea backwards: write into
`cc-out-buf[offset]` rather than at the cursor.  `cc-out-patch-4le`
stashes `offset` on the return stack via `>r`/`r@`/`r>` (Ch 4) so
the four byte-writes can each compute `offset+0`, `offset+1`,
`offset+2`, `offset+3`.  We'll see in Ch 25 why patching matters:
ELF headers contain offsets and sizes that aren't known until the
rest of the file is laid out.

This is the same emit, remember, patch pattern from Ch 11, now
lifted from dictionary HERE to `cc-out-buf` offsets.  Later compiler
chapters will remember file offsets instead of Forth branch slots.

**Section C** writes the buffer to a path with `open` + `write` +
`close`.  Flag `577 = O_WRONLY|O_CREAT|O_TRUNC` and mode `493 =
0o755` are the only magic numbers in the file; we compute them
once in the comment so they don't need to recur as `0x241` and `0o755`
in the code.  On open failure (`fd < 0`) the compiler exits with
status 1 — same "no place to write a diagnostic" reasoning as the
arena.

## 3. Why one big buffer instead of streaming?

A more "modern" compiler would stream characters through a lexer
that fed a parser that fed a code emitter — no intermediate
buffers, only state machines.  This compiler does the opposite:
read everything into memory, walk it, then write everything out.

The bytes go the other way too: a streaming design wins on memory
when the source is huge; the buffered design wins on simplicity
when the source is small.  M2-Planet's largest single translation
unit is about 200 KiB.  At a 1 MiB cap we have headroom; at the
cost of two megabytes of address space (source + output) we get a
compiler that has no I/O concurrency to reason about and no
intermediate representation to design.

There's a deeper reason too.  Several passes *want* random access:
the lexer needs to back up after a one-character lookahead failure,
the preprocessor needs to splice macro bodies in place, the code
emitter needs to patch ELF header fields.  Streaming versions of
each are possible but more complex; the buffered design makes them
trivial.

This is "one buffer per responsibility" in its simplest form:
source traversal, preprocessor output, emitted ELF bytes, and later
global data each get an owner and a cursor instead of sharing one
mutable stream.

## 4. How the buffers connect to what's coming

The pieces declared here are reached for, by name, throughout the
rest of Part III.

- Ch 22 (preprocessor) reads from `cc-src-buf` via
  `cc-peek-char` / `cc-next-char`, and writes back into it (or
  appends `#include`d files) using `c!` directly.
- Ch 23 (lexer) reads `cc-peek-char` / `cc-next-char` and produces
  token records.  When it sees a non-token byte it can back up by
  decrementing `cc-src-pos`.
- Ch 24 stores struct descriptors via `cc-alloc`.  Ch 25's label
  fixup overflow chains use it too.
- Chs 25, 26, 29–31 emit code into `cc-out-buf` via
  `cc-emit-byte` / `cc-emit-4le` / `cc-emit-8le`, and back-patch
  with `cc-out-patch-4le` / `cc-out-patch-8le`.
- Ch 32 calls `cc-write-output` at the very end, after everything
  else has run.

That's the contract for the rest of Part III: source on the input
side via `cc-next-char`, machine code on the output side via
`cc-emit-byte`, with `cc-alloc` for whatever doesn't fit in a
fixed-size table.

## Try it

**Small check:** `test-020-cc-arena.fth` and
`test-030-cc-io.fth` are the focused probes for this chapter's two
mechanisms.

**Layer check:** run the repo test script; it includes the arena and
I/O tests alongside the adjacent compiler-unit tests.

```sh
./build.sh
./test.sh         # runs test-020-cc-arena.fth and test-030-cc-io.fth
                  # alongside the lexer / types / sym tests.
```

`test-020-cc-arena.fth` exercises `cc-alloc` at several sizes and
asserts the returned addresses are 8-aligned and non-overlapping;
`test-030-cc-io.fth` rounds-trips bytes through `cc-emit-byte` and
`cc-out-patch-4le`.

**Bootstrap relevance:** the Stage-A gate uses these buffers for
every input byte and every emitted output byte, starting with the
smallest C test case.

```sh
./build.sh && tests/cc/stage-a-check.sh
```

That driver feeds `tests/cc/G0.c` through `seed-forth` loaded with
all the `cc-*.fth` files, captures the output ELF, and diffs it
against M2-Planet's reference.  When you finish reading Part III
the same script will be the compiler's full proof of life.

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

## Takeaways

- The C compiler's memory model is two big in-memory buffers plus
  a small overflow arena.  No `malloc`, no `mmap` — just the 16
  MiB segment from the ELF program header (Ch 13).
- Reading and writing are batched: stdin in one chunked loop,
  output in one `write` after the whole ELF is laid out.
- Back-patching is how the compiler handles forward references
  inside the ELF it's emitting (the same trick `if,` uses for
  Forth-level control flow, Ch 11).

Next: Chapter 22 — The Preprocessor.
