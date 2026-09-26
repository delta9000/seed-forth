# Chapter 24 — Types and Symbols

```text
Missing capability: names and C types have no compact runtime representation.
New pattern: pack types into one word and store symbols in parallel newest-visible columns.
Artifact after this chapter: type helpers, struct descriptors, scoped symbol rows, and lookup.
Proof link: later Stage-A codegen can resolve names, scopes, sizes, and layouts consistently.
```

Ch 23 left the parser with a stream of `tok-*` tokens.  Tokens name
things, though, and nothing yet remembers what a name means.  When the
parser meets `struct tri t;` on line 3 of `tri.c`, it has to record
two facts it will need later: what type `t` has, and where `t` lives.
Eleven lines later it meets `t.rows` and has to find `t` again, with
the innermost declaration winning, and work out where `rows` sits
inside the struct.  Both kinds of fact grow during parsing, but both
have bounded sizes by the time M2-Planet's source has been read, so
the simplest data structures suffice.

The 88-line file `060-cc-types.fth` packs every C type into one
64-bit word.  There are exactly five base kinds: `void`, `char`,
`int`, `struct`, `func`.  No `short`, no `long`, no `float`, no
`double`, no unions, no enums-as-distinct-types.  Pointer depth
generalises to any level (`T**`, `T***`, …).  Struct layouts live in
descriptors allocated from Ch 21's arena.

The 154-line file `070-cc-sym.fth` is the symbol table: seven columns
of 4096 8-byte slots each, 224 KiB in all.  Every global, local,
function, struct tag, enum constant and typedef gets one row, and
`cc-scope-push` / `cc-scope-pop` give lexical scopes by remembering
and restoring the row count.  Types are *consumed* later: Ch 28 reads
them to choose byte or qword loads and strides, and Chs 29–31 use them
to size locals, globals and struct fields.

## 1. The one-word type encoding

```forth file=060-cc-types.fth
\ 060-cc-types.fth — C type encoding for the C-subset compiler.
\
\ A type is one machine word:
\   bits[ 0.. 7] = pointer depth (0 = scalar T, 1 = T*, 2 = T**, ...)
\   bits[ 8..15] = flags (reserved; e.g., signed/unsigned variants)
\   bits[16..31] = base kind (one of ty-* below)
\
\ Struct and function types use base = ty-struct / ty-func.  A struct's
\ descriptor pointer is stored in the symbol-table entry's val field
\ (resolved by the caller before any size-of/field-offset query).
\
\ Depends on 010-lib.fth: constant, [lit], if,/then,/else,, +, -, *, /, =, dup,
\   swap, drop, and, >.

[lit] 0 constant ty-void
[lit] 1 constant ty-char
[lit] 2 constant ty-int                       \ signed 64-bit
[lit] 4 constant ty-struct
[lit] 5 constant ty-func

\ ty-make ( base ptrdepth -- ty )  Pack base and ptr-depth into one word.
: ty-make
  swap [lit] 65536 *  swap +  ;               \ (base << 16) | ptr-depth

\ ty-base ( ty -- base )  Extract the base kind (bits 16..31).
: ty-base
  [lit] 65536 /  [lit] 65535 and ;            \ shift right 16, mask low 16

\ ty-ptr ( ty -- depth )  Extract pointer depth (bits 0..7).
: ty-ptr
  [lit] 255 and ;

\ ty-size ( ty -- bytes )  sizeof(T) in bytes.
\ Pointers are always 8 bytes regardless of pointee.
\ Scalars: void=0, char=1, int/func default=8.
\ Struct sizes are NOT computed here — the caller resolves the descriptor
\ pointer (stored in the symbol entry's val) and reads its size field.
: ty-size
  dup ty-ptr [lit] 0 > if,
    drop [lit] 8
  else,
    ty-base
    dup ty-void = if, drop [lit] 0  else,
    dup ty-char = if, drop [lit] 1  else,
      drop [lit] 8                            \ int / struct / func
    then, then,
  then, ;

```

