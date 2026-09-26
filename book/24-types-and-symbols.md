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

The 97-line file `060-cc-types.fth` packs every C type into one
64-bit word.  There are exactly five base kinds: `void`, `char`,
`int`, `struct`, `func`.  No `short`, no `long`, no `float`, no
`double`, no unions, no enums-as-distinct-types.  Pointer depth
generalises to any level (`T**`, `T***`, …).  Struct layouts live in
descriptors allocated from Ch 21's arena.

The 131-line file `070-cc-sym.fth` is the symbol table: seven columns
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
\   bits[ 8..15] = always 0
\   bits[16..31] = base kind (one of ty-* below)
\
\ Struct and function types use base = ty-struct / ty-func.  The type word
\ does not say which struct: the descriptor pointer lives in the symbol
\ table — the tag's sk-struct entry keeps it in val, and a struct-typed
\ variable keeps it in its struct-desc cell (070-cc-sym.fth) — and in a
\ field record's pointee slot (below).  The caller resolves it before any
\ size-of/field-offset query.
\
\ Depends on 010-lib.fth: constant, [lit], if,/then,/else,, +, -, *, /, =, dup,
\   swap, drop, and, >, 1+; 020-cc-arena.fth: cc-check-cap.

[lit] 0 constant ty-void
[lit] 1 constant ty-char
[lit] 2 constant ty-int                       \ signed 64-bit
[lit] 3 constant ty-struct
[lit] 4 constant ty-func

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
Bits 8–15 are always 0: the depth field is simply given a byte of its
own, and nothing else is packed there, since the only integer type is
signed 64-bit `int`.  The base kinds are numbered 0 to 4 with no gaps.

A struct's type word says only "a struct", never which one.  Which
struct lives beside the type: in the tag's symbol (its `val`), in a
struct variable's struct-desc cell (§2), and in a field record's
pointee slot (below).

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
\ per struct (descriptor size cc-sd-bytes = 16 + 40*16 = 656 bytes).  The
\ pointee field enables chained '->' / '.' postfix on fields that are
\ themselves struct pointers (e.g. `head->next->prev` resolves both arrows).

[lit] 16 constant cc-sd-max-fields
cc-sd-max-fields [lit] 40 * [lit] 16 + constant cc-sd-bytes      \ 656

: cc-sd-total-size      @ ;                            \ ( desc -- size )
: cc-sd-field-count     [lit] 8 + @ ;                  \ ( desc -- n )
: cc-sd-set-total-size  ! ;                            \ ( v desc -- )
: cc-sd-set-field-count [lit] 8 + ! ;                  \ ( v desc -- )

\ cc-sd-field-rec ( desc i -- rec-addr )  Address of field i's record.
\ Dies with code 50 for i past the last record: a struct with more than
\ cc-sd-max-fields fields.
: cc-sd-field-rec
  dup 1+ cc-sd-max-fields [lit] 50 cc-check-cap
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
bytes of field records gives `cc-sd-bytes`, 656 bytes per struct.
M2-Planet's largest struct is well under 16 fields, and a 17th field
would land past the descriptor, so `cc-sd-field-rec`, the one word
that turns a field index into an address, dies with code 50 first
(`tests/cc/die-50-struct-fields.c`).

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
\ Seven parallel arrays indexed by symbol id (cell[], 030-cc-io.fth):
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
\   cc-sym-extra     [id] : one more fact, whose meaning depends on the symbol
\   cc-sym-extra2    [id] : and, for sk-func only, a second one
\ Nothing outside this file names the two extra arrays: each meaning has its
\ own accessor (see "Field accessors" below).
\
\ Scope markers stored in cc-scope-stack (push records the current sym-count;
\ pop restores it, discarding all symbols added since the matching push).
\
\ Depends on 010-lib.fth (constant, variable, create, allot, [lit], if,/then,,
\   0=, 1+, !, @, +!, -!, drop, swap, >r, r@, r>), 020-cc-arena.fth (cc-die,
\   cc-check-cap) and 030-cc-io.fth (cell[], cc-name-find).

[lit] 4096 constant cc-sym-cap

create cc-sym-name-addr  cc-sym-cap [lit] 8 * allot
create cc-sym-name-len   cc-sym-cap [lit] 8 * allot
create cc-sym-kind       cc-sym-cap [lit] 8 * allot
create cc-sym-type       cc-sym-cap [lit] 8 * allot
create cc-sym-val        cc-sym-cap [lit] 8 * allot
create cc-sym-extra      cc-sym-cap [lit] 8 * allot
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

`extra` and `extra2` are two more cells.  Their meaning depends on the
symbol, so no code outside this file reads them by those names; §3's
accessors name each meaning instead.

## 3. Adding and finding symbols

