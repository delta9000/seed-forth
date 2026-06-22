# Chapter 24 — Types and Symbols

```text
Missing capability: names and C types have no compact runtime representation.
New pattern: pack types into one word and store symbols in parallel newest-visible columns.
Artifact after this chapter: type helpers, struct descriptors, scoped symbol rows, and lookup.
Proof link: later Stage-A codegen can resolve names, scopes, sizes, and layouts consistently.
```

Two short files give the compiler its memory of "what exists".
`060-cc-types.fth` (88 lines, entire file) packs every C type into
a single 64-bit word, with five base kinds and a pointer-depth
counter sharing the bits; struct layouts live in descriptors
allocated from Ch 21's arena, reached through `cc-sd-*` accessors.
`070-cc-sym.fth` (154 lines, entire file) is the symbol table:
parallel 8-byte columns (Ch 12 `create`/`allot` buffers, names
matched by `bytes-eq`) indexed by symbol id, with
`cc-scope-push` and `cc-scope-pop` marking and restoring the count
to give lexical scopes for free.

By the end of the chapter you'll be able to encode a C type by hand,
predict where any given declaration will land in the symbol table,
walk a struct descriptor through its accessors, and read
`cc-sym-add` (note its use of `>r`/`r@`/`r>` from Ch 4 to hold the
new id while filling the parallel columns).  Where types are
*consumed* is Ch 27 (expression type-checking) and Chs 25–26
(size-based instruction selection in codegen); the `cc-sym-extra2`
field's second life as a forward-reference fixup list head is Ch 31.

---

The compiler needs to remember two kinds of facts: *what types
exist* and *what names exist*.  Both can grow during parsing, but
both have bounded sizes by the time M2-Planet's source has been
read.  This chapter handles them with the simplest possible data
structures.

The type system is exactly five base kinds: `void`, `char`,
`int`, `struct`, `func`.  No `short`, no `long`, no `float`, no
`double`, no unions, no enums-as-distinct-types.  Pointer depth
generalises to any level (`T**`, `T***`, …) so the compiler can
follow whatever indirection M2-Planet's source asks for.

The name table is seven columns of 4096 8-byte slots each —
224 KiB total.  Every global, local, function, struct tag, enum
constant, and typedef gets one row.

These choices push complexity into the *encoding*, not the
runtime representation.  By the end of the chapter you should be
able to encode a type by hand and predict where any given symbol
will land in the table.

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

Five constants, three pack/unpack words, four header accessors, ten
field-record accessors.  That is the entire C-type vocabulary the
compiler needs.

A type lives in one 64-bit word.  `ty-make` builds it: shift the
base kind left by 16 (multiplying by 65 536 — Forth has no shift
operator; multiplication does the job) and OR in the pointer depth
(0 = scalar, 1 = `T*`, 2 = `T**`, ...).  The bits 8–15 zone is
reserved for sign flags and is unused in this compiler — the only
integer type is signed 64-bit `int`.

`ty-size` is where the bits earn their keep.  Any non-zero pointer
depth means "this is a pointer; 8 bytes."  Otherwise drop down to
the base kind: `void` is 0 bytes (only legal in `void f(void)`-style
signatures), `char` is 1 byte, and everything else — `int`, `func`,
plain `struct` — is 8.

Why are struct sizes lied about?  Because `ty-size` only sees the
type *word*; it doesn't have the struct descriptor in hand.  When
the codegen actually needs `sizeof(struct foo)` it looks up the
struct's symbol, reads `val` to get the descriptor pointer, and
calls `cc-sd-total-size`.  The `[lit] 8` here is "you must not call
`ty-size` on a `ty-struct` and expect a useful answer" — every site
that handles structs does the descriptor lookup explicitly.

The struct descriptor itself is a chunk of arena memory allocated
via `cc-alloc` (Ch 21).  Layout:

```
offset  0:  total-size  (bytes)
offset  8:  field-count
offset 16 + i*40:  field i record
  +  0:  name-addr
  +  8:  name-len
  + 16:  field type (encoded as a type word)
  + 24:  field offset within struct
  + 32:  pointee struct descriptor (0 unless the field is a struct*)
```

The 16-byte header plus 16 × 40 = 640 bytes of field records gives
a 656-byte cap per struct.  M2-Planet's largest struct is well
under 16 fields, so the cap is generous.

The `pointee descriptor` field at offset 32 is the non-obvious
piece.  When the parser sees `node->next->prev`, it needs to know
*what struct* `next` points at so it can resolve `prev` against
that struct's fields.  Carrying the pointee descriptor in the
field record means chained arrow access can navigate without
re-looking-up the type by name.

## 2. The symbol-table parallel arrays

