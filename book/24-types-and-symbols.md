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

The file `060-cc-types.fth` packs every C type into one 64-bit word.
The original base kinds, `void`, `char`, `int`, `struct`, and `func`,
keep their numbers.  Extra signed and unsigned integer kinds and
floating storage kinds support the opt-in LP64 target.  Among them,
`ty-llong` and `ty-ullong` give `long long` its own identity: the
same eight-byte size and signedness as `long`, but a distinct kind, so
type comparisons still tell `long *` from `long long *`.  Pointer depth
generalises to any level (`T**`, `T***`, …).  Struct and union layouts
live in descriptors allocated from Ch 21's arena.

The 165-line file `070-cc-sym.fth` is the symbol table: ten columns
of 8192 8-byte slots each, 640 KiB in all.  Every global, local,
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
\ Depends on 010-lib.fth: constant, variable, [lit], if,/then,/else,, exit,,
\   begin,/while,/repeat,, +, -, *, /, =, dup, swap, drop, and, or, >, 1+,
\   @, !, c!, over; 020-cc-arena.fth: cc-check-cap, cc-alloc.

[lit] 0 constant ty-void
[lit] 1 constant ty-char
[lit] 2 constant ty-int                       \ legacy 64-bit; LP64 32-bit
[lit] 3 constant ty-struct
[lit] 4 constant ty-func
[lit] 5 constant ty-short
[lit] 6 constant ty-long
[lit] 7 constant ty-float
[lit] 8 constant ty-double
[lit] 9 constant ty-uchar
[lit] 10 constant ty-ushort
[lit] 11 constant ty-uint
[lit] 12 constant ty-ulong
[lit] 13 constant ty-ldouble
[lit] 14 constant ty-array
\ LP64 long long kinds share long's representation but not its identity:
\ only the LP64 data model spells them, and they rank above long.
[lit] 15 constant ty-llong
[lit] 16 constant ty-ullong

\ Array nodes carry element type/descriptor, dimensions, size and alignment.
\ The last cell is true when the elements are qualified: a pointer to the
\ node then points to qualified elements, as a pointer to const T would.
: cc-ad-type @ ;
: cc-ad-desc [lit] 8 + @ ;
: cc-ad-count [lit] 16 + @ ;
: cc-ad-inner [lit] 24 + @ ;
: cc-ad-size [lit] 32 + @ ;
: cc-ad-align [lit] 40 + @ ;
: cc-ad-qualified [lit] 48 + @ ;

\ The pinned M2/pnut route keeps the original data model unless opted in.
variable cc-target-lp64
[lit] 0 cc-target-lp64 !

\ Restricted first-stage bootstrap approximation, never the default ABI.
\ Portable bootstrap float values travel as integer bits in 8-byte cells.
\ This flag does not implement IEEE floating arithmetic or conversions.
variable cc-bootstrap-floatbits
[lit] 0 cc-bootstrap-floatbits !

\ ty-make ( base ptrdepth -- ty )  Pack base and ptr-depth into one word.
: ty-make
  swap [lit] 65536 *  swap +  ;               \ (base << 16) | ptr-depth

\ ty-base ( ty -- base )  Extract the base kind (bits 16..31).
: ty-base
  [lit] 65536 /  [lit] 65535 and ;            \ shift right 16, mask low 16

\ ty-ptr ( ty -- depth )  Extract pointer depth (bits 0..7).
: ty-ptr
  [lit] 255 and ;

\ ty-size ( ty -- bytes )  Scalar/pointer storage size, not aggregate size.
\ The caller resolves struct descriptors before asking their size/alignment.
\ LP64 is the AMD64 System V model: int=4, long/pointer=8, long double=16.
\ Both long long kinds take the final eight-byte answer, exactly as long.
\ The default retains the original char=1 and other non-void scalars=8.
: ty-size
  dup ty-ptr [lit] 0 > if, drop [lit] 8 exit, then,
  ty-base
  dup ty-void = if, drop [lit] 0 exit, then,
  dup ty-char = if, drop [lit] 1 exit, then,
  cc-target-lp64 @ if,
    cc-bootstrap-floatbits @ if,
      dup ty-float = over ty-double = or over ty-ldouble = or if,
        drop [lit] 8 exit,
      then,
    then,
    dup ty-uchar = if, drop [lit] 1 exit, then,
    dup ty-short = over ty-ushort = or if, drop [lit] 2 exit, then,
    dup ty-int = over ty-uint = or over ty-float = or if,
      drop [lit] 4 exit,
    then,
    dup ty-ldouble = if, drop [lit] 16 exit, then,
  then,
  drop [lit] 8 ;