```forth file=070-cc-sym.fth
\ Add / lookup
\ ===========================================================================

\ cc-sym-add ( name-addr name-len kind type val -- id )
\ Append a new symbol; return its id.  Dies with code 60 if the table
\ already holds cc-sym-cap symbols.
\ Stores fields by parking the new id on the return stack so each store
\ has a fresh copy to compute the slot address.
: cc-sym-add
  cc-sym-count @ 1+ cc-sym-cap [lit] 60 cc-check-cap
  cc-sym-count @                                 ( a u k t v id )
  >r                                              \ R: id
  r@ cc-sym-val       cell[] !                   \ store val
  r@ cc-sym-type      cell[] !                   \ store type
  r@ cc-sym-kind      cell[] !                   \ store kind
  r@ cc-sym-name-len  cell[] !                   \ store name-len
  r@ cc-sym-name-addr cell[] !                   \ store name-addr
  \ Extra is reused across scope pops; zero it on every add so callers don't
  \ inherit a stale value (sk-local array-len, sk-func fixup-list, etc.).
  [lit] 0 r@ cc-sym-extra  cell[] !
  [lit] 0 r@ cc-sym-extra2 cell[] !
  [lit] 1 cc-sym-count +!
  r> ;

```

`cc-sym-add` takes five arguments (`name-addr`, `name-len`, `kind`,
`type`, `val`), writes them into the parallel arrays at index
`cc-sym-count`, zeroes both extra slots, and bumps the count.

After `cc-sym-count @` puts the new id on top, `>r` parks it on the
return stack (Ch 4).  Each column store then uses `r@` to get a fresh
copy of the id without disturbing the data stack.  The data stack
starts as `(a u k t v)`; after `r@ cc-sym-val cell[] !` it is
`(a u k t)`; after `r@ cc-sym-type cell[] !` it is `(a u k)`; and
so on until all five values are stored.  `cell[]` (Ch 21) turns the
id into the address of its cell in one column.  A 4,097th symbol dies
with code 60 before anything is written.

Why not `dup` the id five times on the data stack?  Because the data
stack already holds five operands, and weaving the id around them
would be unreadable.  Forth code gets hard to follow once the stack
holds more than three or four unrelated values; the return stack is
the release valve.

Adding is half the job; the other half is finding a name again:

```forth file=070-cc-sym.fth
\ cc-sym-find ( name-addr name-len -- id-or-neg1 )
\ cc-name-find walks the entries newest first and returns at the first
\ match, which gives innermost-scope semantics: -1 means "not found",
\ anything >= 0 is the matched id.
: cc-sym-find
  cc-sym-name-addr cc-sym-name-len cc-sym-count @ cc-name-find ;

```

`cc-sym-find` is Ch 21's `cc-name-find` over the two name columns,
the same lookup the macro table uses.  It walks the table
newest-first and returns with `exit,` on the first hit.  Innermost
declarations appear later in the table, so the reverse walk finds
them first, and innermost-scope-wins falls out without any explicit
scope check.  This is Ch 17's newest-wins lookup with scope added.

The loop index runs down to `-1` when nothing matches, and that `-1`
is the "not found" answer, so the caller reads either "found id N"
or "not found" with no flag variable.  Once the caller has an id,
it reads the row through one-line accessors:

```forth file=070-cc-sym.fth
\ ===========================================================================
\ Field accessors / mutators (all take id on TOS).
\ ===========================================================================

: cc-sym-kind-of       cc-sym-kind      cell[] @ ;       \ ( id -- kind )
: cc-sym-type-of       cc-sym-type      cell[] @ ;       \ ( id -- ty   )
: cc-sym-val-of        cc-sym-val       cell[] @ ;       \ ( id -- val  )

\ The extra cell means one of three things, depending on the symbol; each
\ meaning has its own accessors, all over the same cc-sym-extra array.
\   array length: an array local or global's element count; 0 for a scalar.
: cc-sym-array-len-of     cc-sym-extra     cell[] @ ;  \ ( id -- n    )
: cc-sym-set-array-len    cc-sym-extra     cell[] ! ;  \ ( n id --    )
\   struct descriptor: a struct or struct-pointer local or global's
\   descriptor (060-cc-types.fth).  Its type's base is ty-struct, which is
\   how readers tell this meaning from an array length (so the subset has
\   no arrays of structs).
: cc-sym-struct-desc-of   cc-sym-extra     cell[] @ ;  \ ( id -- desc )
: cc-sym-set-struct-desc  cc-sym-extra     cell[] ! ;  \ ( desc id -- )
\   call fixups: for an sk-func not yet defined, the head of the list of
\   `call rel32` sites waiting for its address.  This word gives the cell's
\   address, so the list code can push onto it (0 = no pending calls).
: cc-sym-call-fixups      cc-sym-extra     cell[] ;    \ ( id -- cell )
\ The extra2 cell has one meaning, for sk-func only.
\   address fixups: the head of the list of `movabs rdi, imm64` sites that
\   load the function's address before it is defined (a forward-declared
\   function used as a value, e.g. `common_recursion(expression)` before
\   expression's body).  cc-parse-function patches each imm64 to the real
\   vaddr when it reaches the definition.  0 = no pending loads.
: cc-sym-addr-fixups      cc-sym-extra2    cell[] ;    \ ( id -- cell )

```