A type lives in one 64-bit word.  `ty-make` builds it: shift the base
kind left by 16 (Forth has no shift operator, so multiply by 65 536)
and add the pointer depth (0 = scalar, 1 = `T*`, 2 = `T**`, ...).
Bits 8–15 are reserved for sign flags and unused here, since the only
integer type is signed 64-bit `int`.

`ty-size` shows why the depth sits in the low bits.  Any non-zero
pointer depth means "pointer, 8 bytes."  Otherwise it falls back to
the base kind: `void` is 0 bytes (only legal in `void f(void)`-style
signatures), `char` is 1 byte, and everything else (`int`, `func`,
plain `struct`) is 8.

The 8 for a struct is deliberately wrong.  `ty-size` sees only the
type word, not the struct descriptor.  When codegen needs
`sizeof(struct foo)` it looks up the struct's symbol, reads `val` to
get the descriptor pointer, and calls `cc-sd-total-size`.  Every site
that handles structs does that lookup explicitly and never asks
`ty-size`.

```forth file=060-cc-types.fth
\ ===========================================================================
\ Struct descriptor accessors.
\ ===========================================================================
\ A struct descriptor (allocated via cc-alloc) has the layout:
\
\   offset  0:  total-size (bytes)
\   offset  8:  field-count
\   offset 16 + i*40:  field i record (5 cells)
\     +  0:  name-addr
\     +  8:  name-len
\     + 16:  field type
\     + 24:  field offset (bytes from struct base)
\     + 32:  pointee struct descriptor (0 unless the field is a struct pointer)
\
\ The header is 16 bytes; each field record is 40 bytes.  Capped at 16 fields
\ per struct (descriptor size = 16 + 40*16 = 656 bytes).  The pointee field
\ enables chained '->' / '.' postfix on fields that are themselves struct
\ pointers (e.g. `head->next->prev` resolves both arrows).

: cc-sd-total-size      @ ;                            \ ( desc -- size )
: cc-sd-field-count     [lit] 8 + @ ;                  \ ( desc -- n )
: cc-sd-set-total-size  ! ;                            \ ( v desc -- )
: cc-sd-set-field-count [lit] 8 + ! ;                  \ ( v desc -- )

\ cc-sd-field-rec ( desc i -- rec-addr )  Address of field i's record.
: cc-sd-field-rec
  [lit] 40 * [lit] 16 + + ;

\ Field-record accessors / mutators.  Each takes rec-addr on TOS.
: cc-sf-name-addr       @ ;                            \ ( rec -- a )
: cc-sf-name-len        [lit]  8 + @ ;                 \ ( rec -- u )
: cc-sf-type            [lit] 16 + @ ;                 \ ( rec -- ty )
: cc-sf-offset          [lit] 24 + @ ;                 \ ( rec -- off )
: cc-sf-desc            [lit] 32 + @ ;                 \ ( rec -- desc )

: cc-sf-set-name-addr   ! ;                            \ ( a rec -- )
: cc-sf-set-name-len    [lit]  8 + ! ;                 \ ( u rec -- )
: cc-sf-set-type        [lit] 16 + ! ;                 \ ( ty rec -- )
: cc-sf-set-offset      [lit] 24 + ! ;                 \ ( off rec -- )
: cc-sf-set-desc        [lit] 32 + ! ;                 \ ( desc rec -- )
```

The struct descriptor is a chunk of arena memory from `cc-alloc`
(Ch 21), with the layout given in the comment: a 16-byte header, then
one 40-byte record per field.  The 16-byte header plus 16 × 40 = 640
bytes of field records gives a 656-byte cap per struct.  M2-Planet's
largest struct is well under 16 fields.