\ ty-unsigned? ( ty -- flag )  Pointers compare as unsigned addresses.
\ Plain char is signed in LP64; legacy byte expressions are zero-extended.
: ty-unsigned?
  dup ty-ptr [lit] 0 > if, drop true exit, then,
  ty-base
  dup ty-uchar = over ty-ushort = or
  over ty-uint = or over ty-ulong = or over ty-ullong = or
  swap ty-char = cc-target-lp64 @ 0= and or ;

\ ty-long-long? ( ty -- flag )  Scalar long long, signed or unsigned.
: ty-long-long?
  dup ty-ptr if, drop [lit] 0 exit, then,
  ty-base dup ty-llong = swap ty-ullong = or ;

\ ty-align ( ty -- bytes )  Scalar/pointer alignment; void uses 1.
\ Struct/union alignment is cc-sd-align, not the type word's fallback.
: ty-align  ty-size dup 0= if, drop [lit] 1 then, ;

\ cc-integer-suffix ( addr len -- flag )  The one integer-suffix parser,
\ shared by literal typing below and the constant evaluator (125).  The
\ text addr len starts at the suffix's first letter; flag is true only if
\ all of it is one C suffix: an optional U on either side of an optional
\ l, L, ll or LL (C90 6.1.3.2 plus long long).  So 1LLL, 1lL, 1LUL and
\ 1uu are false.  cc-literal-unsigned and cc-literal-long (0, 1 or 2)
\ record what was read.
variable cc-literal-unsigned
variable cc-literal-long
: cc-integer-suffix-u ( addr len -- addr' len' )
  dup 0= if, exit, then,
  cc-literal-unsigned @ if, exit, then,
  over c@ dup [char] u = swap [char] U = or if,
    true cc-literal-unsigned ! swap 1+ swap 1-
  then, ;
: cc-integer-suffix-l ( addr len -- addr' len' )
  dup 0= if, exit, then,
  over c@ dup [char] l = swap [char] L = or 0= if, exit, then,
  [lit] 1 cc-literal-long !
  over c@ >r swap 1+ swap 1-                      ( addr' len' ; R: letter )
  dup if,
    over c@ r@ = if, [lit] 2 cc-literal-long ! swap 1+ swap 1- then,
  then,
  r> drop ;
: cc-integer-suffix ( addr len -- flag )
  [lit] 0 cc-literal-unsigned ! [lit] 0 cc-literal-long !
  cc-integer-suffix-u cc-integer-suffix-l cc-integer-suffix-u
  nip 0= ;

\ cc-integer-suffix-letter? ( c -- flag )  u, U, l or L.
: cc-integer-suffix-letter?
  dup [char] u = over [char] U = or
  over [char] l = or swap [char] L = or ;

\ cc-integer-suffix-start ( addr len -- addr' len' )  Step over the
\ digits to the first suffix letter, or to the end.
: cc-integer-suffix-start
  begin, dup while,
    over c@ cc-integer-suffix-letter? if, exit, then,
    swap 1+ swap 1-
  repeat, ;

\ cc-integer-literal-check ( -- )  Parse the current tk-num token's
\ suffix, the letters the lexer (050) kept after the digits; no hex digit
\ is one of them.  A malformed suffix is 240, the constant evaluator's
\ code for an unsupported constant form, in every expression context.
: cc-integer-literal-check
  tok-str-addr @ tok-str-len @ cc-integer-suffix-start
  cc-integer-suffix 0= if, [lit] 240 cc-die then, ;