```forth file=070-cc-sym.fth
\ 070-cc-sym.fth — symbol table for the C-subset compiler.
\
\ Five parallel arrays indexed by symbol id (0..cc-sym-count-1):
\   cc-sym-name-addr [id] : pointer into cc-src-buf where the name begins
\   cc-sym-name-len  [id] : length of the name in bytes
\   cc-sym-kind      [id] : sk-* (global/local/func/struct/enum/typedef)
\   cc-sym-type      [id] : encoded type word from cc-types
\   cc-sym-val       [id] : kind-specific payload
\                            sk-global/sk-func: absolute vaddr
\                            sk-local         : rbp-relative offset (negative)
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
\ Parallel array for "extra info".  For sk-local entries that are arrays this
\ is the array length (in elements); for everything else it is 0.
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

\ ===========================================================================
\ Field accessors / mutators (all take id on TOS).
\ ===========================================================================

: cc-sym-kind-of       cc-sym-kind      sym-slot @ ;     \ ( id -- kind )
: cc-sym-type-of       cc-sym-type      sym-slot @ ;     \ ( id -- ty   )
: cc-sym-val-of        cc-sym-val       sym-slot @ ;     \ ( id -- val  )

\ Extra-info accessor / setter.  For sk-local array entries, the extra field
\ holds the array length in elements; otherwise it stays 0.
: cc-sym-extra-of      cc-sym-extra     sym-slot @ ;     \ ( id -- extra )
: cc-sym-set-extra     cc-sym-extra     sym-slot ! ;     \ ( extra id -- )

\ Second extra slot — see comment near `create cc-sym-extra2` above.
: cc-sym-extra2-of     cc-sym-extra2    sym-slot @ ;     \ ( id -- extra2 )
: cc-sym-set-extra2    cc-sym-extra2    sym-slot ! ;     \ ( extra2 id -- )

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

Seven columns × 4096 rows × 8 bytes = 224 KiB.  Plus a 512-byte
scope stack (64 entries × 8 bytes).  That's the entire memory
budget for global declarations, function definitions, every local
variable in every function, every struct tag, every typedef.

The seven columns are not arbitrary — they're the union of every
piece of metadata any symbol kind needs.

`name-addr` and `name-len` point back into `cc-src-buf` (or into
the preprocessor's name pool for macros — but macros aren't
symbols).  No deep copy: the source buffer lives until process
exit.

`kind` is one of six `sk-*` codes.  `type` is the type word from
§1.

`val` is overloaded.  For globals and functions it holds the
absolute virtual address where the symbol lives in the emitted
ELF.  For locals it holds the `rbp`-relative offset (always
negative — locals live *below* the saved frame pointer).  For
structs it holds the descriptor pointer.  For enum constants it
holds the integer value.  For typedefs it holds the type word that
the typedef name aliases.

`extra` and `extra2` are two more overload slots.  `extra` is the
array length for `sk-local` array variables and zero otherwise.
`extra2` is the head of a forward-reference fixup chain for
`sk-func`.  Ch 31 covers the fixup mechanism in detail; for now,
treat `extra2` as "future-codegen scratch space."

## 3. Adding and finding symbols

`cc-sym-add` takes five arguments — `name-addr`, `name-len`,
`kind`, `type`, `val` — and writes them into the parallel arrays
at index `cc-sym-count`, then bumps the count.

The Forth bit-twiddling here is the trick.  After
`cc-sym-count @` puts the new id on top, `>r` parks it on the
return stack.  Now each column store can use `r@` to get a *fresh
copy* of the id without disturbing the data stack:

```
r@ cc-sym-val       sym-slot !         ( pops val )
r@ cc-sym-type      sym-slot !         ( pops type )
…
```

The data stack starts with `(a u k t v)`; after the first
`r@ cc-sym-val sym-slot !` it's `(a u k t)`; after the next
`r@ cc-sym-type sym-slot !` it's `(a u k)`; and so on until all
five values are stored.

Why park the id on the return stack instead of `dup`ing it five
times on the data stack?  Because the data stack is full of
*operands* (the five values being stored) that we don't want to
weave around the id.  Forth code becomes unreadable when the stack
holds more than 3–4 unrelated values; the return stack is the
release valve.

`cc-sym-find` walks the table newest-first.  Same "no exit"
discipline as `cc-check-keyword` (Ch 23): record the hit in a
variable, keep iterating but skip work after the hit.  Newest-first
order plus skip-after-hit gives innermost-scope-wins semantics
without any explicit scope checking — innermost-declared symbols
appear later in the table, so the reverse walk finds them first.

This is Ch 17's newest-wins lookup pattern with one extra
dimension: scope.  Pushing a scope remembers a count, adding locals
appends rows, and popping the scope restores the count so the same
linear walk sees the right visible names.

The result encoding `(id) or (-1)` is conventional: `[lit] 0 0=`
produces -1, the same value the find result starts with, so a
post-loop read tells the caller "found id N" or "not found."

## 4. Scopes are a stack of integers

`cc-scope-push` saves the current `cc-sym-count` onto
`cc-scope-stack`.  `cc-scope-pop` reads it back into
`cc-sym-count`.  Together they implement lexical scope as a
counter manipulation — no tree, no parent pointers, no per-scope
allocation.

When the parser enters a function, it `cc-scope-push`es.  Each
local declaration calls `cc-sym-add`, which appends.  When the
function ends, the parser calls `cc-scope-pop`, which restores
the count to its pre-function value — *deleting* the local
symbols by making them unreachable.  The bytes are still in the
arrays, but `cc-sym-find` only walks up to `cc-sym-count - 1`, so
the next translation will overwrite them.

Globals never get popped because `cc-scope-push` is never called
at file scope.  They're below every scope marker, so the reverse
walk always reaches them.

The 64-deep scope cap is overkill — nested blocks in M2-Planet rarely
exceed 4.  But scope-depth doubles as a sanity check: if a
`cc-scope-pop` ever happens without a matching push, depth would
underflow and the next push would clobber stale memory.  The cap
makes those failures loud rather than silent.

## 5. How types and symbols connect

Putting the two files together, here's the full lifecycle of a
single C declaration `struct point p;` inside a function:

1. The lexer (Ch 23) produces tokens: `kw-struct`, `tk-ident`
   `"point"`, `tk-ident` `"p"`, `tk-punct` `;`.
2. The parser (Chs 29–31) reaches the declaration and looks up
   `"point"` via `cc-sym-find` — finds an `sk-struct` entry.
   Reads `cc-sym-val-of` to get the descriptor pointer.
3. Reads `cc-sd-total-size` from the descriptor — say, 24 bytes.
4. Allocates 24 bytes of locals at offset `-24` from `rbp`.
5. Calls `cc-sym-add` with the name `"p"`, kind `sk-local`, type
   `ty-make ty-struct 0`, val `-24`.
6. The new symbol becomes findable; references to `p.x` will look
   `p` up, see `sk-local`, read its val for the `rbp`-offset, and
   the codegen will emit `lea rax, [rbp + (-24)]` to get the
   struct's base address.

That's the only protocol every later chapter needs to know.

## Try it

**Small check:** the `probe` snippet below adds one symbol and prints
the new symbol id plus the resulting count.

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

To run the small check, load the seven Forth files, add one symbol,
and print its id and the resulting count.  We define a one-shot word
`probe` and call it; seed-forth has no `-e` flag, so everything goes
through stdin:

```sh
./build.sh
{
  for f in 010-lib.fth 020-cc-arena.fth 030-cc-io.fth \
           040-cc-prep.fth 050-cc-lex.fth \
           060-cc-types.fth 070-cc-sym.fth; do
    sed -e 's/\\.*$//' -e 's/([^)]*)//g' "$f"
  done
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
} | grep -v '^[[:space:]]*$' | ./seed-forth
```

Expected output: `01` — the new symbol's id is `0`, and the count
after the add is `1`.

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
   early?  Hint: the seed has no `exit`, but a Forth-level
   wrapper could check a flag at every iteration and skip the
   body.  Measure whether it's worth the bytes.

## After this chapter

The compiler has runtime data for names and C types: every type
fits in one word (base kind + pointer depth + size), every symbol
lives in a row across parallel columns, and scopes push/pop by
remembering a count.  Struct definitions get their own 16+40·N-byte
descriptor.

You can read `ty-make`, `cc-sym-add`, and the scope stack, and
explain why a single linear scan in newest-first order is enough
for both correctness and performance at this scale.

Toward Stage-A: identical name resolution produces identical slot
assignments and identical struct layouts, which is the precondition
for every load/store byte that follows being identical to the
reference's.

## Takeaways

- The whole C type system fits in one word per type, plus an
  out-of-band descriptor for structs.  This is what makes the
  symbol table cheap (parallel arrays of fixed-size cells).
- Lexical scope is "remember the count; truncate to it on pop."
  No tree, no nesting record — just a stack of integers, with
  globals below every scope marker so they survive every pop.
- The struct descriptor is the only place the compiler tracks
  per-field metadata.  Everything else (variables, functions,
  enum constants, typedefs) is a row in the parallel-array
  symbol table.

Next: Chapter 25 — ELF Emission and Codegen, Part 1.