The pointee descriptor at offset 32 of each field record is the
non-obvious piece.  When the parser sees `node->next->prev`, it needs
to know *which struct* `next` points at to resolve `prev` against that
struct's fields.  Carrying the pointee descriptor in the field record
lets chained arrow access navigate without looking the type up again
by name.

## 2. The symbol-table parallel arrays

```forth file=070-cc-sym.fth
\ 070-cc-sym.fth — symbol table for the C-subset compiler.
\
\ Seven parallel arrays indexed by symbol id; extra/extra2 are described below:
\   cc-sym-name-addr [id] : pointer into cc-src-buf where the name begins
\   cc-sym-name-len  [id] : length of the name in bytes
\   cc-sym-kind      [id] : sk-* (global/local/func/struct/enum/typedef)
\   cc-sym-type      [id] : encoded type word from cc-types
\   cc-sym-val       [id] : kind-specific payload
\                            sk-global/sk-func: globals-buf offset / vaddr
\                            sk-local         : slot index (disp -8*(slot+1))
\                            sk-struct        : arena-pointer to descriptor
\                            sk-enum          : integer value
\                            sk-typedef       : encoded type word
\
\ Scope markers stored in cc-scope-stack (push records the current sym-count;
\ pop restores it, discarding all symbols added since the matching push).
\
\ Depends on 010-lib.fth (constant, variable, create, allot, [lit], if,/then,,
\   begin,/while,/repeat,, +, -, *, =, >=, 0=, !, @, +!, -!, drop, dup, swap)
\   and bytes-eq.

[lit] 4096 constant cc-sym-cap

create cc-sym-name-addr  cc-sym-cap [lit] 8 * allot
create cc-sym-name-len   cc-sym-cap [lit] 8 * allot
create cc-sym-kind       cc-sym-cap [lit] 8 * allot
create cc-sym-type       cc-sym-cap [lit] 8 * allot
create cc-sym-val        cc-sym-cap [lit] 8 * allot
\ Parallel array for "extra info".  Arrays (local or global): length in
\ elements.  Struct-typed locals/globals: descriptor.  Otherwise 0.
create cc-sym-extra      cc-sym-cap [lit] 8 * allot
\ Second extra slot.  For sk-func entries this is the head of a fixup list
\ for forward-emitted `movabs rdi, imm64` sites that load the function's
\ absolute vaddr (used when a forward-declared function appears as an
\ rvalue, e.g. `common_recursion(expression)` before expression is defined).
\ The list is walked and each 8-byte imm64 is patched to the function's real
\ vaddr when cc-parse-function processes its definition.  0 means "no
\ pending imm64 fixups".
create cc-sym-extra2     cc-sym-cap [lit] 8 * allot
variable cc-sym-count

[lit] 64 constant cc-scope-cap
create cc-scope-stack  cc-scope-cap [lit] 8 * allot
variable cc-scope-depth

\ Symbol kinds.
[lit] 0 constant sk-global
[lit] 1 constant sk-local
[lit] 2 constant sk-func
[lit] 3 constant sk-struct
[lit] 4 constant sk-enum
[lit] 5 constant sk-typedef

\ ===========================================================================
\ Helpers
\ ===========================================================================

\ sym-slot ( id arr -- addr )  Compute the address of slot id in array arr.
\ Each slot is 8 bytes; arr is the base address returned by `create`.
: sym-slot  swap [lit] 8 * + ;

```

Seven columns × 4096 rows × 8 bytes = 224 KiB, plus a 512-byte scope
stack (64 entries × 8 bytes).  That is the entire memory budget for
global declarations, function definitions, every local variable in
every function, every struct tag and every typedef.  The seven columns
are the union of the metadata any symbol kind needs.