\ cc-integer-literal-type ( -- ty )  Type of the current tk-num token.
\ The original spelling (050) distinguishes decimal from hex/octal and
\ preserves U/L/LL suffixes without expanding the lexer's snapshot state.
\ LP64 long and long long share one 64-bit representation, so only a
\ two-letter LL suffix selects long long; its value picks the signedness.
\ As a bootstrap extension, a decimal value beyond signed long uses ulong.
\ Range tests use unsigned division, so bit-63-set constants stay correct.
: cc-integer-literal-type
  cc-target-lp64 @ 0= if, ty-int [lit] 0 ty-make exit, then,
  cc-integer-literal-check
  cc-literal-long @ [lit] 1 > if,
    cc-literal-unsigned @ tok-num @ 2^63 / or if,
      ty-ullong
    else, ty-llong then,
    [lit] 0 ty-make exit,
  then,
  cc-literal-long @ if,
    cc-literal-unsigned @ tok-num @ 2^63 / or if,
      ty-ulong
    else, ty-long then,
  else,
    cc-literal-unsigned @ if,
      tok-num @ [lit] 4294967296 / if, ty-ulong else, ty-uint then,
    else,
      tok-num @ [lit] 2147483648 / 0= if,
        ty-int
      else,
        tok-str-addr @ c@ [char] 0 =
        tok-num @ [lit] 4294967296 / 0= and if,
          ty-uint
        else,
          tok-num @ 2^63 / if, ty-ulong else, ty-long then,
        then,
      then,
    then,
  then,
  [lit] 0 ty-make ;

```

A type lives in one 64-bit word.  `ty-make` builds it: shift the base
kind left by 16 (Forth has no shift operator, so multiply by 65 536)
and add the pointer depth (0 = scalar, 1 = `T*`, 2 = `T**`, ...).
Bits 8–15 are always 0: the depth field is simply given a byte of its
own, and nothing else is packed there.  The original base kinds stay
numbered 0 to 4; LP64 additions occupy 5 to 13.  `cc-target-lp64`
defaults to zero, preserving the original 64-bit `int` data model.

A struct's type word says only "a struct", never which one.  Which
struct lives beside the type: in the tag's symbol (its `val`), in a
struct variable's struct-desc cell (§2), and in a field record's
pointee slot (below).

`ty-size` shows why the depth sits in the low bits.  Any non-zero
pointer depth means "pointer, 8 bytes."  Otherwise it falls back to
the base kind: `void` is 0 bytes (only legal in `void f(void)`-style
signatures), `char` is 1 byte, and everything else (`int`, `func`,
plain `struct`) is 8 in the legacy target.  With `cc-target-lp64`
set, `short` is 2 bytes, `int` and `float` are 4, `long`, `double`,
and pointers are 8, and `long double` occupies 16.  Unsigned kinds
share the corresponding width.  `ty-unsigned?` classifies integer
conversion and comparison semantics; `ty-align` supplies scalar
alignment.  Floating storage sizes alone do not implement floating
arithmetic.  A separate, default-off `cc-bootstrap-floatbits` flag
lets the restricted first bootstrap stage transport all three floating
kinds in 8-byte integer cells.  That approximation is not IEEE
arithmetic and does not change standard LP64 mode.

An LP64 integer literal's type comes from its spelling.
`cc-integer-suffix` is the only reader of its `U`/`L` suffix: an
optional `U` on either side of `l`, `L`, `ll` or `LL`.  Literal typing,
Ch 41's constant evaluator and `#if` (Ch 28's `cc-cx-operand`) all call
it, so `1LLL`, `1lL`, `1LUL` and `1uu` are error 240 wherever they
appear rather than being typed by a count of letters.

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
\ A struct/union descriptor (allocated via cc-sd-alloc) is a fixed header
\ whose address never changes, plus a separately allocated field table:
\
\   offset  0: total-size (bytes)
\   offset  8: field-count
\   offset 16: aggregate alignment (LP64)
\   offset 24: is-union flag (LP64)
\   offset 32: target cell (SysV: bitfield cursor, 129-cc-bitfield.fth)
\   offset 40: field-table address (0 until the first field)
\   offset 48: field-table capacity, in records
\
\ Field i's record is at table + i*record-bytes.  LP64 records are 6 cells:
\     +  0: name-addr
\     +  8: name-len
\     + 16: field type (array element type when array-len is nonzero)
\     + 24: field offset (bytes from aggregate base)
\     + 32: aggregate/pointee descriptor, or 0
\     + 40: array length (0 for a scalar)
\
\ Legacy records keep only the first five cells (40 bytes) and legacy
\ code reads only the first two header cells.  The table starts with room
\ for 8 records and doubles when an append needs more, so small structs
\ stay small and a large one costs at most twice its exact size.  The cap
\ is policy, not storage: LP64 allows 1023 members, C99's translation
\ limit for one struct or union (5.2.4.1).  That is over four times the
\ largest in GCC 4.0.4 (JNINativeInterface, 232 members) and seven times
\ bfd's (elf_backend_data, 143).  The legacy M2-Planet subset
\ keeps its documented 16-field limit and small arena.