Each accessor is a `cell[]` fetch or store with the id on top of the
stack.  The extra cell carries one of three facts, and each fact gets
its own name even though they share the array:

- **array length** (`cc-sym-array-len-of`): an array variable's
  element count, 0 for a scalar, so Ch 28 can tell `int a[4]` (take
  the address) from `int *p` (load the value);
- **struct descriptor** (`cc-sym-struct-desc-of`): for a variable
  whose type's base is `ty-struct`, the descriptor that lays it out;
  the type is how a reader knows which of the first two it is;
- **call fixups** (`cc-sym-call-fixups`): for a function called
  before its definition, the head of the list of `call` sites waiting
  for its address.

The extra2 cell has one fact, **address fixups**
(`cc-sym-addr-fixups`): the list of places that load a function's
address before it is defined.  The two fixup words return the cell's
address rather than its contents, because Ch 26's list code pushes
onto the list in place, and Ch 31 walks both lists when the definition
arrives.

## 4. Scopes are a stack of integers

```forth file=070-cc-sym.fth
\ ===========================================================================
\ Scopes
\ ===========================================================================

\ cc-scope-push ( -- )  Mark the current sym-count as a scope boundary.
\ Dies with code 61 past cc-scope-cap nested scopes.
: cc-scope-push
  cc-scope-depth @ 1+ cc-scope-cap [lit] 61 cc-check-cap
  cc-sym-count @
  cc-scope-depth @ cc-scope-stack cell[] !
  [lit] 1 cc-scope-depth +! ;

\ cc-scope-pop ( -- )  Discard any symbols added since the matching push;
\ pops the marker off cc-scope-stack.  A pop with no push to match is a
\ parser bug: die with code 62.
: cc-scope-pop
  cc-scope-depth @ 0= if, [lit] 62 cc-die then,
  [lit] 1 cc-scope-depth -!
  cc-scope-depth @ cc-scope-stack cell[] @
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
blocks rarely exceed 4.  Both ends are guarded: a 65th push dies with
code 61 (`tests/cc/die-61-scopes-deep.c` nests 70 blocks), and a pop
with no push to match dies with 62.  The parser keeps pushes and pops
paired, so 62 would mean a bug in the parser, not in the C.

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
   pointer with `cc-sym-set-struct-desc`.
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
parser (Chs 29–31) and read back the rows it added.  The probe runs
`cc-parse-program`'s steps up to the top-level loop and stops there:
the whole-program check that follows would reject a fragment with no
`main`.  `row` prints a symbol's id, name, kind and base type:

```sh
./build.sh
{
  cat 010-lib.fth 0[2-9]0-cc-*.fth 1[01]0-cc-*.fth
  cat <<'FORTH'
    : .d  dup [lit] 9 > if, dup [lit] 10 / .d then,
          dup [lit] 10 / [lit] 10 * - [lit] 48 + emit ;
    : .n  .d [lit] 32 emit ;
    : row  dup .n  dup [lit] 1 over cc-sym-name-addr cell[] @
           rot cc-sym-name-len cell[] @ write drop [lit] 32 emit
           dup cc-sym-kind-of .n  cc-sym-type-of ty-base .d [lit] 10 emit ;
    : probe
      cc-load-stdin cc-preprocess cc-out-init cc-globals-init
      cc-emit-elf-header
      cc-emit-entry-stub cc-emit-shims cc-emit-external-protos
      cc-emit-libc-typedefs cc-parse-function-list
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
24 t 0 3
16 2 0 8
```

Ids 0–22 are filled before any C is read (Ch 31's libc shims, a
`memset` prototype, built-in typedefs).  `tri` is row 23, kind 3
(`sk-struct`), and its val points at a descriptor in the arena: 16
bytes, 2 fields, `rows` at offset 0 and `stars` at offset 8.  `t` is
row 24, kind 0 (`sk-global`), base type 3 (`ty-struct`).  Those two
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

5. **★★★ Modify.** `cc-sym-find` is linear in table size: a name
   declared early in a large translation unit is found only after
   every newer entry has been length-checked.  Add a hash (say, of
   the first byte and the length) to a bucket-head array and chain
   entries through a new column.  Keep newest-first order within a
   bucket so shadowing still works, and measure on the M2-Planet
   build whether it is worth the bytes.

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