`name-addr` and `name-len` point back into `cc-src-buf`.  There is no
deep copy, because the source buffer lives until process exit.
(Macros are not symbols; their names live in Ch 22's pool.)  `kind`
is one of six `sk-*` codes, and `type` is the type word from §1.

`val` is overloaded.  For functions it holds the absolute virtual
address where the function lives in the emitted ELF (0 while it's
only forward-declared).  For globals it holds an offset into
`cc-globals-buf`, since the data's vaddr isn't known until the code
ends (Ch 26 §5).  For locals it holds a *slot index* counted by
`cc-fn-local-count`; the `rbp` displacement `-8*(slot+1)` is computed
at emit time (Ch 25), so locals live below the saved frame pointer.
For structs it holds the descriptor pointer, for enum constants the
integer value, and for typedefs the type word the name aliases.

`extra` and `extra2` are two more overload slots.  `extra` is the
array length for array variables, the descriptor pointer for
struct-typed variables and pointers, and zero otherwise.  `extra2` is
the head of a forward-reference fixup chain for `sk-func`, which Ch 31
walks when the function's definition arrives.

## 3. Adding and finding symbols

```forth file=070-cc-sym.fth
\ ===========================================================================
\ Add / lookup
\ ===========================================================================

\ cc-sym-add ( name-addr name-len kind type val -- id )
\ Append a new symbol; return its id.
\ Stores fields by parking the new id on the return stack so each store
\ has a fresh copy to compute the slot address.
: cc-sym-add
  cc-sym-count @                                 ( a u k t v id )
  >r                                              \ R: id
  r@ cc-sym-val       sym-slot !                 \ store val
  r@ cc-sym-type      sym-slot !                 \ store type
  r@ cc-sym-kind      sym-slot !                 \ store kind
  r@ cc-sym-name-len  sym-slot !                 \ store name-len
  r@ cc-sym-name-addr sym-slot !                 \ store name-addr
  \ Extra is reused across scope pops; zero it on every add so callers don't
  \ inherit a stale value (sk-local array-len, sk-func fixup-list, etc.).
  [lit] 0 r@ cc-sym-extra  sym-slot !
  [lit] 0 r@ cc-sym-extra2 sym-slot !
  [lit] 1 cc-sym-count +!
  r> ;

```

`cc-sym-add` takes five arguments (`name-addr`, `name-len`, `kind`,
`type`, `val`), writes them into the parallel arrays at index
`cc-sym-count`, zeroes both extra slots, and bumps the count.

After `cc-sym-count @` puts the new id on top, `>r` parks it on the
return stack (Ch 4).  Each column store then uses `r@` to get a fresh
copy of the id without disturbing the data stack.  The data stack
starts as `(a u k t v)`; after `r@ cc-sym-val sym-slot !` it is
`(a u k t)`; after `r@ cc-sym-type sym-slot !` it is `(a u k)`; and
so on until all five values are stored.

Why not `dup` the id five times on the data stack?  Because the data
stack already holds five operands, and weaving the id around them
would be unreadable.  Forth code gets hard to follow once the stack
holds more than three or four unrelated values; the return stack is
the release valve.

Adding is half the job; the other half is finding a name again:

```forth file=070-cc-sym.fth
\ cc-sym-find walks all entries top-down (most recent first).  We can't bail
\ early (no `exit` primitive in the seed), so we stash the needle in two
\ globals and accumulate the result in cc-sym-find-result.  Once a match is
\ recorded the loop continues but skips further comparisons.
\
\ Result encoding: -1 (= [lit] 0 0=) means "not found"; anything >= 0 is the
\ matched id.  Most-recent-first iteration combined with "skip once found"
\ delivers innermost-scope semantics.
variable cc-sym-find-result
variable cc-sym-find-needle-addr
variable cc-sym-find-needle-len

\ cc-sym-find ( name-addr name-len -- id-or-neg1 )
: cc-sym-find
  cc-sym-find-needle-len  !
  cc-sym-find-needle-addr !
  [lit] 0 0= cc-sym-find-result !                \ -1 = "not found yet"
  cc-sym-count @ [lit] 1 -                       ( i = count-1 )
  begin,
    dup [lit] 0 >=
  while,
    cc-sym-find-result @ [lit] 0 0= = if,        \ still searching?
      dup cc-sym-name-len sym-slot @
      cc-sym-find-needle-len @ = if,             \ same length?
        dup cc-sym-name-addr sym-slot @          ( i entry-addr )
        cc-sym-find-needle-addr @ swap           ( i needle entry )
        cc-sym-find-needle-len @                 ( i needle entry u )
        bytes-eq if,
          dup cc-sym-find-result !               \ record id
        then,
      then,
    then,
    [lit] 1 -                                    \ i--
  repeat,
  drop                                            \ discard final i (=-1)
  cc-sym-find-result @ ;

```

`cc-sym-find` walks the table newest-first with the same no-`exit`
discipline as `cc-check-keyword` (Ch 23): record the hit in a
variable, keep iterating, skip the comparisons after the hit.
Innermost declarations appear later in the table, so the reverse walk
finds them first, and innermost-scope-wins falls out without any
explicit scope check.  This is Ch 17's newest-wins lookup with scope
added.

`[lit] 0 0=` produces -1, the value the result starts with, so after
the loop the caller reads either "found id N" or "not found."  Once
the caller has an id, it reads the row through one-line accessors:

```forth file=070-cc-sym.fth
\ ===========================================================================
\ Field accessors / mutators (all take id on TOS).
\ ===========================================================================

: cc-sym-kind-of       cc-sym-kind      sym-slot @ ;     \ ( id -- kind )
: cc-sym-type-of       cc-sym-type      sym-slot @ ;     \ ( id -- ty   )
: cc-sym-val-of        cc-sym-val       sym-slot @ ;     \ ( id -- val  )

\ Extra-info accessor / setter.  Array length for arrays, struct descriptor
\ for struct-typed locals/globals, otherwise 0 (see cc-sym-extra above).
: cc-sym-extra-of      cc-sym-extra     sym-slot @ ;     \ ( id -- extra )
: cc-sym-set-extra     cc-sym-extra     sym-slot ! ;     \ ( extra id -- )

\ Second extra slot — see comment near `create cc-sym-extra2` above.
: cc-sym-extra2-of     cc-sym-extra2    sym-slot @ ;     \ ( id -- extra2 )
: cc-sym-set-extra2    cc-sym-extra2    sym-slot ! ;     \ ( extra2 id -- )

```

Each accessor is a `sym-slot` fetch or store with the id on top of
the stack.

## 4. Scopes are a stack of integers

```forth file=070-cc-sym.fth
\ ===========================================================================
\ Scopes
\ ===========================================================================

\ cc-scope-push ( -- )  Mark the current sym-count as a scope boundary.
: cc-scope-push
  cc-sym-count @
  cc-scope-stack cc-scope-depth @ [lit] 8 * + !
  [lit] 1 cc-scope-depth +! ;

\ cc-scope-pop ( -- )  Discard any symbols added since the matching push;
\ pops the marker off cc-scope-stack.
: cc-scope-pop
  [lit] 1 cc-scope-depth -!
  cc-scope-stack cc-scope-depth @ [lit] 8 * + @
  cc-sym-count ! ;
```

`cc-scope-push` saves the current `cc-sym-count` onto
`cc-scope-stack`, and `cc-scope-pop` reads it back into
`cc-sym-count`.  Lexical scope is a counter manipulation: no tree, no
parent pointers, no per-scope allocation.

When the parser enters a function, it pushes a scope.  Each local
declaration calls `cc-sym-add`, which appends.  When the function
ends, the parser pops, which restores the count to its pre-function
value and so deletes the locals by making them unreachable.  The
bytes are still in the arrays, but `cc-sym-find` only walks up to
`cc-sym-count - 1`, and later additions overwrite them.

Globals are never popped because no scope is pushed at file scope.
They sit below every scope marker, so the reverse walk always reaches
them.

The 64-deep scope cap is far more than M2-Planet needs; its nested
blocks rarely exceed 4.  Nothing enforces the cap, though.
`cc-scope-push` never compares `cc-scope-depth` against
`cc-scope-cap`, and `cc-scope-pop` has no underflow guard: a 65th push
writes past the end of `cc-scope-stack`, and a pop without a matching
push reads the cell below it.  Both failures are silent.  The parser
keeps pushes and pops paired, and M2-Planet stays far below the cap,
so neither happens in practice.

## 5. How types and symbols connect

Here is the lifecycle of a single C declaration `struct point p;`
inside a function:

1. The lexer (Ch 23) produces tokens: `kw-struct`, `tk-ident`
   `"point"`, `tk-ident` `"p"`, `tk-punct` `;`.
2. The parser (Chs 29–31) reaches the declaration and looks up
   `"point"` via `cc-sym-find`, finding an `sk-struct` entry.  It
   reads `cc-sym-val-of` to get the descriptor pointer.
3. It reads `cc-sd-total-size` from the descriptor: say, 24 bytes,
   which is three 8-byte slots.
4. It reserves those three slots.  If `p` is the function's first
   local they are slots 0–2, and `p` takes the *highest*, slot 2,
   so its base address `rbp - 8*(2+1)` = `rbp - 24` is the lowest
   of the three.
5. It calls `cc-sym-add` with the name `"p"`, kind `sk-local`, type
   `ty-make ty-struct 0`, val `2`, then stores the descriptor
   pointer in `p`'s `extra`.
6. The new symbol is now findable.  A reference to `p.x` looks `p`
   up, sees `sk-local`, reads slot 2 from its val and the field
   layout from its descriptor, and codegen emits `lea rdi, [rbp - 24]`
   to get the struct's base address.

Every later chapter uses exactly this protocol.

## Try it

**Small check:** the `cc-sym-add` snippet below adds one symbol and prints
its id and the new count.

**Layer check:** the root test script covers both files from this
chapter.

```sh
./build.sh
./test.sh               # exercises types via test-060-cc-types.fth
                        # and symbols via test-070-cc-sym.fth
```

`test-060-cc-types.fth` exercises `ty-make`, `ty-base`, `ty-ptr`,
`ty-size`, and the struct-descriptor accessors round-trip.
`test-070-cc-sym.fth` exercises `cc-sym-add`, `cc-sym-find`, and
the scope push/pop dance.

For the small check, load the seven Forth files and call
`cc-sym-add` directly, all through stdin:

```sh
./build.sh
{
  cat 010-lib.fth 020-cc-arena.fth 030-cc-io.fth \
      040-cc-prep.fth 050-cc-lex.fth \
      060-cc-types.fth 070-cc-sym.fth
  cat <<'FORTH'
    here  [lit] 102 c, [lit] 111 c, [lit] 111 c,
    [lit] 3
    sk-global
    ty-int [lit] 0 ty-make
    [lit] 1024
    cc-sym-add
    [lit] 48 + emit
    cc-sym-count @ [lit] 48 + emit
    bye
FORTH
} | ./seed-forth
```

Expected output: `01` — the new symbol's id is `0`, and the count
after the add is `1`.

**tri.c at this stage:** feed lines 2–3 of `tri.c` through the
parser (Chs 29–31) and read back the rows it added.  `row` prints a symbol's id, name, kind and base type:

```sh
./build.sh
{
  cat 010-lib.fth 0[2-9]0-cc-*.fth 1[01]0-cc-*.fth
  cat <<'FORTH'
    : .d  dup [lit] 9 > if, dup [lit] 10 / .d then,
          dup [lit] 10 / [lit] 10 * - [lit] 48 + emit ;
    : .n  .d [lit] 32 emit ;
    : row  dup .n  dup [lit] 1 over cc-sym-name-addr sym-slot @
           rot cc-sym-name-len sym-slot @ write drop [lit] 32 emit
           dup cc-sym-kind-of .n  cc-sym-type-of ty-base .d [lit] 10 emit ;
    : probe
      cc-load-stdin cc-preprocess cc-out-init cc-globals-init
      cc-emit-elf-header cc-parse-program
      [lit] 23 row  [lit] 24 row
      [lit] 23 cc-sym-val-of  dup cc-sd-total-size .n
      dup cc-sd-field-count .n  dup [lit] 0 cc-sd-field-rec cc-sf-offset .n
      [lit] 1 cc-sd-field-rec cc-sf-offset .d  bye ;
    probe
FORTH
  cat <<'C'
struct tri { int rows; int stars; };
struct tri t;
C
} | ./seed-forth
```

```text
23 tri 3 0
24 t 0 4
16 2 0 8
```

Ids 0–22 are filled before any C is read (Ch 31's libc shims, a
`memset` prototype, built-in typedefs).  `tri` is row 23, kind 3
(`sk-struct`), and its val points at a descriptor in the arena: 16
bytes, 2 fields, `rows` at offset 0 and `stars` at offset 8.  `t` is
row 24, kind 0 (`sk-global`), base type 4 (`ty-struct`).  Those two
offsets become the `add rdi, 0x0` and `add rdi, 0x8` in every `t.rows`
and `t.stars` the compiler emits (Ch 28).

**Bootstrap relevance:** Stage-A reaches this layer through every
identifier lookup, local declaration, struct field, typedef, and
function symbol in the M2-Planet input.

## Exercises

1. **★★★ Extend.** Add `ty-short` (16-bit integer).  How many places change?
   What new size does `ty-size` need to return?  Hint: changing
   `060-cc-types.fth` is the easy part; finding all the places
   in Chs 25–31 that assume 8-byte cells is the hard part.

2. **★★ Verify.** Struct fields max out at 16 per struct.  Find the largest
   struct in M2-Planet's source.  Does it fit?

3. **★★ Trace.** The symbol table is a linear-scan parallel-array.  What's the
   worst-case lookup time for a 1000-symbol table?  Would a
   hash-based table fit in this codebase's size budget?

4. **★★★ Extend.** Add `ty-array` as a base kind distinct from `ty-ptr`.  Where
   would it differ in behaviour from a plain pointer?  Hint:
   array-to-pointer decay (in expression context) and
   `sizeof(arr)` (in `sizeof` context) are the two C rules.

5. **★★★ Modify.** `cc-sym-find`'s newest-first walk plus "skip after hit" is
   linear in table size, even after a hit.  Could you bail
   early?  Hint: the seed has no `exit`, and the body already
   skips its comparisons once `cc-sym-find-result` is set — but
   the loop keeps counting down to 0.  Fold the "still searching"
   test into the `while,` condition instead.  Measure whether it's
   worth the bytes.

## After this chapter

The compiler has runtime data for names and C types: every type fits
in one word (base kind plus pointer depth, with `ty-size` deriving the
size), every symbol is a row across parallel columns, and scopes push
and pop by remembering a count.  Struct definitions get their own
16+40·N-byte descriptor.  Identical name resolution gives identical
slot assignments and struct layouts, which every load and store byte
in the Stage-A comparison depends on.  `tri.c` now has rows for `tri`
and `t`, but the output buffer still holds nothing a CPU can run.  Ch
25 writes the first bytes: the ELF header and the instruction
encoders.

## Takeaways

- Every C type fits in one word, with an out-of-band arena descriptor for struct layouts, which keeps the symbol table a set of fixed-size parallel columns.
- Lexical scope is "remember the count, truncate to it on pop", with globals below every scope marker so they survive every pop.
- The struct descriptor is the only per-field metadata in the compiler; variables, functions, enum constants and typedefs are each a single symbol-table row.

Next: Chapter 25 — ELF Emission and Codegen, Part 1.