[lit] 16 constant cc-sd-max-fields
[lit] 1023 constant cc-sd-lp64-max-fields
[lit] 56 constant cc-sd-header-bytes
[lit] 8 constant cc-sd-initial-fields

: cc-sd-field-cap
  cc-target-lp64 @ if, cc-sd-lp64-max-fields else, cc-sd-max-fields then, ;

: cc-sd-record-bytes-default
  cc-target-lp64 @ if, [lit] 48 else, [lit] 40 then, ;
defer cc-sd-record-bytes
' cc-sd-record-bytes-default is cc-sd-record-bytes

\ cc-zalloc ( bytes -- addr )  Arena storage cleared to zero, so cells a
\ target adds read as 0 even where the arena reuses mapped memory.
: cc-zalloc
  dup cc-alloc                                   ( bytes addr )
  dup >r swap over +                             ( start end ; R: addr )
  begin, over over < while,
    swap [lit] 0 over c! 1+ swap
  repeat,
  drop drop r> ;

\ cc-sd-alloc ( -- desc )  A zeroed header with no field table yet.
: cc-sd-alloc  cc-sd-header-bytes cc-zalloc ;

: cc-sd-total-size      @ ;                            \ ( desc -- size )
: cc-sd-field-count     [lit] 8 + @ ;                  \ ( desc -- n )
: cc-sd-align           [lit] 16 + @ ;                 \ ( desc -- align )
: cc-sd-union?          [lit] 24 + @ ;                 \ ( desc -- flag )
: cc-sd-set-total-size  ! ;                            \ ( v desc -- )
: cc-sd-set-field-count [lit] 8 + ! ;                  \ ( v desc -- )
: cc-sd-set-align       [lit] 16 + ! ;                 \ ( v desc -- )
: cc-sd-set-union       [lit] 24 + ! ;                 \ ( v desc -- )
: cc-sd-table           [lit] 40 + @ ;                 \ ( desc -- addr )
: cc-sd-table-cap       [lit] 48 + @ ;                 \ ( desc -- n )

\ cc-sd-grow ( desc need -- )  Replace the table with a zeroed one holding
\ at least need records (double, at least 8, at most the field cap) and
\ copy the old records across.  The old table stays behind in the arena,
\ so a record address taken before an append to the same descriptor is
\ stale afterwards; callers fetch each record after any such append.
\ cc-sd-table-moved ( old new bytes -- ) lets side tables keyed by record
\ address follow the records (115-cc-native.fth: field qualification).
: cc-sd-table-moved-default  drop 2drop ;
defer cc-sd-table-moved
' cc-sd-table-moved-default is cc-sd-table-moved
variable cc-sd-grow-desc
: cc-sd-grow
  swap cc-sd-grow-desc !                         ( need )
  cc-sd-grow-desc @ cc-sd-table-cap [lit] 2 *    ( need cap )
  dup cc-sd-initial-fields < if, drop cc-sd-initial-fields then,
  begin, over over > while, [lit] 2 * repeat,
  nip dup cc-sd-field-cap > if, drop cc-sd-field-cap then,
  dup cc-sd-record-bytes * cc-zalloc             ( cap new )
  cc-sd-grow-desc @ cc-sd-table over             ( cap new old new )
  cc-sd-grow-desc @ cc-sd-table-cap cc-sd-record-bytes *
  begin, dup while,                              ( cap new src dst n )
    >r over c@ over c! 1+ swap 1+ swap r> 1-
  repeat, drop 2drop                             ( cap new )
  cc-sd-grow-desc @ cc-sd-table over
  cc-sd-grow-desc @ cc-sd-table-cap cc-sd-record-bytes * cc-sd-table-moved
  cc-sd-grow-desc @ [lit] 40 + !
  cc-sd-grow-desc @ [lit] 48 + ! ;

\ cc-sd-field-rec ( desc i -- rec-addr )  Error 50 if record i would exceed
\ the target's member cap; grow the table when i is past its capacity.
: cc-sd-field-rec
  dup 1+ cc-sd-field-cap [lit] 50 cc-check-cap
  over cc-sd-table-cap over > 0= if, over over 1+ cc-sd-grow then,
  cc-sd-record-bytes * swap cc-sd-table + ;

\ Field-record accessors / mutators.  Each takes rec-addr on TOS.
\ Alignment, union and array-length accessors are for LP64 descriptors only.
: cc-sf-name-addr       @ ;                            \ ( rec -- a )
: cc-sf-name-len        [lit]  8 + @ ;                 \ ( rec -- u )
: cc-sf-type            [lit] 16 + @ ;                 \ ( rec -- ty )
: cc-sf-offset          [lit] 24 + @ ;                 \ ( rec -- off )
: cc-sf-desc            [lit] 32 + @ ;                 \ ( rec -- desc )
: cc-sf-array-len       [lit] 40 + @ ;                 \ ( rec -- n )

: cc-sf-set-name-addr   ! ;                            \ ( a rec -- )
: cc-sf-set-name-len    [lit]  8 + ! ;                 \ ( u rec -- )
: cc-sf-set-type        [lit] 16 + ! ;                 \ ( ty rec -- )
: cc-sf-set-offset      [lit] 24 + ! ;                 \ ( off rec -- )
: cc-sf-set-desc        [lit] 32 + ! ;                 \ ( desc rec -- )
: cc-sf-set-array-len   [lit] 40 + ! ;                 \ ( n rec -- )

\ Targets may extend field shape without changing legacy/native records.
: cc-sf-array-inner-default ( rec -- n ) drop [lit] 0 ;
: cc-sf-set-array-inner-default ( n rec -- )
  drop if, [lit] 213 cc-die then, ;
defer cc-sf-array-inner
defer cc-sf-set-array-inner
' cc-sf-array-inner-default is cc-sf-array-inner
' cc-sf-set-array-inner-default is cc-sf-set-array-inner
```

The struct descriptor is two pieces of arena memory from `cc-alloc`
(Ch 21).  The 56-byte header never moves, so symbols and field
records can hold its address while the body is still being parsed
(`struct node *next;` inside `struct node`).  The field records live in
a separate table that the header points at.  `cc-sd-alloc` returns a
zeroed header with no table; the first `cc-sd-field-rec` for index 0
makes room for 8 records, and each later append past the end doubles
the table (`cc-sd-grow`), copying the old records and leaving the old
table behind in the bump arena.  A struct of n fields therefore costs
the header plus less than 2n records in all, instead of a fixed
worst-case block for every struct.  An LP64 record is 48 bytes, a SysV
one 72 (Ch 47 adds bitfield and matrix cells), and a legacy one 40.

Because records move when a table grows, a record address is only
good until the next append to the same descriptor.  Every caller
fetches the record it is about to fill after any append, and the one
side table keyed by record address — field qualification, Ch 34 — is
re-keyed through the `cc-sd-table-moved` hook.

The field limit is now a policy rather than a storage size.  LP64
code accepts 1023 members per struct or union, C99's translation limit
(§5.2.4.1); anonymous members count once flattened into their parent.
The largest records in the sources this compiler targets are far
below it: binutils 2.30 bfd's `struct elf_backend_data` has 143
members and GCC 4.0.4's largest, `JNINativeInterface` in libjava, 232.
`cc-sd-field-rec` checks the cap before it touches a record and stops
with code 50 on the 1024th member (`tests/gcc/large-record-check.py`).
The legacy subset keeps its 16-field limit: M2-Planet's largest struct
has 11 fields, its eight descriptors now take about 4.3 KB of the
32 KB legacy arena instead of 5.2 KB, and the legacy 17th-field error
remains code 50 (`tests/cc/die-50-struct-fields.c`).

The pointee descriptor at offset 32 of each field record is the
non-obvious piece.  When the parser sees `node->next->prev`, it needs
to know *which struct* `next` points at to resolve `prev` against that
struct's fields.  Carrying the pointee descriptor in the field record
lets chained arrow access navigate without looking the type up again
by name.

## 2. The symbol-table parallel arrays

The live-row limit is 8192. Scope pops recover rows, so this bounds
simultaneously visible declarations rather than all declarations ever seen.
`cc-sym-add` checks the next count before touching any column and keeps
error 60 for the first excess row. Reusing a row clears all five auxiliary
columns, including qualification provenance.

The original GCC 4.0.4 `c-parse.c` compilation reached the earlier 4096-row
limit before it exhausted its separately mapped arena. Doubling the row
limit adds 320 KiB across these ten columns. The direct System V signature
column also follows `cc-sym-cap`, adding another 32 KiB. The focused
`tests/gcc/symbol-capacity-check.py` gate verifies both boundary behavior
and that loading the compiler plus linker still fits the unchanged seed's
16 MiB mapping. Other limits remain independent: object records and ELF
symbols have their own capacities, and function signatures use arena bytes.
A larger symbol table alone does not establish a complete GCC build.

```forth file=070-cc-sym.fth
\ 070-cc-sym.fth — symbol table for the C-subset compiler.
\
\ Ten parallel arrays indexed by symbol id (cell[], 030-cc-io.fth):
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

[lit] 8192 constant cc-sym-cap

create cc-sym-name-addr  cc-sym-cap [lit] 8 * allot
create cc-sym-name-len   cc-sym-cap [lit] 8 * allot
create cc-sym-kind       cc-sym-cap [lit] 8 * allot
create cc-sym-type       cc-sym-cap [lit] 8 * allot
create cc-sym-val        cc-sym-cap [lit] 8 * allot
create cc-sym-extra      cc-sym-cap [lit] 8 * allot
create cc-sym-extra2     cc-sym-cap [lit] 8 * allot
create cc-sym-desc        cc-sym-cap [lit] 8 * allot
create cc-sym-inner       cc-sym-cap [lit] 8 * allot
\ Qualification provenance is separate from the encoded C type.
create cc-sym-qualified cc-sym-cap [lit] 8 * allot
variable cc-qualified-fields
: cc-field-qualified ( record -- flag )
  cc-qualified-fields @ begin, dup while,
    2dup [lit] 8 + @ = if, 2drop true exit, then, @
  repeat, 2drop [lit] 0 ;
: cc-field-set-qualified ( flag record -- )
  swap if,
    [lit] 16 cc-alloc dup >r [lit] 8 + !
    cc-qualified-fields @ r@ ! r> cc-qualified-fields !
  else, drop then, ;
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

Ten columns × 8192 rows × 8 bytes = 640 KiB, plus a 512-byte scope
stack (64 entries × 8 bytes).  That is the entire memory budget for
global declarations, function definitions, every local variable in
every function, every struct tag and every typedef.  The ten columns
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
  [lit] 0 r@ cc-sym-desc cell[] !
  [lit] 0 r@ cc-sym-inner cell[] !
  [lit] 0 r@ cc-sym-qualified cell[] !
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

Adding is half the job; the other half is finding a name again.
Ordinary names and explicit tag references enter through separate deferred
words. Both retain the historical lookup by default. The System V target
binds namespace-aware searches, allowing `struct stat` and the function
`stat` to coexist while retaining the same scope stack:

```forth file=070-cc-sym.fth
\ cc-sym-find ( name-addr name-len -- id-or-neg1 )
\ cc-name-find walks the entries newest first and returns at the first
\ match, which gives innermost-scope semantics: -1 means "not found",
\ anything >= 0 is the matched id.
\ The default keeps the original single lookup for the bootstrap dialect.
\ A target can separate C's ordinary and tag namespaces without replacing
\ the shared symbol records or their scope lifetime.
: cc-sym-find-default
  cc-sym-name-addr cc-sym-name-len cc-sym-count @ cc-name-find ;
defer cc-sym-find
defer cc-sym-find-tag
' cc-sym-find-default is cc-sym-find
' cc-sym-find-default is cc-sym-find-tag

```

The default `cc-sym-find` is Ch 21's `cc-name-find` over the two name columns,
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
: cc-sym-struct-desc-of
  cc-target-lp64 @ if, cc-sym-desc else, cc-sym-extra then, cell[] @ ;  \ ( id -- desc )
: cc-sym-set-struct-desc
  cc-target-lp64 @ if, cc-sym-desc else, cc-sym-extra then, cell[] ! ;
: cc-sym-array-inner-of cc-sym-inner cell[] @ ;
: cc-sym-set-array-inner cc-sym-inner cell[] ! ;  \ ( desc id -- )
\   call fixups: for an sk-func not yet defined, the head of the list of
\   `call rel32` sites waiting for its address.  This word gives the cell's
\   address, so the list code can push onto it (0 = no pending calls).
: cc-sym-call-fixups-default cc-sym-extra cell[] ;
defer cc-sym-call-fixups
' cc-sym-call-fixups-default is cc-sym-call-fixups    \ ( id -- cell )
\ The extra2 cell has one meaning, for sk-func only.
\   address fixups: the head of the list of `movabs rdi, imm64` sites that
\   load the function's address before it is defined (a forward-declared
\   function used as a value, e.g. `common_recursion(expression)` before
\   expression's body).  cc-parse-function patches each imm64 to the real
\   vaddr when it reaches the definition.  0 = no pending loads.
: cc-sym-addr-fixups-default cc-sym-extra2 cell[] ;
defer cc-sym-addr-fixups
' cc-sym-addr-fixups-default is cc-sym-addr-fixups
: cc-sym-object-size-of cc-sym-extra2 cell[] @ ;
: cc-sym-set-object-size cc-sym-extra2 cell[] ! ;    \ ( id -- cell )

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

The fixup-cell accessors are deferred, with these array cells as their
default. The System V target may instead return a cell in a persistent
implicit-external declaration record. That keeps a pending call alive when
its block-scoped symbol is removed, without extending the name's visibility.

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
  cat 010-lib.fth 0[2-9]0-cc-*.fth 1[01][0-9]-cc-*.fth
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
      cc-emit-entry-stub cc-emit-shims cc-register-late-shims
      cc-emit-external-protos cc-emit-libc-typedefs cc-parse-function-list
      [lit] 32 row  [lit] 33 row
      [lit] 32 cc-sym-val-of  dup cc-sd-total-size .n
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
32 tri 3 0
33 t 0 3
16 2 0 8
```

Ids 0–31 are filled before any C is read (Ch 31's eleven libc shims,
its eight late shims, a `memset` prototype, twelve built-in typedefs).
`tri` is row 32, kind 3
(`sk-struct`), and its val points at a descriptor in the arena: 16
bytes, 2 fields, `rows` at offset 0 and `stars` at offset 8.  `t` is
row 33, kind 0 (`sk-global`), base type 3 (`ty-struct`).  Those two
offsets become the `add rdi, 0x0` and `add rdi, 0x8` in every `t.rows`
and `t.stars` the compiler emits (Ch 28).

**Bootstrap relevance:** Stage-A reaches this layer through every
identifier lookup, local declaration, struct field, typedef, and
function symbol in the M2-Planet input.

## Exercises

1. **★★★ Trace.** Follow LP64 `ty-short` from its 2-byte `ty-size`
   through loads, stores, casts, and array strides.  Which parser
   decisions must change as well as the type helpers?  Verify that
   switching LP64 off retains the original generated bytes.

2. **★★ Verify.** Legacy struct fields max out at 16 per struct.  Find the largest
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
16+40·N-byte legacy or 32+48·N-byte LP64 descriptor.  Identical name resolution gives identical
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
